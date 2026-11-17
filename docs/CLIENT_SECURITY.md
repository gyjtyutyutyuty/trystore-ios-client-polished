# TryStore iOS client security posture

## What this hardening does

- Release builds use optimized whole-module Swift compilation, strip installed-product and Swift symbols, remove dead code, and omit generated debug information. Keep Release as the only configuration used for distribution; retain private dSYMs outside the public app bundle if crash symbolication is needed.
- License keys and the per-install identifier are saved in the iOS Keychain using `WhenUnlockedThisDeviceOnly`. This prevents access while the device is locked and prevents migration through backups to another device. The app must be unlocked to validate or retrieve these values.
- The iOS target no longer includes the TryStore patch directory as a resource. An active license is required to fetch a manifest or package from the patch Worker; the Worker validates via the existing license service binding and fails closed. The client verifies the HTTPS host, SHA-256, package UUID, and expected package identity before installation.
- The license/admin and signing secrets remain on the server. Never add these credentials, or another reusable server secret, to Swift, Info.plist, CI artifacts, or the app bundle.
- The license gate checks server validation at launch and when the app returns to the foreground. Before opening, the client must complete App Attest registration when needed and submit a fresh, request-bound assertion to obtain the bundle key. The server validates Apple’s attestation chain and app identity, consumes one-use challenges, binds keys to license/device records, and atomically advances assertion counters. Missing configuration or any failure denies the app session.
- The app already attempts to deny debugger attachment and perform runtime security checks. These are friction measures, not a trust boundary; a determined attacker can bypass them.

## Limits that cannot be removed from an installable client

An iOS app runs on a device controlled by its user. A determined person can inspect the executable, disassemble code, instrument runtime behavior, alter local checks, and extract files delivered to that app. Remote authorization protects the feed from unauthenticated downloads, while SHA-256 and identity checks detect corrupted or mismatched packages. Once an authorized client receives a patch, a determined device owner can still copy it. There is no honest way to make a client IPA "anticrackable" or impossible to reverse engineer.

The license service enforces the submitted `deviceId` and each key's `max_devices` value in D1, including before releasing patch-bundle material. App Attest adds server-verifiable evidence that supported requests came from a genuine app instance, but it is not user identity, does not make the client unmodifiable, and cannot prevent copying after an authorized app receives decrypted data. Non-supported devices and invalid or misconfigured attestations fail closed.

## Release checklist

1. Build and distribute only the Release configuration through the intended signed distribution channel.
2. Keep signing keys, API credentials, and any server-side encryption keys in a secret manager; rotate any credential that was ever committed or bundled.
3. Keep dSYMs private and protect CI logs/artifacts. Do not upload them publicly.
4. Apply `cloudflare/migrations/0003_app_attest.sql` to the Global Key Control D1 database, configure the App Attest app ID/environment, and set the same random `APP_ATTEST_INTERNAL_TOKEN` secret on the license and patch-feed Workers. See `docs/APP_ATTEST_SETUP.md`.
5. Confirm the production patch Worker checks active licenses before returning TryStore manifest or package data, rejects the old TryStore bundle-key GET route, and only releases the key after a valid App Attest assertion.
6. Run `python3 scripts/verify_license_activation.py`, `python3 scripts/verify_legacy_patch_bundle.py`, `node scripts/verify_app_attest_worker.mjs`, and `node scripts/verify_patch_feed_worker.mjs`; after build, also run the patch verifier against the app bundle to confirm no patch assets are present.
7. Build and device-test on macOS with Xcode; this Linux environment cannot compile or sign the iOS target. Confirm production App Attest succeeds on supported hardware and expired/revoked licenses, bad assertions, replayed challenges, and development attestations are rejected by production.
