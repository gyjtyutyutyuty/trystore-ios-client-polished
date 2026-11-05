#!/usr/bin/env python3
"""Validate all statically bundled TryStore patch sources and IPA assets."""
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

ASSET_MAP = {
    "HEAD.TRYSTORE": "HEAD",
    "NECK.TRYSTORE": "NECK",
    "HSPESSCOSO.TRYSTORE": "HS_PESSCOSO",
    "HS SLA PECHO.TRYSTORE": "HS_SLA_PECHO",
    "EXCLUSIVO AZUL.TRYSTORE": "EXCLUSIVO_AZUL",
    "TryStore.TRYSTORE": "TRYSTORE_BALAS_MAGICAS",
    "HOLOGRAMAEXCLUSIVO(4).TRYSTORE": "HOLOGRAMA_EXCLUSIVO_VERDE",
    "HOLOGRAMAEXCLUSIVO(5).TRYSTORE": "HOLOGRAMA_EXCLUSIVO_ROSADO",
    "Cuello y Drag.TRYSTORE": "CUELLO_Y_DRAG",
    "Pecho3105.TRYSTORE": "PECHO3105",
    "CUELLO3105.TRYSTORE": "CUELLO3105",
}
BUNDLED = {
    "HEAD.TRYSTORE": "HEAD",
    "NECK.TRYSTORE": "NECK",
    "HSPESSCOSO.TRYSTORE": "HS PESSCOSO",
    "HS SLA PECHO.TRYSTORE": "HS SLA PECHO",
    "EXCLUSIVO AZUL.TRYSTORE": "EXCLUSIVO AZUL",
    "TryStore.TRYSTORE": "TryStore",
    "HOLOGRAMAEXCLUSIVO(4).TRYSTORE": "HOLOGRAMA EXCLUSIVO VERDE",
    "HOLOGRAMAEXCLUSIVO(5).TRYSTORE": "HOLOGRAMA EXCLUSIVO ROSADO",
    "Cuello y Drag.TRYSTORE": "Drag con Cuello",
    "Pecho3105.TRYSTORE": "Pecho3105",
    "CUELLO3105.TRYSTORE": "CUELLO3105",
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def check_source(require_assets: bool) -> None:
    store = STORE.read_text()
    resource = RESOURCE.read_text()
    pbx = PROJECT.read_text()
    entries = dict(re.findall(
        r'BundledPatch\(resourceName:\s*"([^\"]+)",\s*projectName:\s*"([^\"]+)', store
    ))
    expected_entries = {name: project for name, project in BUNDLED.items()}
    require(entries == expected_entries, f"bundled catalog mismatch: {entries!r}")
    resource_entries = dict(re.findall(r'\("([^\"]+)",\s*"([A-Z0-9_]+)"\)', resource))
    require(resource_entries == ASSET_MAP, f"encrypted asset map mismatch: {resource_entries!r}")
    require("PatchFeedService" not in pbx and "PatchFeedService" not in store,
            "remote patch feed service remains in the app project")
    require("installBundledPackageDataIfNeeded" in store,
            "encrypted package installer is not wired")
    require("installBundledRawPackageDataIfNeeded" not in store,
            "raw patch package fallback remains enabled")
    require("3105A211" in pbx and ".TRYSTORE" not in pbx,
            "raw patch file is incorrectly listed as an Xcode resource")
    files = {p.name for p in PATCH_DIR.glob("*.TRYSTORE")}
    require(files == set(ASSET_MAP), f"patch source file set mismatch: {sorted(files)!r}")
    for filename in ASSET_MAP:
        require((PATCH_DIR / filename).is_file() and (PATCH_DIR / filename).stat().st_size > 0,
                f"missing source patch: {filename}")
    if require_assets:
        for asset in ASSET_MAP.values():
            dataset = ASSETS / f"{asset}.dataset"
            binary = dataset / f"{asset}.bin"
            require(binary.is_file() and binary.stat().st_size > 0,
                    f"missing generated encrypted asset: {asset}")
            contents = json.loads((dataset / "Contents.json").read_text())
            require(contents.get("data", [{}])[0].get("filename") == f"{asset}.bin",
                    f"wrong encrypted asset metadata: {asset}")
    print(f"PASS: {len(ASSET_MAP)} patch sources are mapped to encrypted IPA assets")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle missing: {app}")
    require((app / "Info.plist").is_file(), "Info.plist missing from app")
    require(any(app.rglob("Assets.car")), "compiled asset catalog missing from app")
    print("PASS: IPA app bundle contains Info.plist and compiled Assets.car")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets-generated", action="store_true")
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    check_source(require_assets=args.assets_generated or args.app is not None)
    if args.app:
        check_app(args.app)
