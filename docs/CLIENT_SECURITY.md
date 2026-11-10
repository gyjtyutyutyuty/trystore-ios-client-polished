# TryStore iOS client security posture

## What this hardening does

- Release builds use optimized whole-module Swift compilation, strip installed-product and Swift symbols, remove dead code, and omit generated debug information. Keep Release as the only configuration used for distribution; retain private dSYMs outside the public app bundle if crash symbolication is needed.
- License keys and the per-install identifier are saved in the iOS Keychain using `WhenUnlockedThisDeviceOnly`. This prevents access while the device is locked and prevents migration through backups to another device. The app must be unlocked to validate or retrieve these values.
- The iOS target no longer includes the TryStore patch directory as a resource. An active license is required to fetch a manifest or package from the patch Worker; the Worker validates via the existing license service binding and fails closed. The client verifies the HTTPS host, SHA-256, package UUID, and expected package identity before installation.
- The license/admin and signing secrets remain on the server. Never add these credentials, or another reusable server secret, to Swift, Info.plist, CI artifacts, or the app bundle.
- The license gate checks server validation at launch and when the app returns to the foreground. Authorization decisions should remain server-side; client-side checks can be patched by a device owner.
- The app already attempts to deny debugger attachment and perform runtime security checks. These are friction measures, not a trust boundary; a determined attacker can bypass them.

## Limits that cannot be removed from an installable client

An iOS app runs on a device controlled by its user. A determined person can inspect the executable, disassemble code, instrument runtime behavior, alter local checks, and extract files delivered to that app. Remote authorization protects the feed from unauthenticated downloads, while SHA-256 and identity checks detect corrupted or mismatched packages. Once an authorized client receives a patch, a determined device owner can still copy it. There is no honest way to make a client IPA "anticrackable" or impossible to reverse engineer.

The current license validation service accepts a `deviceId` field but does not enforce device binding or its `max_devices` value. The ID is sent with patch requests as context, not as a theft-prevention guarantee. For stronger protection, enforce device binding in the license service with a documented recovery/reset path. App Attest can add server-verifiable signals for supported devices, but requires a separate server integration and does not prove that a client is unmodified.

## Release checklist

1. Build and distribute only the Release configuration through the intended signed distribution channel.
2. Keep signing keys, API credentials, and any server-side encryption keys in a secret manager; rotate any credential that was ever committed or bundled.
3. Keep dSYMs private and protect CI logs/artifacts. Do not upload them publicly.
4. Confirm the production patch Worker checks active licenses before returning TryStore manifest or package data; direct unauthenticated TryStore URLs must fail closed.
5. Run `python3 scripts/verify_license_activation.py` and `python3 scripts/verify_legacy_patch_bundle.py`; after build, also run the patch verifier against the app bundle to confirm no patch assets are present.
6. Build and device-test on macOS with Xcode; this Linux environment cannot compile or sign the iOS target. Confirm an authorized sync succeeds and an expired/revoked license is rejected.
