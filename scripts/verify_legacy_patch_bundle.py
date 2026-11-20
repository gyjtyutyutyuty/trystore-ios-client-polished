#!/usr/bin/env python3
"""Validate TryStore package sources, remote delivery wiring, UI mappings, and IPA exclusions."""
from __future__ import annotations
import argparse
import base64
import hashlib
import os
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
    "TryStore.TRYSTORE": "TryStore",
    "HOLOGRAMAEXCLUSIVO.3105": "HOLOGRAMA EXCLUSIVO",
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


def bundle_key() -> bytes | None:
    raw = os.environ.get("TRYSTORE_BUNDLE_KEY", "").strip()
    if not raw:
        return None
    try:
        key = base64.b64decode(raw, validate=True)
    except Exception as error:
        fail(f"TRYSTORE_BUNDLE_KEY is not valid base64: {error}")
    require(len(key) == 32, "TRYSTORE_BUNDLE_KEY must decode to 32 bytes")
    return key


DECRYPT = (
    "const c=require('crypto');"
    "const bk=Buffer.from(process.argv[1],'hex');"
    "const wk=Buffer.from(process.argv[2],'hex');"
    "const ka=Buffer.from(process.argv[3]);"
    "const pa=Buffer.from(process.argv[4]);"
    "let x=[];process.stdin.on('data',v=>x.push(v));process.stdin.on('end',()=>{"
    "const p=Buffer.concat(x);"
    "const ku=c.createDecipheriv('aes-256-gcm',bk,wk.subarray(0,12));"
    "ku.setAAD(ka);ku.setAuthTag(wk.subarray(wk.length-16));"
    "const ck=Buffer.concat([ku.update(wk.subarray(12,wk.length-16)),ku.final()]);"
    "const n=p.subarray(0,12),t=p.subarray(p.length-16);"
    "const d=c.createDecipheriv('aes-256-gcm',ck,n);d.setAAD(pa);d.setAuthTag(t);"
    "process.stdout.write(Buffer.concat([d.update(p.subarray(12,p.length-16)),d.final()]));});"
)


