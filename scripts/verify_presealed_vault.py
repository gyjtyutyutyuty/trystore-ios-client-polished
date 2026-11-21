#!/usr/bin/env python3
"""Verify a pre-sealed TSC2 vault against its committed manifest.

The release archive uses the pre-sealed vault when no bundle key is available
in the build environment. The manifest pins every blob's SHA-256 and the key
fingerprint the feed publishes, so a stale vault fails the build instead of
shipping art the app cannot open.

Usage:
    python scripts/verify_presealed_vault.py --vault build_support/CharacterVaultTSC2/CharacterVault \
        --manifest build_support/CharacterVaultTSC2/manifest.json --fingerprint <feed hex>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

MAGIC = b"TSC2"
HEX = set("0123456789abcdef")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def is_hex(value: str) -> bool:
    return len(value) == 64 and all(character in HEX for character in value.lower())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--fingerprint", default="")
    args = parser.parse_args()

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except Exception as error:
        fail(f"cannot read manifest: {error}")
    files = manifest.get("files")
    fingerprint = str(manifest.get("keyFingerprint", "")).lower()
    if not isinstance(files, dict) or not files:
        fail("manifest has no files")
    if not is_hex(fingerprint):
        fail("manifest keyFingerprint is not a SHA-256 hex digest")
    if args.fingerprint and fingerprint != args.fingerprint.strip().lower():
        fail(
            "pre-sealed vault does not match the feed key; regenerate it with "
            "scripts/rewrap_character_vault.py"
        )

    if not args.vault.is_dir():
        fail(f"vault not found at {args.vault}")
    present = {
        path.relative_to(args.vault).as_posix(): path
        for path in args.vault.rglob("*.tsc")
        if path.is_file()
    }
    missing = sorted(set(files) - set(present))
    extra = sorted(set(present) - set(files))
    if missing:
        fail(f"missing vault blobs: {', '.join(missing[:4])}")
    if extra:
        fail(f"unexpected vault blobs: {', '.join(extra[:4])}")

    for relative in sorted(files):
        expected = files[relative]
        blob = present[relative].read_bytes()
        if not blob.startswith(MAGIC):
            fail(f"blob is not TSC2: {relative}")
        if len(blob) != int(expected.get("size", -1)):
            fail(f"size mismatch: {relative}")
        if hashlib.sha256(blob).hexdigest() != str(expected.get("sha256", "")).lower():
            fail(f"digest mismatch: {relative}")

    print(f"ok    {len(files)} pre-sealed TSC2 blobs match the manifest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
