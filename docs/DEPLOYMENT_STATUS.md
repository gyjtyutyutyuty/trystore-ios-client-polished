# Deployment status — 2026-11-21

Scope: TSC2 bundled art, short-lived feed tokens, signed manifests, and the
App Attest schema the two Workers depend on.

## Applied

- D1 `jvztxnx-global-control`:
  - `migrations/0004_feed_key_state.sql` applied; `feed_key_state` seeds the
    served key version and now holds version `2` for `trystore`, `apple-music`
    and `hyper-regedit` after the rotation below.
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
| `GET /character-vault/version` | 200, 16 files, `keyFingerprint` `ed05…6b50` |
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

## Bundle-key rotation (2026-11-21)

The version-1 bundle key had been recovered from a project secret, so it was
treated as burned. Rotation is a data change, not a deploy
(`scripts/rotate_bundle_key.py`):

- `APP_BUNDLE_KEY_V2` set on `trystore-patch-feed`; `feed_key_state` moved to
  version `2` for `trystore`, `apple-music` and `hyper-regedit`.
- 25 of 25 packages re-wrapped: the ten already carrying `wrappingScheme=bundle`
  were unwrapped with v1 and sealed with v2; the fifteen carrying an in-band
  `publicContentKey` were wrapped for the first time. Manifests were rewritten
  with the new SHA-256, size, `keyVersion` and `?v=` URL, then the D1
  `feed_blobs` override for `trystore` was deleted so KV is authoritative.
- The 16 committed `TSC2` blobs were re-sealed with
  `HKDF-SHA256(v2, salt="trystore-character-vault-v1", info="TSC2/key")` and
  republished. Old fingerprint `6d77…8759`, new fingerprint
  `ed05f733621ace3b4665336ab7b11dee2adfb7c047cf7afc0300082095f26b50`;
  vault version is now `42604b0e0445c649b5a7f9d57a89cefd2d75502cb58ce99be2858d259c9b677d`.
- Verification pulled every rotated package and vault blob back from KV,
  decrypted with v2 and compared the plaintext with the pre-rotation copy: 25
  package payloads and 16 vault blobs matched exactly.

`APP_BUNDLE_KEY` (v1) is still installed so an in-flight device can finish with
a cached key. Delete it once the 24-hour client cache has expired.

## 3105 adapter hardening (2026-11-21)

The `3105api` adapter wrote the licence key verbatim into
`access_logs.key_value` and logged the full query string, so one D1 read or log
export handed out working credentials. Deployed as version
`0562dfc6-e121-4f22-b786-8c8295af6360`:

- `access_logs` now stores `k1:<HMAC-SHA-256(pepper, key)[:16]>`; the pepper is
  the `ACCESS_LOG_PEPPER` secret. All 1,198 existing rows were overwritten with
  `purged` (`cloudflare/3105-security-scrub.sql`); a live insert was confirmed
  to store `k1:…`, not the key.
- `/rest/v1/*`, `/realtime/*` and `/patches/*` require the Supabase `apikey`
  (header or `?apikey=`); anonymous calls return 401.
- The device table returns a truncated hash instead of `device_hash`, and a
  device can only be bound to an active, unexpired key. Both routes are rate
  limited through `api_rate_limits`.
- `console.log` redacts `key_value`, `apikey`, `authorization` and `token`.
- The adapter forwards `cf-connecting-ip` to the licence Worker. Without it,
  every resolve bucketed under `unknown` and one script could exhaust the
  shared 30/min limit for all users.

The trust boundary is still a live licence: App Attest is the only proof that a
release runs on genuine hardware, and `app_attest_keys` is empty because no
sideloaded build completed registration. The exposed D1 dump contains the
licence values that were in `access_logs`; revoking and reissuing those keys is
the only way to cut off a copy that already left the database.

## Character vault feed

The IPA used to carry 16 sealed `TSC2` blobs. They now live in the feed's KV
namespace under `vault/trystore/<path>`, with a signed manifest at
`vault/trystore/manifest.json`. Its `version` is a digest of the file list, so
a re-sealed vault with the same key still invalidates installed copies, and
`keyFingerprint` carries the bundle-key fingerprint
(`ed05f733621ace3b4665336ab7b11dee2adfb7c047cf7afc0300082095f26b50`).

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

Codemagic workflow `supportpatch_unsigned_ipa` archived commit `7c109ec` on
build `6b01125f799fbd143cf99e9b` (2026-11-21). The archive carries no
`CharacterVault` and no `Patches`; the verify step confirmed both are absent,
`__RESTRICT` is present, and document sharing is off. At archive time the
sealed vault in KV was version
`c2041d6c563e265cc7a59b5977e8d247267176e9f8e1025ab1e32af5b0c7e329` with
fingerprint `6d77…8759`; the rotation above replaced both. The build fetches
whatever version the feed serves, so no re-archive is needed for the new key.
Earlier builds fixed the `csops` lookup and the attested-key optional; the
temporary build-log relay is gone from both the Worker and the archive script.

