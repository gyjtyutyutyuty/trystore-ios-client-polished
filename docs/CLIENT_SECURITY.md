# TryStore iOS client security posture

## What this hardening does

- Release builds use optimized whole-module Swift compilation, strip installed-product and Swift symbols, remove dead code, and omit generated debug information. Keep Release as the only configuration used for distribution; retain private dSYMs outside the public app bundle if crash symbolication is needed.
- License keys and the per-install identifier are saved in the iOS Keychain using `WhenUnlockedThisDeviceOnly`. This prevents access while the device is locked and prevents migration through backups to another device. The app must be unlocked to validate or retrieve these values.
- The license/admin and signing secrets remain on the server. Never add these credentials, or another reusable server secret, to Swift, Info.plist, CI artifacts, or the app bundle.
- The license gate checks server validation at launch and when the app returns to the foreground. Authorization decisions should remain server-side; client-side checks can be patched by a device owner.

## Limits that cannot be removed from an installable client

An iOS app runs on a device controlled by its user. A determined person can inspect the executable, disassemble code, instrument runtime behavior, alter local checks, and extract files shipped inside the IPA. The bundled `.TRYSTORE` resources and local patch-handling logic are therefore not confidential merely because the release is optimized or symbol-stripped. Obfuscation and debugger/jailbreak detection only raise the cost for some attackers; they are bypassable and must not be treated as authorization controls.

For stronger commercial protection, keep valuable secrets and high-value decisions off-device, use short-lived server-issued authorization, and rate-limit/revoke access server-side. If device binding is required, enforce it in the license service using the submitted device identifier and a documented recovery/reset flow; the current TryStore endpoint does not enforce the `deviceId` field. App Attest can add server-verifiable signals for supported devices, but it is an additional server integration, not proof that a client is unmodified or impossible to reverse engineer.

## Release checklist

1. Build and distribute only the Release configuration through the intended signed distribution channel.
2. Keep signing keys, API credentials, and any server-side encryption keys in a secret manager; rotate any credential that was ever committed or bundled.
3. Keep dSYMs private and protect CI logs/artifacts. Do not upload them publicly.
4. Review every bundled asset/package as extractable by an installer. Do not put data there whose secrecy is required for security.
5. Run `python3 scripts/verify_license_activation.py` and the patch bundle verifier before release. Build and device-test on macOS with Xcode; this Linux environment cannot compile the iOS target.
