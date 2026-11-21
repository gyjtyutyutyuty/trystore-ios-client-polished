#!/usr/bin/env python3
"""Re-seal bundled CharacterVault art from legacy TSC1 to release TSC2.

TSC1 uses the historical split key that used to live in CharacterVault.swift.
TSC2 derives its key from the server-released patch bundle key:

    HKDF-SHA256(bundleKey, salt="trystore-character-vault-v1",
                info="TSC2/key", length=32)

The archive step runs this script so a release IPA never carries the static
TSC1 key or TSC1 payloads. Debug builds still read TSC1 from a checkout.

Usage:
    python scripts/rewrap_character_vault.py --app build/Payload/SupportPatch.app \
        --bundle-key "$TRYSTORE_BUNDLE_KEY"
    python scripts/rewrap_character_vault.py --app ... --bundle-key ... --verify
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import os
import sys
from pathlib import Path

LEGACY_KEY = bytes.fromhex(
    "05d6ff83229ba99a123d6371c0cbb89addd3f85d0709e592cbef444423178abf"
)
MAGIC1 = b"TSC1"
MAGIC2 = b"TSC2"
NONCE_LEN = 16
TAG_LEN = 16
BLOCK = 32
SALT = b"trystore-character-vault-v1"
INFO = b"TSC2/key"


def hkdf_sha256(ikm: bytes, salt: bytes, info: bytes, length: int) -> bytes:
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    output = bytearray()
    block = b""
    counter = 1
    while len(output) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha256).digest()
        output.extend(block)
        counter += 1
    return bytes(output[:length])


def stream(key: bytes, nonce: bytes, counter: int) -> bytes:
    return hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()


def xor_stream(key: bytes, nonce: bytes, cipher: bytes) -> bytes:
    plain = bytearray(cipher)
    offset = 0
    counter = 0
    while offset < len(plain):
        block = stream(key, nonce, counter)
        take = min(BLOCK, len(plain) - offset)
        for index in range(take):
            plain[offset + index] ^= block[index]
        offset += take
        counter += 1
    return bytes(plain)


def open_blob(blob: bytes, key: bytes) -> bytes:
    if len(blob) <= 4 + NONCE_LEN + TAG_LEN:
        raise ValueError("blob is too short")
    magic = blob[:4]
    if magic not in (MAGIC1, MAGIC2):
        raise ValueError("unknown magic")
    nonce = blob[4:4 + NONCE_LEN]
    tag = blob[4 + NONCE_LEN:4 + NONCE_LEN + TAG_LEN]
    cipher = blob[4 + NONCE_LEN + TAG_LEN:]
    expected = hmac.new(key, nonce + cipher, hashlib.sha256).digest()[:TAG_LEN]
    if not hmac.compare_digest(expected, tag):
        raise ValueError("tag mismatch")
    return xor_stream(key, nonce, cipher)


def seal_blob(plain: bytes, key: bytes) -> bytes:
    nonce = os.urandom(NONCE_LEN)
    cipher = xor_stream(key, nonce, plain)
    tag = hmac.new(key, nonce + cipher, hashlib.sha256).digest()[:TAG_LEN]
    return MAGIC2 + nonce + tag + cipher


def bundle_key(value: str) -> bytes:
    try:
        raw = base64.b64decode(value, validate=True)
    except Exception as error:
        raise SystemExit(f"bundle key is not valid base64: {error}") from error
    if len(raw) != 32:
        raise SystemExit(f"bundle key must decode to 32 bytes, got {len(raw)}")
    return raw


def vault_files(app: Path) -> list[Path]:
    root = app / "CharacterVault"
    if not root.is_dir():
        raise SystemExit(f"CharacterVault not found under {app}")
    return sorted(p for p in root.rglob("*.tsc") if p.is_file())


def verify(app: Path, derived: bytes) -> int:
    files = vault_files(app)
    if not files:
        raise SystemExit("no CharacterVault/*.tsc files")
    for path in files:
        blob = path.read_bytes()
        if not blob.startswith(MAGIC2):
            raise SystemExit(f"release vault carries a non-TSC2 blob: {path}")
        try:
            open_blob(blob, derived)
        except ValueError as error:
            raise SystemExit(f"invalid TSC2 blob {path}: {error}") from error
    print(f"ok    {len(files)} CharacterVault blobs are TSC2 and authenticate")
    return 0


def rewrap(app: Path, derived: bytes, verify_only: bool) -> int:
    files = vault_files(app)
    if not files:
        raise SystemExit("no CharacterVault/*.tsc files")
    if verify_only:
        return verify(app, derived)

    rewritten = 0
    for path in files:
        blob = path.read_bytes()
        if blob.startswith(MAGIC2):
            try:
                open_blob(blob, derived)
            except ValueError as error:
                raise SystemExit(f"existing TSC2 blob does not match this key: {path}") from error
            continue
        if not blob.startswith(MAGIC1):
            raise SystemExit(f"unknown vault blob format: {path}")
        try:
            plain = open_blob(blob, LEGACY_KEY)
        except ValueError as error:
            raise SystemExit(f"legacy TSC1 blob failed authentication: {path}: {error}") from error
        path.write_bytes(seal_blob(plain, derived))
        rewritten += 1
    print(f"ok    re-sealed {rewritten}/{len(files)} CharacterVault blobs as TSC2")
    return verify(app, derived)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--bundle-key", required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    derived = hkdf_sha256(bundle_key(args.bundle_key), SALT, INFO, 32)
    return rewrap(args.app, derived, args.verify)


if __name__ == "__main__":
    sys.exit(main())