## Manifest signing key

Public key, pinned in `PatchResourceBundle.swift`:

```
RrxJgZTY9C41WTQyO6+XNHmXp4jI7p6H2ppKwj2qC2o=
```

Rotating the private key requires a client build with the new public half.
Keep the old secret until installed builds have rolled forward.

## 2026-11-21 - hero fix and code pinning

- Blank hero: `CharacterSceneView.install` faded from opacity 0 with an implicit
  `SCNTransaction` animation. A fixed-pose stage keeps `isPlaying` false, so the
  animation never advanced and the mesh stayed transparent. The mesh is visible
  on the first frame now; the fade runs only while the display link exists.
- Key release: an App Attest failure of any kind, including a 401 from the
  challenge route, now falls through to the licence-bound release. Only
  `configuration` and `secureStorage` abort. `LicenseManager` keeps a cached key
  across transient failures and deletes it only on `.unauthorized`.
- Vault: the manifest `keyFingerprint` is compared with the cached bundle key
  before downloading; a mismatch aborts the sync instead of writing 16 blobs
  that cannot be unsealed. A corrupt sealed copy is evicted so the next sync
  re-downloads, and transport failures are retried twice.
- Binary pinning: `build_supportpatch_unsigned.sh` stores
  `TRYSTORE_CODE_SHA256` (SHA-256 over the `__TEXT` sections) in `Info.plist`;
  `Hardening` recomputes it and reports `.modifiedBinary`. Signing only touches
  `__LINKEDIT` and the Mach header, so the digest survives a re-sign.
  `tools/macho_code_digest.py` and `tools/verify_ipa_hardening.py` enforce it.
- Deployed: feed `7a431d40-044f-48c4-8b73-d9401975820d`, licence
  `e0f7dc1b-7c0e-4ac7-8ad5-a5e4a8d8df18`. `MANIFEST_SIGNING_KEY` was uploaded
  again from the local key so the pinned public half matches the signature.
- Feed: `/report` writes one KV key per project (the timestamped copy was a
  write amplifier) at 10/min, and `/character-vault/version` is rate limited.
- An IPA without `TRYSTORE_CODE_SHA256` now fails `verify_ipa_hardening.py`;
  IPA 9 predates the pin and is only useful as a pre-fix reference.

### Abuse controls (2026-11-21)

- Feed tokens now carry `mode` (`attest` or `licence`) and the release route
  records successful attestations in `feed_auth_cache` as `attest|<hash>` for
  30 days. A 10-minute token expiring no longer erases the proof.
- `REQUIRE_VAULT_ATTESTATION="1"` makes the vault manifest and blobs require
  that marker. Default is `"0"` so sideloaded installs keep working; flipping
  it locks the vault to attested devices only.
- Hourly per-licence budgets live in `feed_rate_limits`, keyed by
  `sha256("fetch|<bucket>|<licence>|<device>")`: 24 manifests, 64 vault blobs,
  160 patch blobs. A scraper that rotates IPs still hits the same subject and
  gets `429 fetch_quota_exceeded` with `retry-after`.
- Deployed feed `c9270dad-9dc1-4e19-8eb7-89d5fee05589`.
- Still open by design: the device identifier is a client-generated UUID, so a
  jailbroken device can copy it and look like the original. Only App Attest
  closes that; the strict flag is the switch for when every build can attest.

### Device-bound release (2026-11-21)

- `DeviceKey.swift` keeps a P-256 key in the Secure Enclave (software keychain
  fallback when the SEP is unavailable). The private half never leaves the
  phone; only the 65-byte public point is sent.
- `GET /api/patches/trystore/device-challenge` issues a 32-byte, 180-second,
  single-use challenge to a live licence. The client signs
  `TryStore device v1\n<challenge>\n<project>\n<device>` with
  `ecdsaSignatureMessageX962SHA256` and sends the raw 64-byte r||s signature
  on the licence-bound bundle-key request.
- `feed_device_keys` (migration `0005`) stores the public half on first use.
  A later release that presents a different key is rejected with
  `device_key_mismatch`; a reused challenge with `device_challenge_expired`;
  a bad signature with `device_signature_invalid`.
- `REQUIRE_DEVICE_SIGNATURE="1"` rejects a licence-bound release with no proof
  (`device_signature_required`). Default is `"0"` so the currently installed
  builds keep working; flip it after the new IPA is on the devices, because
  an unsigned client then gets no bundle key at all (patches included).
- Deployed feed `a8639d3b-d929-4be7-a4a0-757637f58867`. The local verifier
  generates a real P-256 key and covers success, replay, key substitution and
  strict mode.
