"""Pack CharacterModels/ into the encrypted CharacterVault/ the app ships.

The IPA used to carry rouk.obj, sakura.obj and their textures as plain files --
anyone with a zip tool had the art. The vault keeps the same folder shape but
every file is a TSC1 blob: 4-byte magic, 16-byte nonce, 16-byte HMAC tag, then
an HMAC-SHA256 keystream XOR of the plaintext.

Usage:
    set TRYSTORE_CHARACTER_KEY=<64 hex chars>
    python scripts/pack_character_assets.py
"""

import hashlib
import hmac
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "ThreeOneOSFive", "CharacterModels")
TARGET = os.path.join(ROOT, "ThreeOneOSFive", "CharacterVault")

MAGIC = b"TSC1"
NONCE_LEN = 16
TAG_LEN = 16
BLOCK = 32


def keystream_block(key: bytes, nonce: bytes, counter: int) -> bytes:
    return hmac.new(key, nonce + counter.to_bytes(8, "big"), hashlib.sha256).digest()


def seal(key: bytes, plaintext: bytes, nonce: bytes) -> bytes:
    out = bytearray(len(plaintext))
    counter = 0
    offset = 0
    while offset < len(plaintext):
        block = keystream_block(key, nonce, counter)
        take = min(BLOCK, len(plaintext) - offset)
        for i in range(take):
            out[offset + i] = plaintext[offset + i] ^ block[i]
        offset += take
        counter += 1
    tag = hmac.new(key, nonce + bytes(out), hashlib.sha256).digest()[:TAG_LEN]
    return MAGIC + nonce + tag + bytes(out)


def main() -> int:
    key_hex = os.environ.get("TRYSTORE_CHARACTER_KEY", "").strip()
    if len(key_hex) != 64:
        print("TRYSTORE_CHARACTER_KEY must be 64 hex characters", file=sys.stderr)
        return 2
    key = bytes.fromhex(key_hex)

    if not os.path.isdir(SOURCE):
        print("missing source folder: " + SOURCE, file=sys.stderr)
        return 2

    written = 0
    for folder, _, files in os.walk(SOURCE):
        for name in sorted(files):
            src = os.path.join(folder, name)
            rel = os.path.relpath(src, SOURCE)
            dst = os.path.join(TARGET, rel + ".tsc")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(src, "rb") as handle:
                plaintext = handle.read()
            nonce = os.urandom(NONCE_LEN)
            with open(dst, "wb") as handle:
                handle.write(seal(key, plaintext, nonce))
            written += 1

    print("sealed %d files into %s" % (written, TARGET))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
