#!/usr/bin/env python3
"""Verify every offline patch package is shipped in the app bundle."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"
MANIFEST = PATCH_DIR / "manifest.json"

def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")

def verify(directory: Path, label: str) -> int:
    try:
        manifest = json.loads((directory / "manifest.json").read_text())
    except Exception as exc:
        fail(f"{label}: patch manifest missing or invalid: {exc}")
    patches = manifest.get("patches")
    if not isinstance(patches, list) or len(patches) != 11:
        fail(f"{label}: expected 11 bundled packages, found {len(patches) if isinstance(patches, list) else 'invalid'}")
    seen = set()
    for item in patches:
        name = item.get("file", "")
        if not name or Path(name).name != name or not name.lower().endswith(".trystore") or name in seen:
            fail(f"{label}: unsafe, unsupported, or duplicate package name: {name!r}")
        seen.add(name)
        path = directory / name
        if not path.is_file():
            fail(f"{label}: missing patch package {name}")
        data = path.read_bytes()
        if len(data) != item.get("size"):
            fail(f"{label}: wrong size for {name}")
        digest = hashlib.sha256(data).hexdigest()
        if digest.lower() != str(item.get("sha256", "")).lower():
            fail(f"{label}: checksum mismatch for {name}")
    if len(seen) != 11:
        fail(f"{label}: incomplete patch set")
    print(f"PASS: {label} contains all 11 patch packages with matching SHA-256 checksums")
    return len(seen)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    verify(PATCH_DIR, "source package folder")
    if args.app:
        verify(args.app / "Patches", "built app")
