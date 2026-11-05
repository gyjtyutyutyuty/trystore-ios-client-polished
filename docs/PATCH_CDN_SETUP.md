# TryStore patches — offline IPA bundle and optional Telegram staging

The iOS app no longer checks a remote patch feed, downloads patch packages, or reports feed status. Patch updates are delivered in a newly built IPA. This keeps patch activation available offline after installation; it also means changes made to the optional Cloudflare/Telegram staging service do not change an already-installed app.

## Offline IPA package flow

The 11 patch packages shipped in the current snapshot are source files under `ThreeOneOSFive/Patches/`. The CI workflow encrypts each package into its own named data asset using the `PATCH_BUNDLE_KEY_BASE64` Actions secret, verifies the complete source-to-asset map, and compiles those assets into the IPA. At launch, the app installs the embedded package data into its local patch library; the normal select, activate, and restore controls operate on those local packages. The Azul, Balas Magicas, and additional Aim modules are in the same bundle as the other patch modules.

To update the shipped snapshot, replace or add the approved `.TRYSTORE` source files under `ThreeOneOSFive/Patches/`, update the explicit maps in `scripts/encrypt_bundled_patches.mjs`, `ThreeOneOSFive/helpers/PatchResourceBundle.swift`, and `ThreeOneOSFive/helpers/PatchProjectStore.swift`, then update `scripts/verify_legacy_patch_bundle.py` and build a new IPA. The build fails if the source file set and mappings do not match. Schema-9 legacy visual packages are supported only through the bundled-resource decoder and are normalized into the current local package format during installation.

The client performs no runtime HTTP request to the patch-feed worker. License validation remains separate and is not affected by this change.

## Optional Cloudflare/Telegram staging service

The Worker can still be used as an administrative staging service for receiving, reviewing, and retaining patch files, but it is not connected to the iOS app's runtime. Uploading or replacing a package in the Worker alone will not update devices; approved packages must be copied into the IPA source bundle and shipped in a new IPA.

| Component | Path |
| --- | --- |
| Worker (manifest, blobs, and Telegram bot webhook) | `cloudflare/patch-feed-worker.js` |
| Wrangler configuration | `cloudflare/wrangler.toml` |
| IPA source packages | `ThreeOneOSFive/Patches/` |
| Build-time encrypted asset generator | `scripts/encrypt_bundled_patches.mjs` |

Projects handled by the optional Worker include `trystore`, `apple-music`, and `hyper-regedit`. Its KV layout and bot endpoints remain an administrative facility; the iOS client no longer consumes the manifest or sends sync reports.

### Deploy the optional Worker

```bash
cd cloudflare
npm install
npx wrangler login
npx wrangler secret put TELEGRAM_BOT_TOKEN
npx wrangler secret put TELEGRAM_WEBHOOK_SECRET
npx wrangler secret put TELEGRAM_OWNER_ID
npx wrangler deploy
```

The Worker can continue to own the Telegram webhook, handle patch-management callbacks, and forward other Telegram updates through the reseller service binding. Bot uploads are staging inputs only; they do not live-update the iOS app.

### Bundle and release an update

1. Retrieve the intended package from the staging service or another trusted source and verify its project identity and contents.
2. Replace or add the corresponding `.TRYSTORE` source in `ThreeOneOSFive/Patches/`.
3. Update all explicit asset, project-name, Aim/Visual catalog, and validator mappings. Keep package identities unique; the two Holograma legacy source packages are remapped to separate bundled IDs by the app.
4. Run the repository validators and dispatch a new IPA build. The encrypted data assets are generated in CI from the configured build secret and included in the compiled `Assets.car`.
5. Install the new IPA. Existing installs are reconciled with the new embedded snapshot based on the package source revision; no patch-feed call is made by the app.

A bundled snapshot is fixed for each IPA version. An already installed IPA cannot receive later patch changes from Telegram or Cloudflare without installing a new IPA.
