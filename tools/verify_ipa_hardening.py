#!/usr/bin/env python3
"""Fail a build when the shipped IPA is missing the release hardening.

Checked:
  * UIFileSharingEnabled is false
  * LSSupportsOpeningDocumentsInPlace is false
  * the main executable carries LC_SEGMENT_64 __RESTRICT with __restrict

Usage:
    python tools/verify_ipa_hardening.py build/SupportPatch-unsigned.ipa
"""

from __future__ import annotations

import argparse
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

LC_SEGMENT_64 = 0x19


def inspect(binary: bytes) -> tuple[bool, bool]:
    if struct.unpack_from("<I", binary, 0)[0] != 0xFEEDFACF:
        raise SystemExit("executable is not a thin 64-bit Mach-O")
    count = struct.unpack_from("<I", binary, 16)[0]
    offset = 32
    has_segment = False
    has_section = False
    for _ in range(count):
        command, size = struct.unpack_from("<II", binary, offset)
        if size < 8:
            raise SystemExit("malformed load command")
        if command == LC_SEGMENT_64:
            name = binary[offset + 8:offset + 24].split(b"\x00")[0]
            if name == b"__RESTRICT":
                has_segment = True
                sections = struct.unpack_from("<I", binary, offset + 64)[0]
                for index in range(sections):
                    base = offset + 72 + index * 80
                    section_name = binary[base:base + 16].split(b"\x00")[0]
                    if section_name == b"__restrict":
                        has_section = True
        offset += size
    return has_segment, has_section


def verify(ipa: Path) -> list[str]:
    failures = []
    with zipfile.ZipFile(ipa) as archive:
        apps = [name for name in archive.namelist() if name.startswith("Payload/") and ".app/" in name]
        if not apps:
            raise SystemExit("no Payload/*.app in IPA")
        app_root = apps[0].split(".app/", 1)[0] + ".app/"
        info = plistlib.loads(archive.read(app_root + "Info.plist"))
        if info.get("UIFileSharingEnabled") is not False:
            failures.append("UIFileSharingEnabled is not false")
        if info.get("LSSupportsOpeningDocumentsInPlace") is not False:
            failures.append("LSSupportsOpeningDocumentsInPlace is not false")
        executable = info.get("CFBundleExecutable") or "SupportPatch"
        binary = archive.read(app_root + executable)
        vault = [name for name in archive.namelist()
                 if name.startswith(app_root + "CharacterVault/") and name.endswith(".tsc")]
        if not vault:
            failures.append("CharacterVault assets are missing")
        for name in vault:
            if not archive.read(name).startswith(b"TSC2"):
                failures.append(f"release vault carries a non-TSC2 blob: {name.split('/')[-1]}")

    has_segment, has_section = inspect(binary)
    if not has_segment:
        failures.append("__RESTRICT segment is missing (OTHER_LDFLAGS not applied)")
    if not has_section:
        failures.append("__restrict section is missing")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()

    failures = verify(args.ipa)
    if failures:
        for failure in failures:
            print(f"FAIL  {failure}")
        return 1
    print(f"ok    {args.ipa}: __RESTRICT present, Documents exposure disabled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
