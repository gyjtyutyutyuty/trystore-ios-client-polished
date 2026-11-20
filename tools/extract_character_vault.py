#!/usr/bin/env python3
"""Decrypt the CharacterVault TSC1 blobs shipped inside an IPA.

TSC1 layout: 4-byte magic, 16-byte nonce, 16-byte HMAC-SHA256 tag, then the
plaintext XORed with an HMAC-SHA256 keystream.

The key is not a server secret. CharacterVault.swift keeps two 32-byte halves
in the binary and XORs them at runtime; this script uses the reconstructed key
`05d6ff83...178abf`, verifies every tag, and writes the plaintext tree.

Usage:
    python tools/extract_character_vault.py in.ipa out_dir
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import zipfile
from pathlib import Path

MAGIC = b"TSC1"
NONCE_LEN = 16
TAG_LEN = 16
BLOCK = 32
VAULT_KEY = bytes.fromhex(
    "05d6ff83229ba99a123d6371c0cbb89addd3f85d0709e592cbef444423178abf"
)


def keystream(key: bytes, nonce: bytes, counter: int) -> bytes:
    return hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()


def decrypt(blob: bytes) -> bytes:
    if len(blob) <= 4 + NONCE_LEN + TAG_LEN or not blob.startswith(MAGIC):
        raise ValueError("not a TSC1 blob")
    nonce = blob[4:4 + NONCE_LEN]
    tag = blob[4 + NONCE_LEN:4 + NONCE_LEN + TAG_LEN]
    cipher = blob[4 + NONCE_LEN + TAG_LEN:]
    expected = hmac.new(VAULT_KEY, nonce + cipher, hashlib.sha256).digest()[:TAG_LEN]
    if not hmac.compare_digest(expected, tag):
        raise ValueError("TSC1 tag mismatch")

    plain = bytearray(cipher)
    counter = 0
    offset = 0
    while offset < len(plain):
        stream = keystream(VAULT_KEY, nonce, counter)
        take = min(BLOCK, len(plain) - offset)
        for index in range(take):
            plain[offset + index] ^= stream[index]
        offset += take
        counter += 1
    return bytes(plain)


def extract(ipa: Path, out_dir: Path) -> dict:
    written = []
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist() if n.endswith(".tsc") and "/CharacterVault/" in n]
        if not names:
            raise SystemExit("no CharacterVault/*.tsc entries in this IPA")
        for name in sorted(names):
            plain = decrypt(archive.read(name))
            relative = name.split("/CharacterVault/", 1)[1][:-4]
            target = out_dir / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(plain)
            written.append({"source": name, "output": str(target), "bytes": len(plain)})
    return {"entries": written, "count": len(written)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()

    result = extract(args.ipa, args.out)
    print(f"extracted {result['count']} files into {args.out}")
    for entry in result["entries"]:
        print(f"  {entry['bytes']:9d}  {entry['output']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
