#!/usr/bin/env python3
"""Validate that patch payloads are remote-only and optionally inspect an IPA app."""
from __future__ import annotations
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "ThreeOneOSFive"
PATCH_DIR = APP_ROOT / "Patches"
ASSETS = APP_ROOT / "Assets.xcassets"
STORE = APP_ROOT / "helpers/PatchProjectStore.swift"
FEED = APP_ROOT / "helpers/PatchFeedService.swift"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"
PATCH_ASSET_STEMS = {
    "HEAD", "NECK", "HSPESSCOSO", "HS_SLA_PECHO", "EXCLUSIVO_AZUL_TRYSTORE",
    "TryStore_TRYSTORE", "HOLOGRAMA_EXCLUSIVO_VERDE", "HOLOGRAMA_EXCLUSIVO_ROSADO",
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(ok: bool, message: str) -> None:
    if not ok:
        fail(message)


def check_source() -> None:
    store = STORE.read_text()
    feed = FEED.read_text()
    project = PROJECT.read_text()

    package_files = list(APP_ROOT.rglob("*.TRYSTORE"))
    require(not package_files, f"patch package payloads must not be in the app source tree: {package_files}")
    if PATCH_DIR.exists():
        require(not any(PATCH_DIR.iterdir()), f"patch source folder is not empty: {PATCH_DIR}")

    asset_payloads = []
    if ASSETS.exists():
        for path in ASSETS.rglob("*"):
            if path.is_file() and any(stem.lower() in path.name.lower() for stem in PATCH_ASSET_STEMS):
                asset_payloads.append(path)
    require(not asset_payloads, f"patch payload asset files remain in the asset catalog: {asset_payloads}")
    require(".TRYSTORE" not in project, "patch package file references remain in the Xcode project")
    require("patch: bundled patch payloads disabled" in store,
            "bundled patch installation is not explicitly disabled")
    require("https://trystore-patch-feed.burgoajustin.workers.dev" in feed,
            "Cloudflare remote patch feed is not configured")
    require('appendingPathComponent("api/patches/\\(project)/manifest.json")' in feed,
            "remote patch manifest endpoint is not configured")
    print("PASS: no patch payloads are bundled; the Cloudflare remote feed is configured")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle missing: {app}")
    require((app / "Info.plist").is_file(), "Info.plist missing from app")
    require(any(app.rglob("Assets.car")), "compiled asset catalog missing from app")
    package_files = list(app.rglob("*.TRYSTORE"))
    require(not package_files, f"patch package files were copied into the app bundle: {package_files}")
    print("PASS: app bundle is valid and contains no standalone patch package files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)
