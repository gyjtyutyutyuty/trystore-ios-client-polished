#!/usr/bin/env python3
"""Apply the documented SupportPatch crack set to an unsigned IPA.

The patch set targets SupportPatch 1.1.1 build 16 (arm64, unsigned) and is
byte-verified before anything is written. It changes two instructions:

  0x1000118AC  root view, `b.ne` after `licenseManager.isActive`
               -> NOP, so the active branch (ContentView) always runs
  0x10007A67C  RuntimeProbe.currentState
               -> `mov w0, #4; ret` (.ok), skipping the in-process
                  anti-debug / jailbreak / injection probe

What it does not do: the feed still refuses to release the patch bundle key
without a real, server-signed session. Content keys are not in the binary, so
no client-side patch can decrypt feed packages without a licensed activation.

Usage:
    python tools/crack_ipa.py in.ipa out.ipa
    python tools/crack_ipa.py in.ipa out.ipa --manifest artifacts/crack-patches.json

The produced IPA is unsigned; the sideloader signs it on install.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import struct
import tempfile
import zipfile
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19

# (virtual address, expected bytes, replacement bytes, description)
PATCHES: list[tuple[int, bytes, bytes, str]] = [
    (
        0x1000118AC,
        bytes.fromhex("410d0054"),
        bytes.fromhex("1f2003d5"),
        "ContentView gate: `b.ne` after licenseManager.isActive -> NOP; "
        "the active branch always runs",
    ),
    (
        0x10007A67C,
        bytes.fromhex("ff4301d1f85f01a9"),
        bytes.fromhex("80008052c0035fd6"),
        "RuntimeProbe.currentState -> `mov w0, #4; ret` (.ok); debugger, "
        "simulator, jailbreak, injection and Frida-port probes are skipped",
    ),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_segment_slack(data: bytes) -> None:
    """Reject anything that is not the expected thin 64-bit Mach-O."""
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit("binary is not a thin 64-bit Mach-O")


def vm_to_file(data: bytes, address: int) -> int:
    """Map a virtual address to its file offset through the segment table."""
    ncmds = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8:
            raise SystemExit("malformed load command")
        if cmd == LC_SEGMENT_64:
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, offset + 24)
            if vmaddr <= address < vmaddr + vmsize:
                delta = address - vmaddr
                if delta >= filesize:
                    raise SystemExit(f"address {address:#x} has no file bytes")
                return fileoff + delta
        offset += cmdsize
    raise SystemExit(f"address {address:#x} is outside every segment")


def apply_patches(binary: bytearray, patch_set: list[tuple[int, bytes, bytes, str]]) -> list[dict]:
    text_segment_slack(binary)
    applied = []
    for address, expected, replacement, description in patch_set:
        offset = vm_to_file(binary, address)
        current = bytes(binary[offset:offset + len(expected)])
        if current != expected:
            raise SystemExit(
                f"patch mismatch at {address:#x}: expected {expected.hex()}, found {current.hex()}"
            )
        binary[offset:offset + len(replacement)] = replacement
        applied.append(
            {
                "address": f"0x{address:x}",
                "file_offset": f"0x{offset:x}",
                "before": expected.hex(),
                "after": replacement.hex(),
                "description": description,
            }
        )
    return applied


def crack(source: Path, output: Path, manifest: Path | None) -> dict:
    if source.resolve() == output.resolve():
        raise SystemExit("input and output must differ")

    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        with zipfile.ZipFile(source) as archive:
            archive.extractall(root)

        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise SystemExit(f"expected one .app in Payload, found {len(apps)}")
        app = apps[0]
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        executable = info.get("CFBundleExecutable") or app.stem
        binary_path = app / executable
        if not binary_path.exists():
            raise SystemExit(f"executable not found: {binary_path}")

        binary = bytearray(binary_path.read_bytes())
        applied = apply_patches(binary, PATCHES)
        binary_path.write_bytes(binary)

        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(root).as_posix())

    result = {
        "input": str(source),
        "input_sha256": sha256(source),
        "output": str(output),
        "output_sha256": sha256(output),
        "output_bytes": output.stat().st_size,
        "bundle": info.get("CFBundleIdentifier"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "patches": applied,
        "limits": "Feed bundle keys stay server-side; this set unlocks the client gate only.",
    }
    if manifest is not None:
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--manifest", type=Path, default=None)
    args = parser.parse_args()

    result = crack(args.ipa, args.out, args.manifest)
    print(f"wrote      {result['output']}  ({result['output_bytes']} bytes)")
    print(f"sha256     {result['output_sha256']}")
    for patch in result["patches"]:
        print(f"patch      {patch['address']}  {patch['before']} -> {patch['after']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
