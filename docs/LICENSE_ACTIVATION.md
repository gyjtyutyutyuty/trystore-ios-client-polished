# TryStore license activation

The iOS app validates customer access keys through the existing Cloudflare Global Key Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The app sends the entered key, project slug, app version, and a random per-install device identifier over HTTPS. A key is saved only after successful validation, in the app's device-only iOS Keychain. The admin token and signing secret remain server-side and are not included in the app.

TryStore downloads approved `.TRYSTORE` packages from the patch feed; the iOS target does not package the patch directory. The bundle key is not returned by the legacy GET route. The client first requests a short-lived challenge, registers a Secure Enclave-backed App Attest key when needed, then sends a fresh assertion bound to the POST bundle-key request. Only a valid license/device record and a valid App Attest assertion release the key. The app fails closed if App Attest is unsupported or the server cannot verify it. See `docs/APP_ATTEST_SETUP.md` for the required server and Apple Developer configuration.

## Device binding

The global-control Worker validates the submitted UUID-form `deviceId` against the D1 `license_devices` table and enforces each key's `max_devices` value. The App Attest key registration is bound to the same license/device row; challenges are one-use and assertion counters are persisted with compare-and-swap updates. Do not embed an admin, internal Worker, or signing secret in the iOS client.
