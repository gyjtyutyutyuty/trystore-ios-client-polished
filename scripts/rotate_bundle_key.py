#!/usr/bin/env python3
"""Rotate the patch bundle key and re-wrap every served package.

The bundle key protects the content key of each `3105PATCH` package and, through
HKDF, the sealed `TSC2` character vault. Treat it as burned the moment it leaves
the Worker: a key that opened yesterday's blobs must not open tomorrow's.

Order of operations:

  1. Read the old and new 32-byte bundle keys from files (never argv, never a
     command line that lands in shell history).
  2. Re-wrap every package served by the feed under the new key, including the
     packages stored with an in-band `publicContentKey` and no wrapper at all.
  3. Rewrite each project manifest with the new digest, size and version.
  4. Re-seal the committed character vault and update its fingerprint.
  5. Flip `feed_key_state` so the Worker serves the new version.
  6. Publish the vault after the flip.

Set `APP_BUNDLE_KEY_V2` on `trystore-patch-feed` **before** running `--apply`,
otherwise the Worker has no key version 2 to hand out.

Run with `--dry-run` first. The old Worker secret stays in place until every
device has refreshed, so a botched rotation can be rolled back by flipping
`feed_key_state` back to the old version.

Usage:
    python scripts/rotate_bundle_key.py \
        --old-key-file C:/keys/trystore-v1.txt \
        --new-key-file C:/keys/trystore-v2.txt
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import hmac
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "cloudflare" / "wrangler.toml"
VAULT_DIR = ROOT / "build_support" / "CharacterVaultTSC2"
VAULT_FILES = VAULT_DIR / "CharacterVault"
VAULT_MANIFEST = VAULT_DIR / "manifest.json"
PUBLISH_VAULT = ROOT / "scripts" / "publish_character_vault.py"

MAGIC = b"3105PATCH\x00"
PROJECTS = ("trystore", "apple-music", "hyper-regedit")
SALT = b"trystore-character-vault-v1"
INFO = b"TSC2/key"
TSC_MAGIC = b"TSC2"
TSC_NONCE = 16
TSC_TAG = 16
BLOCK = 32
ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")


def fail(message: str) -> None:
    raise SystemExit(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_key(path: Path) -> bytes:
    try:
        raw = base64.b64decode(path.read_text(encoding="utf-8").strip(), validate=True)
    except Exception as error:  # noqa: BLE001 - the message is the point
        fail(f"{path} is not valid base64: {error}")
    if len(raw) != 32:
        fail(f"{path} must decode to 32 bytes, got {len(raw)}")
    return raw


def npx() -> str:
    executable = shutil.which("npx.cmd") or shutil.which("npx")
    if not executable:
        fail("npx is required")
    return executable


def run(command: list[str]) -> bytes:
    completed = subprocess.run(
        command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace")[-800:]
        fail(f"{' '.join(command[:3])} failed: {detail}")
    return ANSI.sub(b"", completed.stdout)


def kv_keys() -> list[str]:
    output = run(
        [npx(), "wrangler", "kv", "key", "list", "--binding", "PATCHES",
         "--remote", "-c", str(CONFIG)]
    ).decode("utf-8", errors="replace")
    start = output.find("[")
    if start < 0:
        fail("could not parse kv key list")
    return [row["name"] for row in json.loads(output[start:])]


def kv_get(key: str) -> bytes:
    completed = subprocess.run(
        [npx(), "wrangler", "kv", "key", "get", key,
         "--binding", "PATCHES", "--remote", "-c", str(CONFIG)],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        fail(f"kv get {key} failed: {completed.stderr.decode(errors='replace')[-400:]}")
    return completed.stdout


def kv_put(key: str, data: bytes, apply: bool) -> None:
    print(f"  {'put' if apply else 'would put'} {key} ({len(data)} bytes)")
    if not apply:
        return
    handle = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")
    try:
        handle.write(data)
        handle.close()
        run([
            npx(), "wrangler", "kv", "key", "put", key,
            "--path", handle.name, "--binding", "PATCHES",
            "--remote", "-c", str(CONFIG),
        ])
    finally:
        try:
            os.unlink(handle.name)
        except OSError:
            pass


def key_aad(envelope: dict) -> bytes:
    version = int(envelope.get("keyAADVersion") or envelope["schemaVersion"])
    return f"3105PATCH/v{version}/key/{envelope['packageID']}".encode()


def open_content_key(envelope: dict, bundle_key: bytes) -> bytes:
    wrapped = envelope.get("wrappedContentKey")
    if not wrapped or len(wrapped) <= 12:
        raise ValueError("missing wrapped content key")
    return AESGCM(bundle_key).decrypt(wrapped[:12], wrapped[12:], key_aad(envelope))


def seal_content_key(envelope: dict, content_key: bytes, bundle_key: bytes) -> bytes:
    nonce = os.urandom(12)
    return nonce + AESGCM(bundle_key).encrypt(nonce, content_key, key_aad(envelope))


def rewrap_package(blob: bytes, old_key: bytes, new_key: bytes,
                   version: int) -> tuple[bytes, bool]:
    """Returns (new blob, changed). Raises when neither key opens the envelope."""
    if not blob.startswith(MAGIC):
        raise ValueError("not a 3105PATCH envelope")
    envelope = plistlib.loads(blob[len(MAGIC):])
    if envelope.get("isPasswordProtected"):
        return blob, False

    if envelope.get("wrappingScheme") == "bundle" and envelope.get("wrappedContentKey"):
        try:
            content_key = open_content_key(envelope, old_key)
        except Exception:
            content_key = open_content_key(envelope, new_key)  # already rotated
            if int(envelope.get("bundleKeyVersion") or 0) == version:
                return blob, False
    elif envelope.get("publicContentKey"):
        # Stored with the content key in-band: anyone who reads the blob has
        # the payload. Rotating is the moment to close that.
        content_key = envelope["publicContentKey"]
    else:
        raise ValueError("no content key")

    envelope["wrappedContentKey"] = seal_content_key(envelope, content_key, new_key)
    envelope["wrappingScheme"] = "bundle"
    envelope["keyAADVersion"] = int(envelope["schemaVersion"])
    envelope["bundleKeyVersion"] = version
    envelope.pop("publicContentKey", None)
    rebuilt = MAGIC + plistlib.dumps(envelope, fmt=plistlib.FMT_BINARY)
    if open_content_key(plistlib.loads(rebuilt[len(MAGIC):]), new_key) != content_key:
        raise ValueError("re-wrapped key does not authenticate")
    return rebuilt, True


def hkdf(key: bytes) -> bytes:
    prk = hmac.new(SALT, key, hashlib.sha256).digest()
    return hmac.new(prk, INFO + b"\x01", hashlib.sha256).digest()


def open_tsc(blob: bytes, key: bytes) -> bytes:
    if len(blob) <= 4 + TSC_NONCE + TSC_TAG or not blob.startswith(TSC_MAGIC):
        raise ValueError("not a TSC2 blob")
    nonce = blob[4:4 + TSC_NONCE]
    tag = blob[4 + TSC_NONCE:4 + TSC_NONCE + TSC_TAG]
    cipher = blob[4 + TSC_NONCE + TSC_TAG:]
    expected = hmac.new(key, nonce + cipher, hashlib.sha256).digest()[:TSC_TAG]
    if not hmac.compare_digest(expected, tag):
        raise ValueError("tag mismatch")
    plain = bytearray(cipher)
    offset = 0
    counter = 0
    while offset < len(plain):
        block = hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()
        take = min(BLOCK, len(plain) - offset)
        for index in range(take):
            plain[offset + index] ^= block[index]
        offset += take
        counter += 1
    return bytes(plain)


def seal_tsc(plain: bytes, key: bytes) -> bytes:
    nonce = os.urandom(TSC_NONCE)
    cipher = bytearray(plain)
    offset = 0
    counter = 0
    while offset < len(cipher):
        block = hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()
        take = min(BLOCK, len(cipher) - offset)
        for index in range(take):
            cipher[offset + index] ^= block[index]
        offset += take
        counter += 1
    cipher = bytes(cipher)
    tag = hmac.new(key, nonce + cipher, hashlib.sha256).digest()[:TSC_TAG]
    return TSC_MAGIC + nonce + tag + cipher


def reseal_vault(old_key: bytes, new_key: bytes, apply: bool) -> bytes:
    manifest = json.loads(VAULT_MANIFEST.read_text(encoding="utf-8"))
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        fail("vault manifest has no files map")
    old_vault = hkdf(old_key)
    new_vault = hkdf(new_key)
    changed = 0
    for relative, entry in sorted(files.items()):
        path = VAULT_FILES / relative
        blob = path.read_bytes()
        try:
            plain = open_tsc(blob, old_vault)
        except ValueError:
            plain = open_tsc(blob, new_vault)  # already rotated
        sealed = seal_tsc(plain, new_vault)
        if open_tsc(sealed, new_vault) != plain:
            fail(f"vault round-trip failed: {relative}")
        entry["sha256"] = sha256_bytes(sealed)
        entry["size"] = len(sealed)
        entry["magic"] = "TSC2"
        if sealed != blob:
            changed += 1
            if apply:
                path.write_bytes(sealed)
    manifest["keyFingerprint"] = sha256_bytes(new_key)
    if apply:
        VAULT_MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"vault: {changed}/{len(files)} blobs re-sealed, "
          f"fingerprint {manifest['keyFingerprint']}")
    return new_vault


def update_manifest(manifest: dict, updates: dict[str, tuple[str, int]],
                    version: int) -> dict:
    for patch in manifest.get("patches", []):
        name = patch.get("file")
        if name not in updates:
            continue
        digest, size = updates[name]
        patch["sha256"] = digest
        patch["size"] = size
        patch["keyVersion"] = version
        url = str(patch.get("url") or "")
        if url:
            parts = urlsplit(url)
            patch["url"] = urlunsplit(parts._replace(query=f"v={digest}"))
    manifest["updatedAt"] = dt.datetime.now(dt.timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )
    return manifest


def d1(sql: str, apply: bool) -> None:
    print(f"  {'d1' if apply else 'would d1'}: {sql}")
    if not apply:
        return
    run([npx(), "wrangler", "d1", "execute", "DB", "--remote",
         "-c", str(CONFIG), "--command", sql, "--yes"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--old-key-file", type=Path, required=True)
    parser.add_argument("--new-key-file", type=Path, required=True)
    parser.add_argument("--key-version", type=int, default=2, choices=(1, 2))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    old_key = read_key(args.old_key_file)
    new_key = read_key(args.new_key_file)
    if old_key == new_key:
        fail("old and new keys are identical")
    version = args.key_version

    keys = kv_keys()
    print(f"{len(keys)} KV keys; target bundle-key version {version}")

    # Build every replacement before writing anything. A failure halfway
    # through a write loop would leave a project with a manifest that points at
    # blobs the Worker has not stored yet.
    pending: list[tuple[str, bytes]] = []
    manifests: list[tuple[str, bytes]] = []
    for project in PROJECTS:
        prefix = f"patches/{project}/"
        names = [k for k in keys if k.startswith(prefix) and k != prefix + "manifest.json"]
        updates: dict[str, tuple[str, int]] = {}
        changed = 0
        for key in sorted(names):
            name = key[len(prefix):]
            blob = kv_get(key)
            try:
                rebuilt, wrapped = rewrap_package(blob, old_key, new_key, version)
            except Exception as error:  # noqa: BLE001
                fail(f"{key}: {error}")
            if wrapped:
                pending.append((key, rebuilt))
                changed += 1
            updates[name] = (sha256_bytes(rebuilt), len(rebuilt))
            print(f"{project:14} {name[:46]:48} "
                  f"{'wrap' if wrapped else 'keep':4} {len(rebuilt):>9}")

        manifest = json.loads(kv_get(prefix + "manifest.json"))
        manifest = update_manifest(manifest, updates, version)
        served = [p.get("file") for p in manifest.get("patches", [])]
        missing = [n for n in served if n not in updates]
        if missing:
            fail(f"{project}: manifest lists files with no KV blob: {missing[:3]}")
        manifests.append(
            (prefix + "manifest.json",
             (json.dumps(manifest, indent=2) + "\n").encode())
        )
        print(f"{project}: {len(served)} served, {changed} blobs to write")

    reseal_vault(old_key, new_key, args.apply)

    for key, data in pending:
        kv_put(key, data, args.apply)
    for key, data in manifests:
        kv_put(key, data, args.apply)

    if args.apply:
        d1("DELETE FROM feed_blobs WHERE project IN "
           "('trystore','apple-music','hyper-regedit')", True)
        for project in PROJECTS:
            d1(
                "INSERT INTO feed_key_state(project,key_version,rotated_at) VALUES("
                f"'{project}',{version},CAST(strftime('%s','now') AS INTEGER)) "
                "ON CONFLICT(project) DO UPDATE SET key_version=excluded.key_version,"
                "rotated_at=excluded.rotated_at",
                True,
            )
        completed = subprocess.run([sys.executable, str(PUBLISH_VAULT)], cwd=ROOT)
        if completed.returncode != 0:
            fail("vault publish failed")
    else:
        print("dry run: no KV, D1 or vault writes")

    print("done; verify /bundle-key/fingerprint matches the new key fingerprint")
    return 0


if __name__ == "__main__":
    sys.exit(main())
