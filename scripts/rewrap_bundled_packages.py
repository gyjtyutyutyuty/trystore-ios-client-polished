#!/usr/bin/env python3
"""Wrap bundled patch content keys under the app bundle key.

The envelope no longer carries a usable content key. Each package keeps its
AES-GCM payload untouched; only the 32-byte content key is rewrapped under the
key the feed releases after licence and device validation.

Usage:
    TRYSTORE_BUNDLE_KEY=<base64 32 bytes> python scripts/rewrap_bundled_packages.py
"""
from __future__ import annotations

import base64
import os
import plistlib
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"
MAGIC = b"3105PATCH\0"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def bundle_key() -> bytes:
    raw = os.environ.get("TRYSTORE_BUNDLE_KEY", "").strip()
    if not raw:
        fail("TRYSTORE_BUNDLE_KEY is required")
    try:
        key = base64.b64decode(raw, validate=True)
    except Exception as error:
        fail(f"TRYSTORE_BUNDLE_KEY is not valid base64: {error}")
    if len(key) != 32:
        fail("TRYSTORE_BUNDLE_KEY must decode to 32 bytes")
    return key


def rewrap(path: Path, key: bytes) -> bool:
    data = path.read_bytes()
    if not data.startswith(MAGIC):
        fail(f"invalid package header: {path.name}")
    envelope = plistlib.loads(data[len(MAGIC):])
    if envelope.get("wrappingScheme") == "bundle":
        return False
    content_key = envelope.get("publicContentKey")
    if not isinstance(content_key, bytes) or len(content_key) != 32:
        fail(f"package has no content key to wrap: {path.name}")

    package_id = envelope["packageID"]
    version = envelope["schemaVersion"]
    aad = f"3105PATCH/v{version}/key/{package_id}".encode()
    nonce = os.urandom(12)
    sealed = AESGCM(key).encrypt(nonce, content_key, aad)

    envelope.pop("publicContentKey", None)
    envelope["wrappedContentKey"] = nonce + sealed
    envelope["wrappingScheme"] = "bundle"
    envelope["keyAADVersion"] = version
    path.write_bytes(MAGIC + plistlib.dumps(envelope, fmt=plistlib.FMT_BINARY))
    return True


def verify(path: Path, key: bytes) -> None:
    data = path.read_bytes()
    envelope = plistlib.loads(data[len(MAGIC):])
    if envelope.get("publicContentKey") is not None:
        fail(f"content key still public: {path.name}")
    wrapped = envelope.get("wrappedContentKey")
    if not isinstance(wrapped, bytes) or len(wrapped) != 60:
        fail(f"wrapped key missing or malformed: {path.name}")
    aad = f"3105PATCH/v{envelope['schemaVersion']}/key/{envelope['packageID']}".encode()
    content_key = AESGCM(key).decrypt(wrapped[:12], wrapped[12:], aad)
    if len(content_key) != 32:
        fail(f"content key length wrong: {path.name}")
    payload_aad = (
        f"3105PATCH/v{envelope['schemaVersion']}/payload/{envelope['packageID']}"
    ).encode()
    ciphertext = envelope["encryptedPayload"]
    plaintext = AESGCM(content_key).decrypt(
        ciphertext[:12], ciphertext[12:], payload_aad
    )
    payload = plistlib.loads(plaintext)
    project_id = payload["project"]["id"]
    if str(project_id).upper() != str(envelope["packageID"]).upper():
        fail(f"payload identity mismatch: {path.name}")


def main() -> None:
    key = bundle_key()
    changed = 0
    packages = sorted(PATCH_DIR.glob("*.TRYSTORE"))
    if not packages:
        fail("no bundled packages found")
    for path in packages:
        if rewrap(path, key):
            changed += 1
        verify(path, key)
        print(f"{path.name}: wrapped")
    print(f"{len(packages)} packages verified, {changed} rewritten")


if __name__ == "__main__":
    main()
