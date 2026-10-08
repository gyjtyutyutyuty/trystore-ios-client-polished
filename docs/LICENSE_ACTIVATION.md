# TryStore license activation

The iOS app validates customer access keys through the existing Cloudflare Global Key Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The endpoint was checked during implementation and returned the Worker health response. The Worker source in `cloudflare/license-worker.js` routes `/api/v1/keys/validate` through `tryValidate`, which checks that a key exists, is active, has not expired, and belongs to the `trystore` project. Its response contract is `valid`, `outcome`, and `expiresAt`.

The app sends the entered key, project slug, app version, and a random per-install device identifier over HTTPS. A key is saved only after successful validation, in the app's device-only iOS Keychain. The admin token and signing secret remain server-side and are not included in the app.

## Important current limitation

The existing `/api/v1/keys/validate` TryStore route does **not** enforce device binding: it ignores the submitted `deviceId` and does not consult the key's `max_devices` value. The device-only Keychain protects the locally saved copy, but the same key can still be entered on another device if shared. Enforcing one-device activation requires a separate server-side Worker/D1 change; do not implement it by embedding an admin or signing secret in the iOS client.
