# TryStore iOS client security posture

## What this hardening does

- Release builds use optimized whole-module Swift compilation, strip installed-product and Swift symbols, remove dead code, and omit generated debug information. Keep Release as the only configuration used for distribution; retain private dSYMs outside the public app bundle if crash symbolication is needed.
- License keys and the per-install identifier are saved in the iOS Keychain using `WhenUnlockedThisDeviceOnly`. This prevents access while the device is locked and prevents migration through backups to another device. The app must be unlocked to validate or retrieve these values.
- The iOS target no longer includes the TryStore patch directory as a resource. An active license is required to fetch a manifest or package from the patch Worker; the Worker validates via the existing license service binding and fails closed. The client verifies the HTTPS host, SHA-256, package UUID, and expected package identity before installation.
- The license/admin and signing secrets remain on the server. Never add these credentials, or another reusable server secret, to Swift, Info.plist, CI artifacts, or the app bundle.
- The license gate checks server validation at launch and when the app returns to the foreground. Authorization decisions should remain server-side; client-side checks can be patched by a device owner.
- The app already attempts to deny debugger attachment and perform runtime security checks. These are friction measures, not a trust boundary; a determined attacker can bypass them.
- Release binaries carry a `__RESTRICT,__restrict` segment (`OTHER_LDFLAGS` in the Xcode target). `dyld` ignores `DYLD_INSERT_LIBRARIES` for a main executable that has it. `Hardening.hasRestrictedSegment()` walks the loaded Mach-O header and treats a missing segment as tampering, so a rebuilt or rewritten binary fails closed.
- `Hardening` also probes loopback ports 27042/27043 (Frida server and control), reads `csops(CS_OPS_STATUS)` for `CS_DEBUGGED`, and keeps the existing `sysctl(P_TRACED)`, `DYLD_*`/`FRIDA_*` environment, dyld image, jailbreak-path and writable-`/private` checks.
- `TamperMonitor` re-runs the probe every three seconds while the app is active. On the first indicator it closes the gate, revokes the licence, deletes the wrapped bundle key and purges decoded workspaces. Launch and foreground transitions do the same through `LicenseManager.handleRuntimeTamper()`.
- The licence decision itself is still a client-side branch. A binary patch that flips it bypasses the gate; it does not recover the server-held bundle key, so feed content stays sealed. See `docs/IPA_CRACK_REPORT.md` for the concrete 1.1.1 (16) analysis and patch set. Treat client checks as friction and keep authorization, device binding and key release server-side.
- Nothing readable as a patch is left in `Documents`. Packages stay sealed on disk in application support (the content key is only in the Keychain), and the decoded workspace tree now lives in application support with `FileProtectionType.complete` and is excluded from backups. A one-time migration moves any tree left in `Documents/Patches` and deletes the exposed copy. On a hardening failure the license is revoked and every workspace is purged, so a tampered process is not left holding decoded payloads.

## Limits that cannot be removed from an installable client

An iOS app runs on a device controlled by its user. A determined person can inspect the executable, disassemble code, instrument runtime behavior, alter local checks, and extract files delivered to that app. Remote authorization protects the feed from unauthenticated downloads, while SHA-256 and identity checks detect corrupted or mismatched packages. Once an authorized client receives a patch, a determined device owner can still copy it. There is no honest way to make a client IPA "anticrackable" or impossible to reverse engineer.

The license service now enforces device binding by default: `/api/v1/keys/validate` records each device against `license_devices` and refuses a key once its `max_devices` (default 1) is reached, and `/api/v1/keys/patch-bundle-key` always binds. A deployment can opt out with `ENFORCE_DEVICE_BINDING=0`, which is not recommended because it makes one key usable on any number of devices. Provide a documented reset path for customers who replace hardware. App Attest can add server-verifiable signals for supported devices, but requires a separate server integration and does not prove that a client is unmodified.

On-disk protection is not a wall against a jailbroken device. Filza with root can read the app container and the Keychain while the device is unlocked, so no container layout makes a delivered patch unextractable; complete protection only closes the window while the device is locked, and excluding the tree from backups keeps it out of iCloud and iTunes copies. The only reliable reduction is to persist less: keep packages sealed, re-decode at use, and purge decoded trees, which is what the app now does. If payloads must never exist on disk at all, the apply path has to decode from the package in memory instead of materializing a workspace; that is a larger change than a storage move.

## Release checklist

1. Build and distribute only the Release configuration through the intended signed distribution channel.
2. Keep signing keys, API credentials, and any server-side encryption keys in a secret manager; rotate any credential that was ever committed or bundled.
3. Keep dSYMs private and protect CI logs/artifacts. Do not upload them publicly.
4. Confirm the production patch Worker checks active licenses before returning TryStore manifest or package data; direct unauthenticated TryStore URLs must fail closed.
5. Run `python3 scripts/verify_license_activation.py` and `python3 scripts/verify_legacy_patch_bundle.py`; after build, also run the patch verifier against the app bundle to confirm no patch assets are present.
6. Build and device-test on macOS with Xcode; this Linux environment cannot compile or sign the iOS target. Confirm an authorized sync succeeds and an expired/revoked license is rejected.
7. After archiving, run `python3 tools/audit_ipa.py <ipa>` and confirm `__RESTRICT` is present, `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are `false`, and no high finding remains. The 1.1.1 (16) artifact failed the first two checks; see `docs/IPA_CRACK_REPORT.md`.