def package_project(filename: str) -> dict | None:
    envelope = package_metadata(filename)
    require(envelope.get("isPasswordProtected") is False,
            f"bundled package requires a password: {filename}")
    require(envelope.get("publicContentKey") is None,
            f"bundled package still ships its content key: {filename}")
    require(envelope.get("wrappingScheme") == "bundle",
            f"bundled package is not wrapped under the app key: {filename}")
    wrapped = envelope.get("wrappedContentKey")
    require(isinstance(wrapped, bytes) and len(wrapped) == 60,
            f"wrapped content key missing or malformed: {filename}")

    key = bundle_key()
    if key is None:
        return None

    aad_key = f"3105PATCH/v{envelope['schemaVersion']}/key/{envelope['packageID']}".encode()
    aad_payload = (
        f"3105PATCH/v{envelope['schemaVersion']}/payload/{envelope['packageID']}"
    ).encode()
    try:
        decoded = subprocess.run(
            ["node", "-e", DECRYPT, key.hex(), wrapped.hex(), aad_key, aad_payload],
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


def payload_fingerprint(project: dict) -> str:
    """Mirror PatchProjectLibrary.projectPayloadFingerprint."""
    digest = hashlib.sha256()

    def feed(value: str) -> None:
        digest.update(value.encode("utf-8"))
        digest.update(b"\0")

    feed("v1")
    feed(str(project.get("id", "")).upper())
    feed(project.get("name", ""))
    for bundle in sorted(project.get("bundleIdentifiers", [])):
        feed("b")
        feed(bundle)
    directories = sorted(
        project.get("directories", []),
        key=lambda item: (item.get("bundleID", ""), item.get("relativePath", "")),
    )
    for directory in directories:
        feed("d")
        feed(directory.get("bundleID", ""))
        feed(directory.get("relativePath", ""))
    rules = sorted(
        project.get("rules", []),
        key=lambda item: (item.get("bundleID", ""), item.get("relativePath", "")),
    )
    for rule in rules:
        feed("r")
        feed(rule.get("bundleID", ""))
        feed(rule.get("relativePath", ""))
        feed(rule.get("replacementFilename", ""))
        digest.update(hashlib.sha256(rule.get("replacementData") or b"").digest())
    return digest.hexdigest()


def check_source() -> None:
    app = APP_SOURCE.read_text(encoding="utf-8")
    store = STORE.read_text(encoding="utf-8")
    library = LIBRARY.read_text(encoding="utf-8")
    resource = RESOURCE.read_text(encoding="utf-8")
    device_service = DEVICE_SERVICE.read_text(encoding="utf-8")
    transaction = TRANSACTION.read_text(encoding="utf-8")
    pbx = PROJECT.read_text(encoding="utf-8")
    worker = WORKER.read_text(encoding="utf-8")

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

    # The location slot is one package now. Legacy Verde/Rosado identities stay
    # in the app map only so an already-installed copy can still be recognized;
    # they are not part of the shipped catalog.
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
        if project is None:
            continue
        rules = project.get("rules", [])
        require(bool(rules), f"patch has no file rules: {filename}")
        require(all(rule.get("relativePath") == normal_path for rule in rules),
                f"normal/Antena package target differs from expected avatar path: {filename}")
    if None not in decoded_projects.values():
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
    require("didInstallRemoteResources = failures.isEmpty" in store
            and "var failures: [String] = []" in store,
            "failed remote package installations cannot be retried or reported")
    require("SHA256.hash(data: data)" in resource and "Authorization" in resource
            and "isTrustedPackageURL" in resource,
            "remote patch downloads are missing authentication, host, or digest checks")
    require("installRemoteFeedPackageIfNeeded" in library and "remoteFeedIdentityMatches" in library,
            "remote package installation is missing canonical UUID/name checks")
    require(
        "if let existingURL, fileManager.fileExists(atPath: existingURL.path)" in library,
        "first remote install attempts to read a package before its destination exists",
    )
    require("async function tryStoreLicenseIsActive" in worker
            and "env.RESELLER.fetch" in worker
            and "/api/v1/keys/validate" in worker
            and worker.count("await requireTryStoreLicense(request, env, project)") >= 3,
            "TryStore Worker manifest, report, and blob routes do not all require license validation")
    require("wrapTrystorePackage" in worker
            and "APP_BUNDLE_KEY" in worker
            and "/bundle-key" in worker,
            "feed worker does not wrap TryStore packages under the app bundle key")
    require("validateTrystoreUpload" in worker
            and "TRYSTORE_SLOT_IDENTITIES" in worker,
            "feed worker does not reject a package whose project does not match its slot")
    codec = (ROOT / "ThreeOneOSFive/helpers/PatchPackageCodec.swift").read_text(encoding="utf-8")
    key_store = (ROOT / "ThreeOneOSFive/helpers/PatchBundleKeyStore.swift").read_text(encoding="utf-8")
    require('wrappingScheme == "bundle"' in codec
            and "PatchBundleKeyStore.cachedKey()" in codec,
            "client does not unwrap bundle-key packages")
    require("api/patches/trystore/bundle-key" in key_store
            and "X-TryStore-Device-ID" in key_store,
            "client bundle-key endpoint or device binding missing")
    require('LICENSED_PATCH_PROJECTS' in worker
            and 'licensed ? "no-store"' in worker,
            "Worker does not scope license checks and cacheability to licensed projects")
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

    # The binary seed is the offline guard against a package whose rules were
    # swapped with another module. It must describe the packages in this tree.
    if bundle_key() is not None:
        seed_block = re.search(
            r"bundledPayloadFingerprints: \[UUID: String\] = \[(.*?)\n    \]",
            library,
            re.S,
        )
        require(seed_block is not None, "payload fingerprint seed table missing")
        seeds = dict(re.findall(
            r'UUID\(uuidString: "([^"]+)"\)!: "([0-9a-f]{64})"',
            seed_block.group(1),
        ))
        require(len(seeds) >= len(BUNDLED), "payload fingerprint seed table is incomplete")
        for filename, project_name in BUNDLED.items():
            project = package_project(filename)
            require(project is not None, f"cannot decode bundled package: {filename}")
            normalized = dict(project)
            normalized["id"] = canonical_ids[project_name]
            normalized["name"] = project_name
            expected = seeds.get(canonical_ids[project_name].upper())
            require(expected is not None, f"missing payload seed for {project_name}")
            require(expected == payload_fingerprint(normalized),
                    f"payload fingerprint seed is stale for {filename}")

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
