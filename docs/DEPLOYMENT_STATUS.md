# Deployment status — 2026-11-20

Scope: TSC2 bundled art, short-lived feed tokens, signed manifests, and the
App Attest schema the two Workers depend on.

## Applied

- D1 `jvztxnx-global-control`:
  - `migrations/0004_feed_key_state.sql` applied; `feed_key_state` now exists
    and is empty, so the feed serves bundle-key version `1`.
  - Existing deployment predated the App Attest merge. The live
    `license_devices` and `api_rate_limits` tables were aligned in place:
    `first_seen` → `first_seen_at`, `last_seen` → `last_seen_at`,
    `revoked_at` added, `count` → `hits`. The same change is recorded as
    `migrations/0004_align_device_rate_schema.sql` for other environments.
- Secrets:
  - `APP_ATTEST_INTERNAL_TOKEN` set on both `jvztxnx-global-control` and
    `trystore-patch-feed` with the same 32+ character value.
  - `FEED_TOKEN_SECRET` set on `trystore-patch-feed`.
  - `MANIFEST_SIGNING_KEY` set on `trystore-patch-feed` (base64 PKCS#8
    Ed25519).
- Workers:
  - `jvztxnx-global-control` deployed from `cloudflare/dist/license-worker.js`
    (esbuild bundle), version `07fc9e53-74ea-4e65-95f5-009599aff2ea`.
    Bindings: `DB`, `APP_ATTEST_APP_ID="K976G5HK7K.cc.forcequit.worse-query"`,
    `APP_ATTEST_ENVIRONMENT="production"`.
  - `trystore-patch-feed` deployed from `cloudflare/patch-feed-worker.js`,
    version `41298eba-205b-4d9f-a0fa-a4e05debaf97`.
- `cloudflare/wrangler.license.toml` is now tracked. It builds
  `dist/license-worker.js` before upload and carries the production App Attest
  vars.

## Live checks

Run against the deployed Workers after upload:

| Check | Result |
| --- | --- |
| `GET /health` on both Workers | 200 |
| Public manifest `hyper-regedit` | 200, signature verifies with pinned key |
| TryStore manifest without credentials | 401 |
| TryStore manifest with a fresh feed token | 200, signature verifies with pinned key |
| TryStore manifest with an expired token | 401 |
| TryStore manifest with a token signed by another secret | 401 |
| App Attest challenge/register/bundle-key without a licence | 401 from the licence Worker through the service binding |
| Legacy `GET /api/patches/trystore/bundle-key` | 405 |
| Public package blob `hyper-regedit` | 200, immutable cache |
| `POST /api/v1/keys/validate` with a bogus key | 200, `valid:false` |
| Rate-limit rows | written with the new `hits` column |

The feed's App Attest routes reached the licence Worker, so the shared
`APP_ATTEST_INTERNAL_TOKEN` is accepted; a missing or wrong value returns 404
from the licence Worker. Device binding for the feed token and the
missing-signing-key `503` are covered by `scripts/verify_patch_feed_worker.mjs`.

## Still device-side

- App Attest is not exercised by an emulator or CI. Attest once on a physical
  device with a real licence, then confirm a second launch uses the assertion
  path and that the bundle-key response contains `feedToken`/`expiresAt`.
- `APP_ATTEST_APP_ID` is set from the Xcode team (`K976G5HK7K`) and bundle ID
  (`cc.forcequit.worse-query`). Confirm the App ID prefix in the Apple
  Developer portal if attestation fails with a hash mismatch.
- The archive step seals `CharacterVault` with the GitHub Actions secret
  `TRYSTORE_BUNDLE_KEY`. It must decode to the same 32 bytes as the feed's
  `APP_BUNDLE_KEY`; a mismatch opens the feed but leaves the vault unreadable.
- The Swift changes were statically checked only. No Xcode build or device
  run was performed on this host.

## Manifest signing key

Public key, pinned in `PatchResourceBundle.swift`:

```
RrxJgZTY9C41WTQyO6+XNHmXp4jI7p6H2ppKwj2qC2o=
```

Rotating the private key requires a client build with the new public half.
Keep the old secret until installed builds have rolled forward.
