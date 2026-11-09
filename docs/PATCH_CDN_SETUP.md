# TryStore authenticated remote patch delivery

The iOS target no longer packages the patch directory. After the license gate succeeds, the client requests the TryStore manifest and patch files from the Cloudflare feed using the saved license key and per-install identifier. The patch Worker checks the license through its existing `RESELLER` service binding before serving TryStore data. The client also validates the manifest host, package size, SHA-256, canonical package UUID, and project identity before importing a package. Known schema-9 visual packages are normalized by the existing migration code.

The patch feed is online-only for initial delivery: an active license and network access are needed for the first successful sync. Validated packages are persisted in the app's protected application-support storage so the app can use its local cache during a session; a later license check still gates app launch. This is distribution control, not DRM: anyone who can run or instrument an authorized client can copy a package after it has been delivered.

## Production rollout

The code change in this repository does not take effect on the live Worker until `cloudflare/patch-feed-worker.js` is deployed to the existing `trystore-patch-feed` Worker. The current Worker already has the required `PATCHES` KV namespace and `RESELLER` service binding, and the current KV manifest contains the 11 package names used by the app. No new server secret or asset upload is required for the current catalog.

Before deployment, preserve the existing Telegram secrets and bindings. After deployment, smoke-test the following without sharing a license key in logs or messages:

1. An unauthenticated GET of `/api/patches/trystore/manifest.json` returns `401`.
2. An unauthenticated GET of a TryStore package URL returns `401` and no cacheable body.
3. The iOS app with a valid TryStore license receives the manifest and every catalog package; the app verifier passes and the normal/Antena patch paths still work.
4. A revoked or expired license is denied by the existing license service.
5. Existing non-TryStore projects continue to receive their current public-feed behavior.

The Telegram patch manager will continue to list, add, replace, and delete TryStore assets, but it will not show a public TryStore download link. Direct TryStore links issued before protection is enabled will stop working without the app's authorization headers. Other project routes remain unchanged.

## Updating assets

Keep approved source `.TRYSTORE` packages under `ThreeOneOSFive/Patches/` for review and feed publishing. They are no longer Xcode resources. Upload or replace a patch through the existing Cloudflare/Telegram patch manager; the Worker updates KV and the manifest, and an authorized app sees that revision on its next sync. Update `FreeFireGame.bundledPatches` only when the app's fixed catalog changes.

Before building, run:

```bash
python3 scripts/verify_legacy_patch_bundle.py
python3 scripts/verify_license_activation.py
npm ci --prefix cloudflare --ignore-scripts
node scripts/verify_patch_feed_worker.mjs
```

After building an app bundle or IPA, run:

```bash
python3 scripts/verify_legacy_patch_bundle.py --app path/to/Payload/TryStore.app
```

The IPA check fails if it finds a `.TRYSTORE`/`.3105` patch file or a `Patches` directory in the app bundle. Build and device-test with macOS/Xcode; Linux cannot compile or sign the iOS target.

## Security boundaries

The app contains the public feed URL, but no reusable server secret. It sends the license key only over HTTPS to the patch Worker; the Worker validates it through `RESELLER` and fails closed on validation errors. The client checks SHA-256 and package identity to detect corruption or mismatched feed entries. Neither symbol stripping nor client-side integrity checks make the IPA impossible to reverse engineer. A determined authorized device owner can instrument the app and copy downloaded packages. The current license validation service accepts a `deviceId` field but does not enforce device binding; do not treat the identifier as an anti-sharing control. App Attest with server-side verification and an explicit recovery policy is a possible future strengthening.
