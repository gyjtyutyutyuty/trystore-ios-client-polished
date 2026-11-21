# Deployment status — 2026-11-21

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
    version `23806b1b-9a8f-4425-823b-901a82d2d2b6`.
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
| Licence-bound `POST` without a licence | 401 |
| Public package blob `hyper-regedit` | 200, immutable cache |
| `POST /api/v1/keys/validate` with a bogus key | 200, `valid:false` |
| Rate-limit rows | written with the new `hits` column |

The feed's App Attest routes reached the licence Worker, so the shared
`APP_ATTEST_INTERNAL_TOKEN` is accepted; a missing or wrong value returns 404
from the licence Worker. Device binding for the feed token and the
missing-signing-key `503` are covered by `scripts/verify_patch_feed_worker.mjs`.

## Licence-bound art release

A sideloaded build cannot always produce an App Attest assertion: the signing
team may differ, the profile may carry the development environment, or a
re-signing tool may drop the entitlement. The feed therefore accepts
`X-TryStore-Attestation-Mode: licence` on
`POST /api/patches/trystore/bundle-key`, validates the live licence and device, and
returns the same key plus feed token. The mode is rate limited and refuses
missing, expired, revoked, or differently bound licences. Activation no longer
depends on the art key at all, so a feed outage or an attestation refusal
leaves the licence usable and only the sealed art pending.

## Still device-side

- App Attest is not exercised by an emulator or CI. Attest once on a physical
  device with a real licence, then confirm a second launch uses the assertion
  path and that the bundle-key response contains `feedToken`/`expiresAt`.
- `APP_ATTEST_APP_ID` is set from the Xcode team (`K976G5HK7K`) and bundle ID
  (`cc.forcequit.worse-query`). Confirm the App ID prefix in the Apple
  Developer portal if attestation fails with a hash mismatch.
- The archive step seals `CharacterVault` with `TRYSTORE_BUNDLE_KEY` when the
  build has it. Codemagic has no key configured, so it uses the checked-in
  `build_support/CharacterVaultTSC2` vault and requires its fingerprint to
  match `/api/patches/trystore/bundle-key/fingerprint`. The key still has to
  match the feed's `APP_BUNDLE_KEY`; a stale pre-sealed vault fails the build
  instead of shipping unreadable art.
- `tools/verify_ipa_hardening.py` runs on the archived IPA in the verify step:
  it rejects a non-TSC2 vault blob, a missing `__RESTRICT` segment, or enabled
  document sharing. The first run against a fresh archive is the next build.

## Archive

Codemagic workflow `supportpatch_unsigned_ipa` archived commit `7329a82` on
build `6b01080d799fbd143cf97363` (2026-11-21). The build compiled with Xcode
26 after two source fixes: `csops` now resolves through `dlsym` instead of the
unavailable variadic `syscall`, and the attested key identifier is kept in a
local so `register` and the Keychain write see a non-optional value. The
temporary build-log relay used to diagnose the earlier failure has been
removed from both the Worker and the archive script; its secret and KV entry
are deleted.

## Manifest signing key

Public key, pinned in `PatchResourceBundle.swift`:

```
RrxJgZTY9C41WTQyO6+XNHmXp4jI7p6H2ppKwj2qC2o=
```

Rotating the private key requires a client build with the new public half.
Keep the old secret until installed builds have rolled forward.
