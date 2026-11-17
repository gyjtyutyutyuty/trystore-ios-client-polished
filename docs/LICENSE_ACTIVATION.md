# TryStore license activation

The iOS app validates customer access keys through the existing Cloudflare Global Key Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The app sends the entered key, project slug, app version, and a random per-install device identifier over HTTPS. A key is saved only after successful validation, in the app's device-only iOS Keychain. The admin token and signing secret remain server-side and are not included in the app.

Patch packages are separate from license validation. TryStore now ships its approved `.TRYSTORE` packages as local app resources and does not call the Cloudflare patch-bundle-key route to import them. A valid license is still required to enter the app; license status is rechecked at launch or when the app becomes active.

## Device binding

The global-control Worker now validates the submitted UUID-form `deviceId` against the D1 `license_devices` table and enforces each key's `max_devices` value. The default generated key allows one device. A second device receives `device_limit`, and the patch-bundle-key endpoint applies the same check before releasing bundle material. The migration is documented in `docs/LICENSE_DEVICE_BINDING.md`; do not implement this by embedding an admin or signing secret in the iOS client.
