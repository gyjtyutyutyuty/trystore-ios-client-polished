# TryStore license activation

The iOS app validates customer access keys through the existing Cloudflare Global Key Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The endpoint was checked during implementation and returned the Worker health response. The Worker source in `cloudflare/license-worker.js` routes `/api/v1/keys/validate` through `tryValidate`, which checks that a key exists, is active, has not expired, and belongs to the `trystore` project. Its response contract is `valid`, `outcome`, and `expiresAt`.

The app sends the entered key, project slug, app version, and a random per-install device identifier over HTTPS. A key is saved only after successful validation, in the app's device-only iOS Keychain. The admin token and signing secret remain server-side and are not included in the app.

## Encrypted bundled resources

The IPA includes the bundled `.3105` patch packages only as AES-256-GCM ciphertext at `ThreeOneOSFive/Patches/Encrypted/*.3105.enc`. After license validation, the app requests `POST /api/v1/keys/patch-bundle-key` with the same license key, device identifier, and `projectId`. The Worker rechecks that the license is active, unexpired, and for `trystore` before returning the key. It also validates legacy keys through the existing license backend. The iOS client verifies that the returned key is 32 bytes, keeps it in memory only, and decrypts resources when importing them; it does not save the bundle key to Keychain.

The key is stored as the Cloudflare Worker secret `PATCH_BUNDLE_ENCRYPTION_KEY`, not in app source or the IPA. To regenerate ciphertext resources, set `PATCH_BUNDLE_KEY_BASE64` in a private build environment to the base64-encoded 32-byte key and run:

```bash
node scripts/encrypt_bundled_patches.mjs
```

The source `.3105` files in `ThreeOneOSFive/Patches/` are build inputs; Xcode must package the encrypted files in `Patches/Encrypted/`, not those inputs. Never put the server key in source control or build logs.

This raises the bar for casual archive inspection, but does not make the content unrecoverable: a person with an authorized app/device can capture the key or plaintext after runtime decryption. The existing license service also does not enforce device binding, as noted below.

## Important current limitation

The existing `/api/v1/keys/validate` TryStore route does **not** enforce device binding: it ignores the submitted `deviceId` and does not consult the key's `max_devices` value. The bundle-key route requires an active license but does not independently bind that license to a device, so a shared active license can be used to request the same key from another device. Enforcing one-device activation requires a separate server-side Worker/D1 change; do not implement it by embedding an admin or signing secret in the iOS client.
