#!/usr/bin/env python3
"""Publish the sealed character vault to the patch-feed Worker's KV namespace.

The IPA no longer carries `CharacterVault`. The Worker serves the sealed blobs
and a signed manifest to a licensed device, so the vault must exist in KV
before an archive that relies on it is installed.

Usage:
    python scripts/publish_character_vault.py [--dry-run]

Reads:
    build_support/CharacterVaultTSC2/manifest.json
    build_support/CharacterVaultTSC2/CharacterVault/<path>

Writes:
    build_support/CharacterVaultTSC2/feed-manifest.json
    KV keys under vault/trystore/
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VAULT_DIR = ROOT / "build_support" / "CharacterVaultTSC2" / "CharacterVault"
SOURCE_MANIFEST = ROOT / "build_support" / "CharacterVaultTSC2" / "manifest.json"
FEED_MANIFEST = ROOT / "build_support" / "CharacterVaultTSC2" / "feed-manifest.json"
WRANGLER_CONFIG = ROOT / "cloudflare" / "wrangler.toml"
KV_PREFIX = "vault/trystore/"
MANIFEST_KEY = KV_PREFIX + "manifest.json"
ALLOWED_PREFIXES = ("rouk/", "sakura/")


def fail(message: str) -> None:
    raise SystemExit(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_feed_manifest() -> dict:
    if not SOURCE_MANIFEST.is_file():
        fail(f"missing {SOURCE_MANIFEST}")
    source = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    fingerprint = str(source.get("keyFingerprint") or "").strip()
    if len(fingerprint) != 64 or any(c not in "0123456789abcdefABCDEF" for c in fingerprint):
        fail("manifest.json keyFingerprint must be a 64-character hex digest")
    if not VAULT_DIR.is_dir():
        fail(f"missing {VAULT_DIR}")

    listed = source.get("files")
    if not isinstance(listed, dict) or not listed:
        fail("manifest.json has no files map")

    files = []
    for relative in sorted(listed):
        if not relative.startswith(ALLOWED_PREFIXES) or not relative.endswith(".tsc"):
            fail(f"refusing unexpected vault path: {relative}")
        if ".." in relative.split("/"):
            fail(f"refusing traversal in vault path: {relative}")
        path = VAULT_DIR / relative
        if not path.is_file():
            fail(f"missing vault blob: {relative}")
        data = path.read_bytes()
        expected = listed[relative]
        if not data.startswith(b"TSC2"):
            fail(f"not a TSC2 blob: {relative}")
        if len(data) != int(expected.get("size", -1)):
            fail(f"size mismatch for {relative}")
        if sha256(path) != str(expected.get("sha256", "")).lower():
            fail(f"digest mismatch for {relative}")
        files.append({
            "path": relative,
            "sha256": str(expected["sha256"]).lower(),
            "size": len(data),
        })

    if not any(entry["path"] == "rouk/rouk.obj.tsc" for entry in files):
        fail("vault is missing rouk/rouk.obj.tsc")
    if not any(entry["path"] == "sakura/sakura.obj.tsc" for entry in files):
        fail("vault is missing sakura/sakura.obj.tsc")

    content = hashlib.sha256(
        "".join(f"{entry['path']}:{entry['sha256']}\n" for entry in files).encode("utf-8")
    ).hexdigest()

    return {
        "schemaVersion": 1,
        "project": "trystore",
        "version": content,
        "keyFingerprint": fingerprint.lower(),
        "files": files,
    }


def wrangler() -> list[str]:
    executable = shutil.which("npx") or shutil.which("npx.cmd")
    if not executable:
        fail("npx is required to publish the vault")
    return [executable, "wrangler", "kv", "key", "put"]


def put(key: str, source: Path, dry_run: bool) -> None:
    command = wrangler() + [
        key,
        "--path",
        str(source),
        "--binding",
        "PATCHES",
        "--config",
        str(WRANGLER_CONFIG),
        "--remote",
    ]
    print(f"{'would upload' if dry_run else 'uploading'} {key}")
    if dry_run:
        return
    completed = subprocess.run(command, cwd=ROOT, text=True)
    if completed.returncode != 0:
        fail(f"wrangler failed for {key}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = build_feed_manifest()
    FEED_MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"version {manifest['version']} ({len(manifest['files'])} files)")

    for entry in manifest["files"]:
        put(KV_PREFIX + entry["path"], VAULT_DIR / entry["path"], args.dry_run)
    put(MANIFEST_KEY, FEED_MANIFEST, args.dry_run)

    if not args.dry_run:
        print("vault published; run the archive step to ship a client that fetches it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
