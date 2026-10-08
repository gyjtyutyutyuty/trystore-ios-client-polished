#!/usr/bin/env python3
"""Validate legacy patch catalog, dashboard controls, Xcode resources, and app bundle."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "ThreeOneOSFive/helpers/PatchProjectStore.swift"
UI = ROOT / "ThreeOneOSFive/ContentView.swift"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"
LIBRARY = ROOT / "ThreeOneOSFive/helpers/PatchProjectLibrary.swift"
RESOURCE_BUNDLE = ROOT / "ThreeOneOSFive/helpers/PatchResourceBundle.swift"
GENERATED_BUNDLE = ROOT / "ThreeOneOSFive/helpers/GeneratedPatchBundle.swift"
DEVICE_SERVICE = ROOT / "ThreeOneOSFive/helpers/DevicePatchService.swift"
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"

# resource filename -> project name shown/selected by the dashboard
EXPECTED = {
    "HEAD.3105": "HEAD",
    "NECK.3105": "NECK",
    "HSPESSCOSO.3105": "HS PESSCOSO",
    "HS SLA PECHO.3105": "HS SLA PECHO",
    "SilentAim.3105": "Silent Aim",
    "HOLOGRAMAARMAS.3105": "HOLOGRAMA ARMAS",
    "HOLOGRAMAPERSONAJE.3105": "HOLOGRAMA PERSONAJE",
}
AIM = ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO", "Silent Aim"]
EXCLUSIVE_AIM = ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO"]
VISUALS = ["HOLOGRAMA ARMAS", "HOLOGRAMA PERSONAJE"]
def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def extract_string_array(source: str, property_name: str) -> list[str]:
    match = re.search(rf"var {re.escape(property_name)}: \[String\] \{{\s*\[([^]]*)\]\s*\}}", source, re.S)
    require(match is not None, f"could not locate FreeFireGame.{property_name}")
    return re.findall(r'"([^"]*)"', match.group(1))


def check_source() -> None:
    catalog = CATALOG.read_text()
    ui = UI.read_text()
    pbx = PROJECT.read_text()
    library = LIBRARY.read_text()
    resource_bundle = RESOURCE_BUNDLE.read_text()
    generated_bundle = GENERATED_BUNDLE.read_text()
    device_service = DEVICE_SERVICE.read_text()

    catalog_entries = re.findall(
        r'BundledPatch\(resourceName:\s*"([^"]+)",\s*projectName:\s*"([^"]+)"', catalog
    )
    require(dict(catalog_entries) == EXPECTED,
            f"bundled catalog mismatch; found {catalog_entries!r}")
    require(len(catalog_entries) == len(EXPECTED),
            f"expected exactly {len(EXPECTED)} unique bundled catalog entries")

    aim_names = extract_string_array(ui, "aimProjectNames")
    visual_names = extract_string_array(ui, "locationProjectNames")
    require(aim_names == AIM, f"aim GUI mapping mismatch: {aim_names!r}")
    require(visual_names == VISUALS, f"visual GUI mapping mismatch: {visual_names!r}")

    # Verify the dashboard's actual visible button arrays select exactly the same
    # seven project names and send taps through the direct ON/OFF store action.
    option_rows = re.findall(
        r'DashboardPatchOption\(projectName:\s*"([^"]+)",\s*title:\s*"([^"]+)".*?group:\s*(\.aim|nil)\)',
        ui,
    )
    dashboard_names = [name for name, _title, _group in option_rows]
    require(dashboard_names == AIM + VISUALS,
            f"dashboard ON/OFF button mappings mismatch: {dashboard_names!r}")
    require('ForEach(selectedPatchTab == .loadout ? DashboardPatchOption.loadout : DashboardPatchOption.visuals)' in ui
            and 'legacyPatchButton(option)' in ui,
            "dashboard no longer renders the loadout and visual package options as buttons")
    for name, _title, group in option_rows:
        require((group == ".aim") == (name in EXCLUSIVE_AIM),
                f"dashboard grouping mismatch for {name!r}: {group}")
    require('patchStore.setEnabled(!isActive, for: item, group: option.group' in ui,
            "dashboard button no longer routes its ON/OFF action through PatchProjectStore")
    require('Text(item == nil ? "MISSING" : (isActive ? "ON" : "OFF"))' in ui,
            "dashboard ON/OFF status label is missing or changed")
    require('$0.project?.name == option.projectName' in ui
            and 'caseInsensitiveCompare("\\(option.projectName).3105")' in ui,
            "dashboard no longer resolves buttons to matching decoded projects/package files")
    require('DevicePatchService.latestReceipt(projectID: item.id) != nil' in ui
            and 'patchStore.setEnabled(!isActive, for: item, group: option.group' in ui,
            "button state and tap handler are no longer connected to patch receipt/apply state")
    require('.disabled(patchStore.isBusy || item == nil)' in ui,
            "dashboard button is not guarded by loading/missing-package state")

    initializer = re.search(r'init\(game: FreeFireGame = \.max\) \{(.*?)\n    \}', catalog, re.S)
    require(initializer is not None
            and 'reload()' in initializer.group(1),
            "store startup no longer loads the patch library")
    require('PatchResourceBundle.load(using: bundleKey)' in catalog
            and 'game.bundledPatches.allSatisfy' in catalog
            and 'installBundledPackageDataIfNeeded(' in catalog,
            "store no longer decrypts the source-embedded archive before importing packages")
    require('GeneratedPatchBundle.base64Chunks.joined()' in resource_bundle
            and 'AES.GCM.open' in resource_bundle
            and 'TBP1' in resource_bundle,
            "runtime loader is missing the authenticated encrypted archive parser")
    require(all(filename not in generated_bundle for filename in EXPECTED),
            "generated Swift ciphertext unexpectedly exposes a patch filename")
    require('PatchPackageCodec.decode(data, contentKey: contentKey)' in library
            and 'PatchPackageCodec.decode(data, password: nil)' in library
            and 'project: decoded?.project' in library,
            "library no longer decodes the bundled packages into selectable projects")
    legacy_installer = re.search(
        r"static func installBundledPackageDataIfNeeded\(.*?\n    \}\n\n    static func packageRootURL",
        library,
        re.S,
    )
    require(legacy_installer is not None
            and re.search(r"installImportedPackage\(.*?existingURL:\s*nil", legacy_installer.group(0), re.S),
            "bundle installer must create its first package without reading a nonexistent destination")
    require('try DevicePatchService.apply(project: project)' in catalog
            and 'try DevicePatchService.restore(receipt: receipt)' in catalog,
            "store ON/OFF handler no longer invokes apply and restore")
    require('PatchTransaction.apply(' in device_service
            and 'PatchTransaction.restore(' in device_service,
            "device service apply/restore transaction path is missing")
    require('case "HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO":' in catalog
            and 'return .aim' in catalog,
            "aim group exclusivity mapping is missing")

    # The encrypted archive is compiled into source, not copied as seven IPA resources.
    resource_phase = re.search(r'3105A800 /\* Resources \*/ = \{.*?files = \((.*?)\);', pbx, re.S)
    require(resource_phase is not None, "SupportPatch resources build phase was not found")
    require('.3105' not in resource_phase.group(1) and '.enc' not in resource_phase.group(1),
            "a patch payload is still listed in the IPA Resources phase")
    source_phase = re.search(r'3105A700 /\* Sources \*/ = \{.*?files = \((.*?)\);', pbx, re.S)
    require(source_phase is not None
            and 'B71300000000000000000004' in source_phase.group(1)
            and 'B71300000000000000000006' in source_phase.group(1),
            "runtime loader and generated ciphertext archive are not compiled into the target")
    for filename in EXPECTED:
        source_file = PATCH_DIR / filename
        require(source_file.is_file() and source_file.stat().st_size > 0,
                f"source payload missing or empty: {source_file}")

    all_packages = sorted(p.name for p in PATCH_DIR.glob("*.3105"))
    require(all_packages == sorted(EXPECTED),
            f"unexpected or missing files in Patches/: {all_packages!r}")
    print("PASS: seven bundled entries map to the expected GUI controls and one encrypted Swift source payload.")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle does not exist: {app}")
    leaked = [path for path in app.rglob("*") if path.is_file()
              and (path.name.endswith(".3105") or path.name.endswith(".3105.enc"))]
    require(not leaked, f"standalone patch files are visible in the built app: {leaked!r}")
    print(f"PASS: no standalone .3105 patch files are present in {app}.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="optional built .app bundle to inspect")
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)


if __name__ == "__main__":
    main()
