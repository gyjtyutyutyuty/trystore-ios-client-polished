#!/usr/bin/env python3
"""Validate the current TryStore bundled patch layout and optional IPA output."""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"
ASSETS = ROOT / "ThreeOneOSFive/Assets.xcassets"
STORE = ROOT / "ThreeOneOSFive/helpers/PatchProjectStore.swift"
RESOURCE = ROOT / "ThreeOneOSFive/helpers/PatchResourceBundle.swift"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"
ENCRYPTED = {
    "HEAD.TRYSTORE": "HEAD",
    "NECK.TRYSTORE": "NECK",
    "HSPESSCOSO.TRYSTORE": "HS_PESSCOSO",
    "HS SLA PECHO.TRYSTORE": "HS_SLA_PECHO",
    "HOLOGRAMAEXCLUSIVO(4).TRYSTORE": "HOLOGRAMA_EXCLUSIVO_VERDE",
    "HOLOGRAMAEXCLUSIVO(5).TRYSTORE": "HOLOGRAMA_EXCLUSIVO_ROSADO",
}
RAW = {
    "EXCLUSIVO AZUL.TRYSTORE": "EXCLUSIVO_AZUL_TRYSTORE",
    "TryStore.TRYSTORE": "TryStore_TRYSTORE",
}
EXPECTED = {**ENCRYPTED, **RAW}
def fail(msg: str) -> None:
    raise SystemExit(f"FAIL: {msg}")
def require(ok: bool, msg: str) -> None:
    if not ok: fail(msg)
def check_source() -> None:
    store = STORE.read_text(); resource = RESOURCE.read_text(); pbx = PROJECT.read_text()
    entries = dict(re.findall(r'BundledPatch\(resourceName:\s*"([^"]+)",\s*projectName:\s*"([^"]+)"', store))
    expected_entries = {
        "HEAD.TRYSTORE":"HEAD", "NECK.TRYSTORE":"NECK", "HSPESSCOSO.TRYSTORE":"HS PESSCOSO",
        "HS SLA PECHO.TRYSTORE":"HS SLA PECHO", "EXCLUSIVO_AZUL_TRYSTORE":"EXCLUSIVO AZUL",
        "TryStore_TRYSTORE":"TryStore", "HOLOGRAMAEXCLUSIVO(4).TRYSTORE":"HOLOGRAMA EXCLUSIVO VERDE",
        "HOLOGRAMAEXCLUSIVO(5).TRYSTORE":"HOLOGRAMA EXCLUSIVO ROSADO",
    }
    require(entries == expected_entries, f"bundled catalog mismatch: {entries!r}")
    require('NSDataAsset(name: patch.resourceName, bundle: .main)?.data' in store, "raw hidden dataset loader missing")
    require('installBundledRawPackageDataIfNeeded' in store, "raw package installer missing")
    resource_entries = dict(re.findall(r'\("([^\"]+)",\s*"([A-Z_]+)"\)', resource))
    require(resource_entries == ENCRYPTED, f"encrypted asset map mismatch: {resource_entries!r}")
    require('3105A211' in pbx and '.TRYSTORE' not in pbx, "raw patch file is incorrectly listed as an Xcode resource")
    for filename in ENCRYPTED:
        p=PATCH_DIR/filename; require(p.is_file() and p.stat().st_size > 0, f"missing source patch: {filename}")
    for filename, asset in ENCRYPTED.items():
        ds=ASSETS/f"{asset}.dataset"; require((ds/f"{asset}.bin").is_file(), f"missing encrypted asset: {asset}")
        json.load(open(ds/'Contents.json'))
    for filename, asset in RAW.items():
        ds=ASSETS/f"{asset}.dataset"; require((ds/filename).is_file() and (ds/filename).stat().st_size > 0, f"missing hidden raw asset: {filename}")
        c=json.load(open(ds/'Contents.json')); require(c.get('data',[{}])[0].get('filename') == filename, f"wrong raw asset metadata: {asset}")
    print("PASS: six encrypted and two hidden raw .TRYSTORE bundles are configured for IPA loading")
def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle missing: {app}")
    require((app/'Info.plist').is_file(), "Info.plist missing from app")
    require(any(app.rglob('Assets.car')), "compiled asset catalog missing from app")
    print("PASS: IPA app bundle contains Info.plist and compiled Assets.car")
if __name__ == '__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--app', type=Path); args=ap.parse_args()
    check_source()
    if args.app: check_app(args.app)
