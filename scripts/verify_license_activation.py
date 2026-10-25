#!/usr/bin/env python3
"""Check Cloudflare license activation configuration and app-target wiring."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ThreeOneOSFive"
PLIST = APP / "Info.plist"
PROJECT = ROOT / "ThreeOneOSFive.xcodeproj/project.pbxproj"
APP_SOURCE = APP / "App.swift"
MANAGER = APP / "helpers/LicenseManager.swift"
WORKER = ROOT / "cloudflare/license-worker.js"
ACTIVATION_GATE = APP / "helpers/ActivationGate.swift"
GATE = APP / "views/LicenseGateView.swift"
SETTINGS = APP / "views/SettingsView.swift"

EXPECTED_ENDPOINT = "https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate"
EXPECTED_PROJECT = "trystore"
SOURCES_BUILD_IDS = {
    "LicenseManager.swift": ("B71300000000000000000003", "B71300000000000000000001"),
    "LicenseGateView.swift": ("B71300000000000000000004", "B71300000000000000000002"),
}
LOCALIZATIONS = ("en", "vi", "zh-Hans", "es", "pt-BR")
LOCALIZATION_KEYS = (
    "license.gate_kicker", "license.gate_title", "license.gate_message",
    "license.key_placeholder", "license.show_key", "license.hide_key",
    "license.verifying", "license.activate", "license.checking",
    "license.keychain_note", "license.retry", "license.error_required",
    "license.error_configuration", "license.error_secure_storage",
    "license.error_offline", "license.error_server", "license.error_invalid",
    "license.error_expired", "license.error_revoked", "license.error_frozen",
    "license.error_wrong_project", "license.error_inactive",
    "license.settings_section", "license.settings_status", "license.settings_active",
    "license.settings_required", "license.settings_expiration", "license.settings_key",
    "license.settings_verify", "license.settings_forget", "license.forget_title",
    "license.forget_message", "license.forget_action", "license.cancel",
)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def main() -> None:
    try:
        info = plistlib.loads(PLIST.read_bytes())
    except Exception as error:
        fail(f"Info.plist could not be parsed: {error}")

    endpoint = info.get("TRYSTORE_LICENSE_API_URL")
    project_id = info.get("TRYSTORE_PROJECT_ID")
    bundle_key_version = info.get("TRYSTORE_PATCH_BUNDLE_KEY_VERSION")
    require(endpoint == EXPECTED_ENDPOINT, f"unexpected Cloudflare endpoint: {endpoint!r}")
    require(project_id == EXPECTED_PROJECT, f"unexpected license project slug: {project_id!r}")
    require(bundle_key_version == "2", f"new release must request bundle-key version 2: {bundle_key_version!r}")
    parsed_endpoint = urlparse(endpoint)
    require(parsed_endpoint.scheme == "https" and parsed_endpoint.path == "/api/v1/keys/validate",
            "license validation endpoint must use HTTPS and the expected validation route")

    pbx = PROJECT.read_text()
    source_phase = re.search(r"3105A700 /\* Sources \*/ = \{.*?files = \((.*?)\);", pbx, re.S)
    require(source_phase is not None, "SupportPatch Sources phase was not found")
    source_ids = set(re.findall(r"\bB713[0-9A-F]{20}\b", source_phase.group(1)))
    for filename, (file_id, build_id) in SOURCES_BUILD_IDS.items():
        require(file_id in pbx and build_id in pbx, f"Xcode references missing for {filename}")
        require(build_id in source_ids, f"{filename} is not compiled into the SupportPatch target")
        require((APP / ("helpers" if filename == "LicenseManager.swift" else "views") / filename).is_file(),
                f"source file not found: {filename}")

    app_source = APP_SOURCE.read_text()
    manager = MANAGER.read_text()
    worker = WORKER.read_text()
    activation_gate = ACTIVATION_GATE.read_text()
    gate = GATE.read_text()
    settings = SETTINGS.read_text()
    require("@StateObject private var licenseManager = LicenseManager()" in app_source
            and "else if licenseManager.isActive" in app_source
            and "LicenseGateView()" in app_source
            and "licenseManager.beginLaunchSession()" in app_source,
            "app root is not gated by live license validation")
    require("URLSession.shared.data(for: request)" in manager
            and "TRYSTORE_LICENSE_API_URL" in manager
            and "TRYSTORE_PROJECT_ID" in manager,
            "license manager is not configured to call the Cloudflare validation endpoint")
    require("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in manager
            and "SecItemAdd" in manager and "SecItemUpdate" in manager,
            "validated key is not stored using device-only iOS Keychain protection")
    require('"key": key' in manager and '"projectId": projectID' in manager
            and '"deviceId": try deviceID()' in manager,
            "license request is missing key, project, or device identifier fields")
    require('"keyVersion": Bundle.main.object(forInfoDictionaryKey: "TRYSTORE_PATCH_BUNDLE_KEY_VERSION")' in manager,
            "patch-bundle request does not send its configured key version")
    require("import MachO" in activation_gate and "_dyld_image_count()" in activation_gate
            and "_dyld_get_image_name(index)" in activation_gate,
            "anti-instrumentation dyld image probes must import the MachO SDK declarations")
    require("b.keyVersion||'1'" in worker
            and "keyVersion==='1'?'PATCH_BUNDLE_ENCRYPTION_KEY'" in worker
            and "keyVersion==='2'?'PATCH_BUNDLE_ENCRYPTION_KEY_V2'" in worker
            and "const bundleKey=String(e[secretName]||'')" in worker,
            "Worker must preserve the existing v1 key and select the new v2 key only for versioned clients")
    require("keyVersion=project==='trystore'?requestedKeyVersion:'1'" in worker
            and "project==='apple-music'?'APPLE_MUSIC_PATCH_BUNDLE_ENCRYPTION_KEY'" in worker
            and "if(g.slug!==project)" in worker
            and "g.slug!==requestedProject" in worker,
            "Worker must retain live project-scoped checks and Apple Music v1 compatibility")
    require("licenseManager.activate(key: keyInput)" in gate
            and "licenseManager.refresh()" in gate,
            "activation gate does not support activation and retry")
    require("licenseManager.refresh()" in settings and "licenseManager.clear()" in settings,
            "Settings does not expose verification and key removal")
    for secret_name in ("LICENSE_ADMIN_TOKEN", "LICENSE_SIGNING_SECRET", "TELEGRAM_BOT_TOKEN"):
        require(secret_name not in manager and secret_name not in gate and secret_name not in PLIST.read_text(),
                f"server-side secret name leaked into the iOS client: {secret_name}")

    for language in LOCALIZATIONS:
        path = APP / f"{language}.lproj/Localizable.strings"
        text = path.read_text()
        for key in LOCALIZATION_KEYS:
            matches = re.findall(r'^"' + re.escape(key) + r'"\s*=', text, re.M)
            require(len(matches) == 1, f"{language}: expected one translation for {key}, found {len(matches)}")

    print("PASS: Cloudflare license activation endpoint, app gate, Keychain storage, Xcode target, and translations are wired.")


if __name__ == "__main__":
    main()
