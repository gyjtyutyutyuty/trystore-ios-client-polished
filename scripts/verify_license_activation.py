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
DEVICE_MIGRATION = ROOT / "cloudflare/migrations/0001_license_devices.sql"
RATE_LIMIT_MIGRATION = ROOT / "cloudflare/migrations/0002_api_rate_limits.sql"
APP_ATTEST_MIGRATION = ROOT / "cloudflare/migrations/0003_app_attest.sql"
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
    "license.error_offline", "license.error_server", "license.error_attestation", "license.error_invalid",
    "license.error_expired", "license.error_revoked", "license.error_frozen",
    "license.error_wrong_project", "license.error_device_limit", "license.error_inactive",
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
    require(endpoint == EXPECTED_ENDPOINT, f"unexpected Cloudflare endpoint: {endpoint!r}")
    require(project_id == EXPECTED_PROJECT, f"unexpected license project slug: {project_id!r}")
    parsed_endpoint = urlparse(endpoint)
    require(parsed_endpoint.scheme == "https" and parsed_endpoint.path == "/api/v1/keys/validate",
            "license validation endpoint must use HTTPS and the expected validation route")

    pbx = PROJECT.read_text(encoding="utf-8")
    source_phase = re.search(r"3105A700 /\* Sources \*/ = \{.*?files = \((.*?)\);", pbx, re.S)
    require(source_phase is not None, "SupportPatch Sources phase was not found")
    source_ids = set(re.findall(r"\bB713[0-9A-F]{20}\b", source_phase.group(1)))
    for filename, (file_id, build_id) in SOURCES_BUILD_IDS.items():
        require(file_id in pbx and build_id in pbx, f"Xcode references missing for {filename}")
        require(build_id in source_ids, f"{filename} is not compiled into the SupportPatch target")
        require((APP / ("helpers" if filename == "LicenseManager.swift" else "views") / filename).is_file(),
                f"source file not found: {filename}")
    release_block = re.search(r"3105AA02 /\* Release \*/ = \{.*?name = Release;", pbx, re.S)
    require(release_block is not None
            and "COPY_PHASE_STRIP = YES;" in release_block.group(0)
            and "DEBUG_INFORMATION_FORMAT = dwarf-with-dsym;" in release_block.group(0)
            and "GCC_GENERATE_DEBUGGING_SYMBOLS = NO;" in release_block.group(0),
            "Release build must strip the app while keeping debug symbols outside the product")

    app_source = APP_SOURCE.read_text(encoding="utf-8")
    manager = MANAGER.read_text(encoding="utf-8")
    worker = WORKER.read_text(encoding="utf-8")
    migration = DEVICE_MIGRATION.read_text(encoding="utf-8")
    rate_limit_migration = RATE_LIMIT_MIGRATION.read_text(encoding="utf-8")
    app_attest_migration = APP_ATTEST_MIGRATION.read_text(encoding="utf-8")
    app_attest_worker = (ROOT / "cloudflare/app-attest.js").read_text(encoding="utf-8")
    patch_feed_worker = (ROOT / "cloudflare/patch-feed-worker.js").read_text(encoding="utf-8")
    key_store = (APP / "helpers/PatchBundleKeyStore.swift").read_text(encoding="utf-8")
    entitlements = (APP / "ThreeOneOSFive.entitlements").read_text(encoding="utf-8")
    activation_gate = ACTIVATION_GATE.read_text(encoding="utf-8")
    gate = GATE.read_text(encoding="utf-8")
    settings = SETTINGS.read_text(encoding="utf-8")
    require("@StateObject private var licenseManager = LicenseManager()" in app_source
            and "else if licenseManager.isActive" in app_source
            and "LicenseGateView()" in app_source
            and "licenseManager.beginLaunchSession()" in app_source,
            "app root is not gated by live license validation")
    require("URLSession.shared.data(for: request)" in manager
            and "TRYSTORE_LICENSE_API_URL" in manager
            and "TRYSTORE_PROJECT_ID" in manager,
            "license manager is not configured to call the Cloudflare validation endpoint")
    require("kSecAttrAccessibleWhenUnlockedThisDeviceOnly" in manager
            and "SecItemAdd" in manager and "SecItemUpdate" in manager,
            "validated key is not stored using device-only iOS Keychain protection")
    require('"key": key' in manager and '"projectId": projectID' in manager
            and '"deviceId": try deviceID()' in manager,
            "license request is missing key, project, or device identifier fields")
    require("patchBundleKey" not in manager and "patch-bundle-key" not in manager,
            "TryStore license manager still requests a remote patch decryption key")
    require("blockedByInstrumentation" not in activation_gate
            and "hasInstrumentationLoaded" not in activation_gate
            and "blockedByInstrumentation" not in app_source,
            "instrumentation detection must not hard-block access to the license-entry screen")
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
    require(DEVICE_MIGRATION.is_file()
            and "CREATE TABLE IF NOT EXISTS license_devices" in migration
            and "PRIMARY KEY (key_id, device_id)" in migration,
            "D1 device-binding migration is missing or incomplete")
    require("const DEVICE_ID=" in worker
            and "async function claimDevice" in worker
            and "max_devices" in worker
            and "device_limit" in worker
            and "claimDevice(e,g,b.deviceId)" in worker
            and "claimDevice(e,g,device)" in worker,
            "Worker does not enforce device binding on validation and bundle-key routes")
    require(APP_ATTEST_MIGRATION.is_file()
            and "CREATE TABLE IF NOT EXISTS app_attest_keys" in app_attest_migration
            and "CREATE TABLE IF NOT EXISTS app_attest_challenges" in app_attest_migration
            and "UNIQUE (license_key_id, device_id)" in app_attest_migration,
            "App Attest D1 registration/challenge migration is missing or incomplete")
    require("handleAppAttestRoute" in worker
            and "verifyAttestation(" in app_attest_worker
            and "verifyAssertion(" in app_attest_worker
            and "consumed_at IS NULL" in app_attest_worker
            and "sign_count=?6" in app_attest_worker,
            "license Worker does not verify Apple attestation/assertions with one-use challenges and atomic counters")
    require("attestation_required" in worker
            and "proxyAppAttest" in patch_feed_worker
            and "method_not_allowed" in patch_feed_worker
            and "APP_ATTEST_INTERNAL_TOKEN" in patch_feed_worker
            and "x-trystore-attestation-mode" in patch_feed_worker
            and "requireTryStoreLicense(request, env, project)" in patch_feed_worker,
            "TryStore bundle key lost App Attest or its licence-bound fallback check")
    require("DCAppAttestService.shared" in key_store
            and "attestKey(" in key_store
            and "generateAssertion(" in key_store
            and "X-TryStore-Device-ID" in key_store
            and "refreshWithLicence" in key_store
            and "X-TryStore-Attestation-Mode" in key_store
            and "com.apple.developer.devicecheck.appattest-environment" in entitlements
            and "APP_ATTEST_ENVIRONMENT = production;" in PROJECT.read_text(),
            "iOS App Attest implementation, entitlement, production environment, or licence-bound fallback is missing")
    require("u.pathname==='/__sendmenu'" not in worker
            and "u.pathname==='/__chatcheck'" not in worker
            and "u.pathname==='/__tgcheck'" not in worker
            and "['/__sendmenu','/__chatcheck','/__tgcheck']" in worker,
            "public Telegram diagnostic endpoints must remain disabled")
    require("async function hyperActivate" in worker
            and "const claim=await claimDevice(e,g,b.deviceId)" in worker
            and "device_mismatch" in worker
            and "Number(p.exp||0)<now()" in worker
            and "String(b.deviceId)!==String(p.device)" in worker,
            "secondary activation and heartbeat routes are missing device binding or token expiry")
    require(RATE_LIMIT_MIGRATION.is_file()
            and "CREATE TABLE IF NOT EXISTS api_rate_limits" in rate_limit_migration
            and "PRIMARY KEY (bucket, subject, window_start)" in rate_limit_migration
            and "async function rateLimit" in worker
            and "async function guardJSON" in worker
            and "MAX_JSON_BYTES=16*1024" in worker
            and "rate_limited" in worker,
            "public license routes are missing request-size and rate-limit controls")
    require("licenseManager.activate(key: keyInput)" in gate
            and "licenseManager.refresh()" in gate,
            "activation gate does not support activation and retry")
    require("licenseManager.refresh()" in settings and "licenseManager.clear()" in settings,
            "Settings does not expose verification and key removal")
    for secret_name in ("LICENSE_ADMIN_TOKEN", "LICENSE_SIGNING_SECRET", "TELEGRAM_BOT_TOKEN"):
        require(secret_name not in manager and secret_name not in gate
                and secret_name not in PLIST.read_text(encoding="utf-8"),
                f"server-side secret name leaked into the iOS client: {secret_name}")

    for language in LOCALIZATIONS:
        path = APP / f"{language}.lproj/Localizable.strings"
        text = path.read_text(encoding="utf-8")
        for key in LOCALIZATION_KEYS:
            matches = re.findall(r'^"' + re.escape(key) + r'"\s*=', text, re.M)
            require(len(matches) == 1, f"{language}: expected one translation for {key}, found {len(matches)}")

    print("PASS: Cloudflare license activation endpoint, app gate, Keychain storage, Xcode target, and translations are wired.")


if __name__ == "__main__":
    main()
