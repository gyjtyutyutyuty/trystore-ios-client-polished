#!/usr/bin/env python3
"""SHA-256 over the `__TEXT` section bytes of a thin 64-bit Mach-O.

The digest is what `Hardening.codeDigest` recomputes on the device against the
value the archive step stores under `TRYSTORE_CODE_SHA256`.

Why sections and not the whole `__TEXT` segment: ad-hoc signing appends
`__LINKEDIT` and rewrites the Mach header (`ncmds`, `sizeofcmds`,
`LC_CODE_SIGNATURE`), and the header lives at file offset 0 inside `__TEXT`.
The section bytes themselves are never touched by signing, so the digest
survives the maintainer's own re-sign and still changes when a patch rewrites
code or constants.

Usage:
    python3 tools/macho_code_digest.py path/to/SupportPatch
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
ZERO_FILL_TYPES = {1, 12, 18}


def code_digest(binary: bytes) -> str:
    if len(binary) < 32:
        raise ValueError("file is too small to be a Mach-O")
    magic, = struct.unpack_from("<I", binary, 0)
    if magic != MH_MAGIC_64:
        raise ValueError("not a thin 64-bit Mach-O")
    command_count, = struct.unpack_from("<I", binary, 16)
    if not 0 < command_count < 4096:
        raise ValueError("implausible load command count")

    ranges: list[tuple[int, int]] = []
    cursor = 32
    for _ in range(command_count):
        if cursor + 8 > len(binary):
            raise ValueError("load command runs past the file")
        command, size = struct.unpack_from("<II", binary, cursor)
        if size < 8 or cursor + size > len(binary):
            raise ValueError("malformed load command")
        if command == LC_SEGMENT_64:
            if size < 72:
                raise ValueError("segment command is too short")
            segment = binary[cursor + 8:cursor + 24].split(b"\x00", 1)[0]
            if segment == b"__TEXT":
                sections, = struct.unpack_from("<I", binary, cursor + 64)
                if cursor + 72 + sections * 80 > cursor + size:
                    raise ValueError("segment sections run past the load command")
                for index in range(sections):
                    base = cursor + 72 + index * 80
                    flags, = struct.unpack_from("<I", binary, base + 64)
                    if (flags & 0xFF) in ZERO_FILL_TYPES:
                        continue
                    length, = struct.unpack_from("<Q", binary, base + 40)
                    offset, = struct.unpack_from("<I", binary, base + 48)
                    if length == 0 or offset + length > len(binary):
                        continue
                    ranges.append((offset, int(length)))
        cursor += size

    if not ranges:
        raise ValueError("no __TEXT sections found")

    digest = hashlib.sha256()
    for offset, length in sorted(ranges):
        digest.update(binary[offset:offset + length])
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    try:
        print(code_digest(args.binary.read_bytes()))
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
