#!/usr/bin/env python3
"""Validate legacy patch catalog, dashboard controls, Xcode resources, and app bundle."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "ThreeOneOSFive/helpers/PatchProjectStore.swift"
UI = ROOT / "ThreeOneOSFive/ContentView.swift"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"
LIBRARY = ROOT / "ThreeOneOSFive/helpers/PatchProjectLibrary.swift"
RESOURCE_BUNDLE = ROOT / "ThreeOneOSFive/helpers/PatchResourceBundle.swift"
PACKAGE_CODEC = ROOT / "ThreeOneOSFive/helpers/PatchPackageCodec.swift"
LICENSE_MANAGER = ROOT / "ThreeOneOSFive/helpers/LicenseManager.swift"
DEVICE_SERVICE = ROOT / "ThreeOneOSFive/helpers/DevicePatchService.swift"
WORKER = ROOT / "cloudflare/license-worker.js"
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"
ASSET_CATALOG = ROOT / "ThreeOneOSFive/Assets.xcassets"

# resource filename -> project name shown/selected by the dashboard
EXPECTED = {
    "HEAD.3105": "HEAD",
    "NECK.3105": "NECK",
    "HSPESSCOSO.3105": "HS PESSCOSO",
    "HS SLA PECHO.3105": "HS SLA PECHO",
    "HOLOGRAMAARMAS.3105": "HOLOGRAMA ARMAS",
    "HOLOGRAMAPERSONAJE.3105": "HOLOGRAMA PERSONAJE",
    "HOLOGRAMAEXCLUSIVO(2).3105": "HOLOGRAMA EXCLUSIVO VERDE",
    "HOLOGRAMAEXCLUSIVO(3).3105": "HOLOGRAMA EXCUSIVO ROSADO",
}
EXPECTED_ASSETS = {
    "HEAD.3105": "HEAD",
    "NECK.3105": "NECK",
    "HSPESSCOSO.3105": "HS_PESSCOSO",
    "HS SLA PECHO.3105": "HS_SLA_PECHO",
    "HOLOGRAMAARMAS.3105": "HOLOGRAMA_ARMAS",
    "HOLOGRAMAPERSONAJE.3105": "HOLOGRAMA_PERSONAJE",
    "HOLOGRAMAEXCLUSIVO(2).3105": "HOLOGRAMA_EXCLUSIVO_VERDE",
    "HOLOGRAMAEXCLUSIVO(3).3105": "HOLOGRAMA_EXCUSIVO_ROSADO",
}
AIM = ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO"]
EXCLUSIVE_AIM = ["HEAD", "NECK", "HS PESSCOSO", "HS SLA PECHO"]
VISUALS = [
    "HOLOGRAMA ARMAS",
    "HOLOGRAMA PERSONAJE",
    "HOLOGRAMA EXCLUSIVO VERDE",
    "HOLOGRAMA EXCUSIVO ROSADO",
]
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
    pbx_object_ids = re.findall(r"^\s*([A-Z0-9]{8,24})\s*(?:/\*.*?\*/\s*)?=\s*\{", pbx, re.M)
    require(len(pbx_object_ids) == len(set(pbx_object_ids)),
            "Xcode project contains duplicate object identifiers")
    library = LIBRARY.read_text()
    resource_bundle = RESOURCE_BUNDLE.read_text()
    package_codec = PACKAGE_CODEC.read_text()
    license_manager = LICENSE_MANAGER.read_text()
    worker = WORKER.read_text()
    device_service = DEVICE_SERVICE.read_text()

    catalog_entries = re.findall(
        r'BundledPatch\(resourceName:\s*"([^"]+)",\s*projectName:\s*"([^"]+)"', catalog
    )
    require(dict(catalog_entries) == EXPECTED,
            f"bundled catalog mismatch; found {catalog_entries!r}")
    require(len(catalog_entries) == len(EXPECTED),
            f"expected exactly {len(EXPECTED)} unique bundled catalog entries")
    require("SilentAim.3105" not in catalog and "Silent Aim" not in ui
            and "SilentAim.3105" not in resource_bundle,
            "removed Silent Aim patch is still present in the app catalog, loader, or dashboard")

    aim_names = extract_string_array(ui, "aimProjectNames")
    visual_names = extract_string_array(ui, "locationProjectNames")
    require(aim_names == AIM, f"aim GUI mapping mismatch: {aim_names!r}")
    require(visual_names == VISUALS, f"visual GUI mapping mismatch: {visual_names!r}")

    # Verify the dashboard's actual visible button arrays select exactly the same
    # eight project names and send taps through the direct ON/OFF store action.
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
    require(re.search(r"PatchResourceBundle\.load\(using:\s*bundleKey", catalog) is not None
            and 'game.bundledPatches.allSatisfy' in catalog
            and 'installBundledPackageDataIfNeeded(' in catalog,
            "store no longer decrypts local asset-catalog resources before importing packages")
    require('NSDataAsset(name: entry.assetName)?.data' in resource_bundle
            and 'AES.GCM.SealedBox' in resource_bundle
            and 'AES.GCM.open' in resource_bundle
            and 'SymmetricKey(data: keyData)' in resource_bundle,
            "runtime loader is missing local authenticated asset decryption")
    require('sendPatchBundleKey(key: key, endpoint: endpoint)' in license_manager
            and 'patchBundleKey = bundleKey' in license_manager
            and 'patchBundleCiphertext' not in license_manager
            and 'sendPatchBundleCiphertext' not in license_manager,
            "license manager should retrieve only the authorization-gated decryption key")
    require("'/api/v1/keys/patch-bundle-key'" in worker
            and 'PATCH_BUNDLE_CIPHERTEXT_B64' not in worker
            and "'/api/v1/keys/patch-bundle'" not in worker,
            "Worker must retain key delivery but not the no-longer-used archive endpoint")
    require('PatchPackageCodec.decode(data, contentKey: contentKey)' in library
            and 'PatchPackageCodec.decode(data, password: nil)' in library
            and 'project: decoded?.project' in library,
            "library no longer decodes the bundled packages into selectable projects")
    stable_bundled_ids = dict(re.findall(
        r'"([^"]+)":\s*UUID\(uuidString:\s*"([A-Fa-f0-9-]+)"\)!', library
    ))
    required_id_names = {
        "HOLOGRAMA EXCLUSIVO VERDE",
        "HOLOGRAMA EXCUSIVO ROSADO",
    }
    require(required_id_names <= stable_bundled_ids.keys()
            and len({stable_bundled_ids[name] for name in required_id_names}) == 2,
            "the two new bundled patches must have distinct stable project IDs")
    bundled_installer = re.search(
        r"static func installBundledPackageDataIfNeeded\(.*?\n    \}\n\n    static func packageRootURL",
        library,
        re.S,
    )
    require(bundled_installer is not None
            and "existingDecoded.project.id != expectedID" in bundled_installer.group(0)
            and "normalizedProject.id = bundledProjectID" in bundled_installer.group(0),
            "bundled installer must migrate prior duplicate IDs and assign unique stable IDs")
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

    # Xcode compiles encrypted Data Sets inside Assets.car; no raw package file is copied.
    resource_phase = re.search(r'3105A800 /\* Resources \*/ = \{.*?files = \((.*?)\);', pbx, re.S)
    require(resource_phase is not None, "SupportPatch resources build phase was not found")
    require('3105A211' in resource_phase.group(1)
            and '.3105' not in resource_phase.group(1)
            and '.enc' not in resource_phase.group(1),
            "the asset catalog is not in the IPA Resources phase or a raw patch file is listed")
    source_phase = re.search(r'3105A700 /\* Sources \*/ = \{.*?files = \((.*?)\);', pbx, re.S)
    require(source_phase is not None
            and 'B71300000000000000000006' in source_phase.group(1)
            and 'B71300000000000000000004' not in source_phase.group(1)
            and re.search(
                r'B71300000000000000000006 /\* PatchResourceBundle\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = B71300000000000000000005;',
                pbx,
            ) is not None
            and 'GeneratedPatchBundle' not in pbx
            and not (ROOT / "ThreeOneOSFive/helpers/GeneratedPatchBundle.swift").exists(),
            "the app target still compiles a patch archive instead of loading asset-catalog Data Sets")
    asset_map = dict(re.findall(r'\("([^\"]+)",\s*"([A-Z_]+)"\)', resource_bundle))
    require(asset_map == EXPECTED_ASSETS, f"asset Data Set mapping mismatch: {asset_map!r}")
    for resource_name, asset_name in asset_map.items():
        dataset = ASSET_CATALOG / f"{asset_name}.dataset"
        contents_path = dataset / "Contents.json"
        require(contents_path.is_file(), f"missing asset Data Set metadata: {contents_path}")
        contents = json.loads(contents_path.read_text())
        files = contents.get('data', [])
        require(len(files) == 1 and files[0].get('filename') == f"{asset_name}.bin",
                f"asset Data Set does not reference its named .bin file: {asset_name}")
        payload = dataset / f"{asset_name}.bin"
        require(payload.is_file() and payload.stat().st_size > 28,
                f"encrypted asset is missing or too small: {payload}")
        require(not (dataset / resource_name).exists(),
                f"plaintext source package is present in the asset Data Set: {resource_name}")
    source_package_ids: dict[str, list[str]] = {}
    for filename in EXPECTED:
        source_file = PATCH_DIR / filename
        require(source_file.is_file() and source_file.stat().st_size > 0,
                f"source payload missing or empty: {source_file}")
        package_data = source_file.read_bytes()
        magic = b"3105PATCH\0"
        require(package_data.startswith(magic),
                f"source payload has an unsupported package header: {filename}")
        try:
            envelope = plistlib.loads(package_data[len(magic):])
        except Exception as error:
            fail(f"source payload has an invalid package envelope: {filename}: {error}")
        schema_version = envelope.get("schemaVersion")
        package_id = str(envelope.get("packageID", ""))
        require(bool(package_id), f"source payload has no package UUID: {filename}")
        source_package_ids.setdefault(package_id, []).append(filename)
        require(schema_version in {1, 2, 9},
                f"unsupported bundled package schema {schema_version!r}: {filename}")
        if schema_version == 9:
            require(filename in {"HOLOGRAMAEXCLUSIVO(2).3105", "HOLOGRAMAEXCLUSIVO(3).3105"}
                    and envelope.get("isPasswordProtected") is False
                    and len(envelope.get("publicContentKey", b"")) == 32
                    and len(envelope.get("encryptedPayload", b"")) >= 28,
                    f"schema-9 migration source is not a valid unprotected package: {filename}")
            require("migrationCompatibleSchemaVersion = 9" in package_codec,
                    "schema-9 package exists but the app has no compatibility migration path")

    duplicate_source_ids = [set(filenames) for filenames in source_package_ids.values() if len(filenames) > 1]
    require(duplicate_source_ids == [{
        "HOLOGRAMAEXCLUSIVO(2).3105",
        "HOLOGRAMAEXCLUSIVO(3).3105",
    }],
            f"unexpected duplicate source package UUIDs: {duplicate_source_ids!r}")

    all_packages = sorted(p.name for p in PATCH_DIR.glob("*.3105"))
    require(all_packages == sorted(EXPECTED),
            f"unexpected or missing files in Patches/: {all_packages!r}")
    print("PASS: eight patch entries map to encrypted .bin Data Sets in Assets.xcassets; Silent Aim is absent and no raw .3105 files are Xcode resources.")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle does not exist: {app}")
    files = [path for path in app.rglob("*") if path.is_file()]
    leaked = [path for path in files if path.name.endswith((".3105", ".3105.enc"))]
    require(not leaked, f"standalone plaintext patch files are visible in the built app: {leaked!r}")
    asset_bin_names = {f"{asset_name}.bin" for asset_name in EXPECTED_ASSETS.values()}
    asset_bins = [path for path in files if path.name in asset_bin_names]
    require(not asset_bins, f"asset-catalog .bin files escaped into the app as loose files: {asset_bins!r}")
    require(any(path.name == "Assets.car" for path in files),
            "built app is missing the compiled asset catalog containing encrypted .bin Data Sets")
    print(f"PASS: no loose patch files are present; encrypted .bin Data Sets are compiled inside Assets.car in {app}.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="optional built .app bundle to inspect")
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)


if __name__ == "__main__":
    main()
