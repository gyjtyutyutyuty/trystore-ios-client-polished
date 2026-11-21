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
    version `f006cd49-a66a-468c-93eb-1590dc38448e`.
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
| `GET /character-vault/version` | 200, 16 files, `keyFingerprint` `6d77…8759` |
| `GET /character-vault/manifest.json` without credentials | 401 |
| `GET /character-vault/rouk/rouk.obj.tsc` without credentials | 401 |
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

## Character vault feed

The IPA used to carry 16 sealed `TSC2` blobs. They now live in the feed's KV
namespace under `vault/trystore/<path>`, with a signed manifest at
`vault/trystore/manifest.json`. Its `version` is a digest of the file list, so
a re-sealed vault with the same key still invalidates installed copies, and
`keyFingerprint` carries the bundle-key fingerprint
(`6d77a77f5c738a5e036b34c4e4c1f4e9627c6c2426e2ddbc5fc4f47d6adb8759`).

| Route | Access |
| --- | --- |
| `GET /api/patches/trystore/character-vault/version` | public; version and file count |
| `GET /api/patches/trystore/character-vault/manifest.json` | licensed; signed |
| `GET /api/patches/trystore/character-vault/<path>` | licensed; sealed bytes |

The client verifies the manifest signature, every size and SHA-256, stores the
sealed copy in Application Support (backup-excluded), and unseals into Caches
only after the bundle key is present. `CharacterVault.purge()` removes both
when the licence is cleared or the runtime tamper probe fires. The archive
script and `tools/verify_ipa_hardening.py` fail if a vault or patch directory
is bundled.

## Still device-side

- App Attest is not exercised by an emulator or CI. Attest once on a physical
  device with a real licence, then confirm a second launch uses the assertion
  path and that the bundle-key response contains `feedToken`/`expiresAt`.
- `APP_ATTEST_APP_ID` is set from the Xcode team (`K976G5HK7K`) and bundle ID
  (`cc.forcequit.worse-query`). Confirm the App ID prefix in the Apple
  Developer portal if attestation fails with a hash mismatch.
- The archive no longer carries `CharacterVault` or `Patches`; the build script
  and `tools/verify_ipa_hardening.py` fail if either is present. The sealed
  vault is published to KV under `vault/trystore/` and the client downloads it
  after the licence check. Codemagic requires the published vault version to
  equal `/api/patches/trystore/bundle-key/fingerprint`.
- `tools/verify_ipa_hardening.py` runs on the archived IPA: it rejects a
  bundled vault or patch directory, a missing `__RESTRICT` segment, or enabled
  document sharing.

## Archive

Codemagic workflow `supportpatch_unsigned_ipa` archived commit `8c855a3` on
build `6b010e0f799fbd143cf98ccc` (2026-11-21). The build compiled with Xcode
26 after two source fixes: `csops` now resolves through `dlsym` instead of the
unavailable variadic `syscall`, and the attested key identifier is kept in a
local so `register` and the Keychain write see a non-optional value. The
temporary build-log relay used to diagnose the earlier failure has been
removed from both the Worker and the archive script; its secret and KV entry
are deleted. The verify step passed on the archived IPA, including
`tools/verify_ipa_hardening.py`: the vault is entirely `TSC2`, `__RESTRICT` is
present, and document sharing is off.

## Manifest signing key

Public key, pinned in `PatchResourceBundle.swift`:

```
RrxJgZTY9C41WTQyO6+XNHmXp4jI7p6H2ppKwj2qC2o=
```

Rotating the private key requires a client build with the new public half.
Keep the old secret until installed builds have rolled forward.
