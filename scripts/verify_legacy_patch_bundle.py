#!/usr/bin/env python3
"""Validate local TryStore packages, their UI buttons, and IPA resources."""
from __future__ import annotations
import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "ThreeOneOSFive/ContentView.swift"
PATCH_DIR = ROOT / "ThreeOneOSFive/Patches"
STORE = ROOT / "ThreeOneOSFive/helpers/PatchProjectStore.swift"
LIBRARY = ROOT / "ThreeOneOSFive/helpers/PatchProjectLibrary.swift"
RESOURCE = ROOT / "ThreeOneOSFive/helpers/PatchResourceBundle.swift"
DEVICE_SERVICE = ROOT / "ThreeOneOSFive/helpers/DevicePatchService.swift"
TRANSACTION = ROOT / "ThreeOneOSFive/helpers/PatchTransaction.swift"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"

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


def package_metadata(filename: str) -> dict:
    data = (PATCH_DIR / filename).read_bytes()
    magic = b"3105PATCH\0"
    require(data.startswith(magic), f"invalid package header: {filename}")
    try:
        return plistlib.loads(data[len(magic):])
    except Exception as error:
        fail(f"invalid package envelope {filename}: {error}")


def check_source() -> None:
    app = APP_SOURCE.read_text()
    store = STORE.read_text()
    library = LIBRARY.read_text()
    resource = RESOURCE.read_text()
    device_service = DEVICE_SERVICE.read_text()
    transaction = TRANSACTION.read_text()
    pbx = PROJECT.read_text()

    canonical_ids: dict[str, str] = {}
    for filename, project_name in BUNDLED.items():
        require(
            f'BundledPatch(resourceName: "{filename}", projectName: "{project_name}"' in store,
            f"bundled catalog is missing {filename}",
        )
        require(f'"{filename}"' in resource, f"local resource list is missing {filename}")
        source = PATCH_DIR / filename
        require(source.is_file() and source.stat().st_size > 0, f"missing source patch: {filename}")
        metadata = package_metadata(filename)
        require(metadata.get("isPasswordProtected") is False,
                f"bundled package requires a password: {filename}")
        require(isinstance(metadata.get("packageID"), str),
                f"package ID missing from envelope: {filename}")
        canonical_ids[project_name] = metadata["packageID"].upper()

    # The two historical schema-9 visual packages are normalized to fresh,
    # distinct IDs during local installation; read those IDs from the app's map.
    special_ids = dict(re.findall(
        r'"(HOLOGRAMA EXCLUSIVO (?:VERDE|ROSADO))": UUID\(uuidString: "([^"]+)"\)!',
        library,
    ))
    for name in ("HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO"):
        require(name in special_ids, f"stable migrated package ID missing: {name}")
        canonical_ids[name] = special_ids[name].upper()
    require(len(set(canonical_ids.values())) == len(BUNDLED),
            "bundled packages do not have unique installed package IDs")

    # Every button is an actual DashboardPatchOption. Explicit package IDs must
    # refer to one of the shipped canonical packages; name-based options must
    # have one unique package-name target.
    options: list[tuple[str, str | None]] = []
    for line in app.splitlines():
        if "DashboardPatchOption(projectName:" not in line:
            continue
        name_match = re.search(r'DashboardPatchOption\(projectName: "([^"]+)"', line)
        if not name_match:
            continue
        id_match = re.search(r'packageID: UUID\(uuidString: "([^"]+)"\)', line)
        options.append((name_match.group(1), id_match.group(1).upper() if id_match else None))

    require(options, "no patch buttons were found")
    all_expected_ids = set(canonical_ids.values())
    for option_name, package_id in options:
        if package_id:
            require(package_id in all_expected_ids,
                    f"button {option_name} points to an unknown package ID {package_id}")

    for filename, canonical_name in BUNDLED.items():
        expected_id = canonical_ids[canonical_name]
        name_targets = [name for name, package_id in options
                        if package_id is None and name == canonical_name]
        id_targets = [(name, package_id) for name, package_id in options
                      if package_id == expected_id]
        require(not name_targets,
                f"package {canonical_name} has a name-only button instead of an exact UUID")
        require(bool(id_targets),
                f"no activation/restore button is linked to {filename} ({canonical_name})")
        require(len(id_targets) == 1,
                f"package {canonical_name} is linked to more than one visible button")

    require("Button(action: activateSelectedPatch)" in app,
            "selected patch action button is not connected to activation/restore")
    require('selectedPatchIsActive ? language.text("patch.action.restore") : language.text("patch.action.activate")' in app,
            "action button does not switch between Activate and Restore")
    require("patchStore.setEnabled(" in app and "DevicePatchService.apply(project:" in store,
            "patch action does not reach the apply transaction")
    require("DevicePatchService.restore(receipt: receipt" in store,
            "patch action does not reach the restore transaction")
    require("static func apply(" in device_service and "static func restore(" in device_service,
            "device patch service is missing apply or restore routes")
    require("Patches in Resources" in pbx and "D71300000000000000000001" in pbx,
            "Patches folder is not registered as an Xcode resource")
    require("func installBundledResources()" in store,
            "local patch installer is not wired")
    require("didInstallBundledResources = allInstalled" in store,
            "failed package installations cannot be retried")
    require("canonicalBundledPackageFilenames" in library
            and "canonicalSelectedIDs.insert(summary.packageID)" in library,
            "legacy duplicate IDs can still disable the canonical bundled patch")
    require("groupsConflict(Self.group(for: candidate), with: resolvedGroup)" in store
            and "(.aim, .antena), (.antena, .aim)" in store,
            "Aim and Antena patches are not restored across their shared assetindexer target")
    require("PatchTransaction.activationDate(for: receipt)" in store
            and ".sorted { $0.2 > $1.2 }" in store
            and "static func activationDate(for receipt:" in transaction,
            "stacked conflicting patch receipts are not restored newest-first")
    print(f"PASS: all {len(BUNDLED)} local packages have unique button mappings and Activate/Restore routes")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle missing: {app}")
    require((app / "Info.plist").is_file(), "Info.plist missing from app")
    bundled = app / "Patches"
    require(bundled.is_dir(), "local Patches folder missing from app bundle")
    for filename in BUNDLED:
        source = PATCH_DIR / filename
        packaged = bundled / filename
        require(packaged.is_file(), f"patch missing from IPA: {filename}")
        require(packaged.stat().st_size == source.stat().st_size,
                f"patch size mismatch in IPA: {filename}")
    print(f"PASS: app bundle contains all {len(BUNDLED)} local patch packages")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)
