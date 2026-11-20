# TryStore authenticated remote patch delivery

The iOS target no longer packages the patch directory. After the license gate succeeds, the client requests the TryStore manifest and patch files from the Cloudflare feed using the saved license key and per-install identifier. The patch Worker checks the license through its existing `RESELLER` service binding before serving TryStore data. The client also validates the manifest host, package size, SHA-256, canonical package UUID, and project identity before accepting a package into the library. Known schema-9 visual packages are normalized by the existing migration code.

The patch feed is online-only for initial delivery: an active license and network access are needed for the first successful sync. Validated packages are persisted in the app's protected application-support storage so the app can use its local cache during a session; a later license check still gates app launch. This is distribution control, not DRM: anyone who can run or instrument an authorized client can copy a package after it has been delivered.

## Production rollout

The updated `cloudflare/patch-feed-worker.js` was deployed to the existing `trystore-patch-feed` Worker on 2026-11-09. Cloudflare deployment ID: `75f2d9d0-fcc9-4929-b388-bc104ce762ad`; active version: `ef6cdb9c-56f4-4d5c-addb-b44d0be6ccea`. The content-only upload preserved the existing `PATCHES` KV namespace, `RESELLER` service binding, public variables, and Telegram secrets. The KV manifest remains unchanged; no asset upload was needed.

Post-deployment checks completed without sharing a license key:

1. An unauthenticated GET of `/api/patches/trystore/manifest.json` returns `license_required` (HTTP 401).
2. An unauthenticated GET of a TryStore package URL returns `license_required` (HTTP 401).
3. The Apple Music manifest remains publicly accessible.
4. Cloudflare's deployed module checksum matches the locally tested Wrangler bundle, excluding only the stale source-map reference.

Still required before shipping the updated iOS client: verify a valid licensed app syncs the full catalog and normal/Antena patch paths, and verify revoked/expired keys are rejected by the existing license service.

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

## Rotating the bundle key

The feed serves one wrapping key version per project. The version lives in D1
(`feed_key_state`), so retiring a key is a data change, not a deploy.

1. Generate a new 32-byte key and store it as the next Worker secret:
   `wrangler secret put APP_BUNDLE_KEY_V2 --config wrangler.toml`.
2. Apply the schema: `wrangler d1 execute jvztxnx-global-control --remote --file migrations/0004_feed_key_state.sql`.
3. In the admin bot, run `/keyversion trystore` to see what is served, then
   `/rotate trystore 2`. Every stored package is re-wrapped before the pointer
   moves, so no device receives a key that cannot open its package. The reply
   reports how many packages were rewrapped, or the first file that failed.
4. Confirm `/keyversion trystore` reports `2`, then delete the retired secret:
   `wrangler secret delete APP_BUNDLE_KEY`.

A rotation is reversible while the old secret still exists (`/rotate trystore 1`).
After the old secret is deleted, a client that still holds a retired key cannot
unwrap anything until it calls `/bundle-key` again; the app now does that at the
start of every sync, so the next sync recovers on its own.

Failing closed matters here: if the version in `feed_key_state` has no secret,
`/bundle-key` returns `503 key_unavailable` instead of falling back to the
previous key, and an upload refuses to publish rather than storing a payload in
the clear.
