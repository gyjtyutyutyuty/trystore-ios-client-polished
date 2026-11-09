#!/usr/bin/env python3
"""Validate TryStore package sources, remote delivery wiring, UI mappings, and IPA exclusions."""
from __future__ import annotations
import argparse
import plistlib
import re
import subprocess
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
WORKER = ROOT / "cloudflare/patch-feed-worker.js"

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


def package_project(filename: str) -> dict:
    envelope = package_metadata(filename)
    key = envelope.get("publicContentKey")
    require(isinstance(key, bytes) and len(key) == 32,
            f"public content key missing or invalid: {filename}")
    aad = f"3105PATCH/v{envelope['schemaVersion']}/payload/{envelope['packageID']}"
    decrypt = (
        "const c=require('crypto'),k=Buffer.from(process.argv[1],'hex'),"
        "a=Buffer.from(process.argv[2]);let x=[];"
        "process.stdin.on('data',v=>x.push(v));process.stdin.on('end',()=>{"
        "const p=Buffer.concat(x),n=p.subarray(0,12),t=p.subarray(p.length-16),"
        "d=c.createDecipheriv('aes-256-gcm',k,n);d.setAAD(a);d.setAuthTag(t);"
        "process.stdout.write(Buffer.concat([d.update(p.subarray(12,p.length-16)),d.final()]));});"
    )
    try:
        decoded = subprocess.run(
            ["node", "-e", decrypt, key.hex(), aad],
            input=envelope["encryptedPayload"],
            check=True,
            capture_output=True,
            timeout=20,
        )
        payload = plistlib.loads(decoded.stdout)
        project = payload["project"]
        require(project.get("id", "").upper() == envelope["packageID"].upper(),
                f"payload/envelope UUID mismatch: {filename}")
        return project
    except Exception as error:
        fail(f"cannot authenticate/decode bundled package {filename}: {error}")


def check_source() -> None:
    app = APP_SOURCE.read_text()
    store = STORE.read_text()
    library = LIBRARY.read_text()
    resource = RESOURCE.read_text()
    device_service = DEVICE_SERVICE.read_text()
    transaction = TRANSACTION.read_text()
    pbx = PROJECT.read_text()
    worker = WORKER.read_text()

    canonical_ids: dict[str, str] = {}
    for filename, project_name in BUNDLED.items():
        require(
            f'BundledPatch(resourceName: "{filename}", projectName: "{project_name}"' in store,
            f"bundled catalog is missing {filename}",
        )
        require("URLSessionConfiguration.ephemeral" in resource, "remote patch client is missing")
        source = PATCH_DIR / filename
        require(source.is_file() and source.stat().st_size > 0, f"missing source patch: {filename}")
        metadata = package_metadata(filename)
        require(metadata.get("isPasswordProtected") is False,
                f"bundled package requires a password: {filename}")
        require(isinstance(metadata.get("packageID"), str),
                f"package ID missing from envelope: {filename}")
        canonical_ids[project_name] = metadata["packageID"].upper()

    # The two historical schema-9 visual packages are normalized to fresh,
    # distinct IDs during remote installation; read those IDs from the app's map.
    special_ids = dict(re.findall(
        r'"(HOLOGRAMA EXCLUSIVO (?:VERDE|ROSADO))": UUID\(uuidString: "([^"]+)"\)!',
        library,
    ))
    for name in ("HOLOGRAMA EXCLUSIVO VERDE", "HOLOGRAMA EXCLUSIVO ROSADO"):
        require(name in special_ids, f"stable migrated package ID missing: {name}")
        canonical_ids[name] = special_ids[name].upper()
    require(len(set(canonical_ids.values())) == len(BUNDLED),
            "bundled packages do not have unique installed package IDs")

    normal_path = (
        "Documents/contentcache/Compulsory/ios/gameassetbundles/avatar/"
        "assetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D"
    )
    normal_packages = (
        "HEAD.TRYSTORE", "NECK.TRYSTORE", "HSPESSCOSO.TRYSTORE", "HS SLA PECHO.TRYSTORE"
    )
    antena_packages = (
        "TryStore.TRYSTORE", "Cuello y Drag.TRYSTORE", "Pecho3105.TRYSTORE", "CUELLO3105.TRYSTORE"
    )
    decoded_projects = {}
    for filename in normal_packages + antena_packages:
        project = package_project(filename)
        decoded_projects[filename] = project
        rules = project.get("rules", [])
        require(bool(rules), f"patch has no file rules: {filename}")
        require(all(rule.get("relativePath") == normal_path for rule in rules),
                f"normal/Antena package target differs from expected avatar path: {filename}")
    for normal_file, antena_file in (
        ("NECK.TRYSTORE", "CUELLO3105.TRYSTORE"),
        ("HSPESSCOSO.TRYSTORE", "Cuello y Drag.TRYSTORE"),
        ("HS SLA PECHO.TRYSTORE", "Pecho3105.TRYSTORE"),
    ):
        normal_rules = decoded_projects[normal_file]["rules"]
        antena_rules = decoded_projects[antena_file]["rules"]
        require(len(normal_rules) == 1 and len(antena_rules) == 1
                and normal_rules[0].get("replacementData") != antena_rules[0].get("replacementData"),
                f"normal patch {normal_file} reuses Antena replacement data from {antena_file}")

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
    require("Patches in Resources" not in pbx and "D71300000000000000000001" not in pbx,
            "patch folder is still registered as an Xcode resource")
    require("func installBundledResources(credentials: PatchFeedCredentials?)" in store,
            "authenticated remote patch sync is not wired")
    require("didInstallRemoteResources = true" in store,
            "failed remote package installations cannot be retried")
    require("SHA256.hash(data: data)" in resource and "Authorization" in resource
            and "isTrustedPackageURL" in resource,
            "remote patch downloads are missing authentication, host, or digest checks")
    require("installRemoteFeedPackageIfNeeded" in library and "remoteFeedIdentityMatches" in library,
            "remote package installation is missing canonical UUID/name checks")
    require("async function tryStoreLicenseIsActive" in worker
            and "env.RESELLER.fetch" in worker
            and "/api/v1/keys/validate" in worker
            and worker.count("await requireTryStoreLicense(request, env, project)") >= 3,
            "TryStore Worker manifest, report, and blob routes do not all require license validation")
    require('project !== "trystore"' in worker
            and 'project === "trystore" ? "no-store"' in worker,
            "Worker does not preserve other project behavior and disable TryStore cacheability")
    require('if (project !== "trystore") rows.push([{ text: "⬇️ Download"' in worker,
            "Telegram patch manager still exposes public TryStore download URLs")
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
    print(f"PASS: {len(BUNDLED)} source packages have unique mappings, aligned paths, and authenticated remote delivery wiring")


def check_app(app: Path) -> None:
    require(app.is_dir(), f"app bundle missing: {app}")
    info_path = app / "Info.plist"
    require(info_path.is_file(), "Info.plist missing from app")
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("TRYSTORE_PATCH_FEED_URL") == "https://trystore-patch-feed.burgoajustin.workers.dev",
            "remote patch feed URL missing or unexpected in app")
    forbidden = [path for path in app.rglob("*") if path.is_file()
                 and path.suffix.lower() in {".trystore", ".3105"}]
    require(not forbidden, f"patch package files found in IPA: {forbidden[:3]}")
    require(not (app / "Patches").exists(), "Patches folder still exists in the app bundle")
    print(f"PASS: IPA contains no local patch packages; all {len(BUNDLED)} packages are fetched remotely")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    check_source()
    if args.app:
        check_app(args.app)
