#!/usr/bin/env python3
"""Reject release IPAs that expose debug artifacts or server-side secrets."""

from __future__ import annotations

import plistlib
import sys
import zipfile
from pathlib import Path

EXPECTED_BUNDLE_ID = "cc.forcequit.worse-query"
FORBIDDEN_MARKERS = (
    b"LICENSE_SIGNING_SECRET",
    b"TELEGRAM_BOT_TOKEN",
    b"LICENSE_ADMIN_TOKEN",
    b"-----BEGIN PRIVATE KEY-----",
    b"-----BEGIN RSA PRIVATE KEY-----",
    b"-----BEGIN EC PRIVATE KEY-----",
)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify_ipa_release.py PATH_TO_IPA")
    ipa = Path(sys.argv[1])
    if not ipa.is_file() or ipa.stat().st_size == 0:
        fail(f"IPA not found or empty: {ipa}")

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        apps = [n for n in names if n.startswith("Payload/") and n.endswith(".app/Info.plist")]
        if len(apps) != 1:
            fail(f"expected one app Info.plist, found {len(apps)}")
        app_root = apps[0][:-len("Info.plist")]
        info = plistlib.loads(archive.read(apps[0]))
        executable_name = info.get("CFBundleExecutable")
        if not isinstance(executable_name, str) or not executable_name:
            fail("CFBundleExecutable is missing")
        executable_path = app_root + executable_name
        if executable_path not in names:
            fail(f"app executable missing: {executable_path}")

        debug_entries = [
            n for n in names
            if n.startswith(app_root + "Contents/Resources/DWARF/")
            or n.endswith(".dSYM/")
            or "/.dSYM/" in n
            or n.endswith(".dwo")
        ]
        if debug_entries:
            fail("debug artifacts embedded in IPA: " + ", ".join(debug_entries[:5]))

        if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
            fail(f"unexpected bundle identifier: {info.get('CFBundleIdentifier')!r}")
        if "TRYSTORE_LICENSE_API_URL" not in info:
            fail("license endpoint is missing from Info.plist")

        executable = archive.read(executable_path)
        for marker in FORBIDDEN_MARKERS:
            if marker in executable:
                fail(f"forbidden server-side secret marker found: {marker.decode(errors='replace')}")

    print(f"PASS: release IPA has no embedded debug artifacts or server-side secret markers ({ipa})")


if __name__ == "__main__":
    main()
