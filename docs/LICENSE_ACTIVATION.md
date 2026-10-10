# TryStore license activation

The iOS app validates customer access keys through the existing Cloudflare Global Key Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The endpoint was checked during implementation and returned the Worker health response. The Worker source in `cloudflare/license-worker.js` routes `/api/v1/keys/validate` through `tryValidate`, which checks that a key exists, is active, has not expired, and belongs to the `trystore` project. Its response contract is `valid`, `outcome`, and `expiresAt`.

The app sends the entered key, project slug, app version, and a random per-install device identifier over HTTPS. A key is saved only after successful validation, in the app's device-only iOS Keychain. The admin token and signing secret remain server-side and are not included in the app.

## Encrypted asset-catalog resources

The eight source `.3105` packages are each encrypted with AES-256-GCM and stored as `.bin` files in patch-named Data Sets under `ThreeOneOSFive/Assets.xcassets/`. Xcode compiles these Data Sets into `Assets.car`; they do not appear as eight loose patch files when the IPA is unzipped. The ciphertext is nevertheless inside the IPA and may be recovered from `Assets.car` with asset-catalog tools.

After license validation, the app requests `POST /api/v1/keys/patch-bundle-key` with the license key, device identifier, and `projectId`. The Worker rechecks that the license is active, unexpired, and for `trystore` before returning the 32-byte key. The app reads the encrypted Data Sets locally through `NSDataAsset`, decrypts them in memory, and imports their package data. It does not save the decryption key to Keychain or write the encrypted `.bin` assets separately to app files.

The decryption key is stored as the Cloudflare Worker secret `PATCH_BUNDLE_ENCRYPTION_KEY`. To regenerate the encrypted asset Data Sets after updating a source package, set `PATCH_BUNDLE_KEY_BASE64` in a private environment to the base64-encoded 32-byte key and run:

```bash
node scripts/encrypt_bundled_patches.mjs
```

The command rewrites the eight `.bin` Data Sets and their `Contents.json` metadata under `Assets.xcassets`; commit those generated assets with the app. The source `.3105` files in `ThreeOneOSFive/Patches/` are encryption inputs and are not copied into the IPA. Never put the decryption key in source control or build logs. If the Worker key secret changes, regenerate all eight assets with that same key.

This hides the separate patch files and original filenames from ordinary IPA extraction; it does not remove their ciphertext from the IPA. A determined person can extract the `.bin` data from `Assets.car`, and a licensed device can recover plaintext after runtime decryption. The existing license service also does not enforce device binding, as noted below.

## Important current limitation

The existing `/api/v1/keys/validate` TryStore route does **not** enforce device binding: it ignores the submitted `deviceId` and does not consult the key's `max_devices` value. The bundle-key route requires an active license but does not independently bind that license to a device, so a shared active license can be used to request the same key from another device. Enforcing one-device activation requires a separate server-side Worker/D1 change; do not implement it by embedding an admin or signing secret in the iOS client.
