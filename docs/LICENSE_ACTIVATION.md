# TryStore license activation

The iOS app validates customer access keys through the Cloudflare Global Key
Control Worker:

- **Endpoint:** `https://jvztxnx-global-control.burgoajustin.workers.dev/api/v1/keys/validate`
- **Health check:** `https://jvztxnx-global-control.burgoajustin.workers.dev/health`
- **Project slug:** `trystore`

The app sends the key, project slug, app version, and a per-install device
identifier over HTTPS. A key is saved only after successful validation, in the
app's device-only iOS Keychain. The admin token and signing secret stay
server-side and never ship in the app.

## Signed session

An active answer carries a signed session:

```
session = base64url(claims) . base64url(ed25519(signature over claims))
```

Claims: `v`, `iss` (`trystore-license`), `aud` (`trystore-feed`), `kid`
(`trystore-ed25519-v1`), `project`, `keyId`, `keyHint`, `device`, `nonce`,
`iat`, `exp`. `exp` is capped at fifteen minutes.

The app pins the public half in `LicenseManager.SessionVerifier` and refuses an
active answer whose session does not verify, so a repointed endpoint cannot
unlock the app. The signing key is `SESSION_SIGNING_KEY`, a base64 PKCS#8 DER
Ed25519 private key:

```
npx wrangler secret put SESSION_SIGNING_KEY -c wrangler.license.toml
```

Rotating it requires a client build. The feed does not consume the session yet;
installed builds authenticate with their licence key.

## Device binding and limits

Rate limits are always on: 30/min validate and 10/min bundle key, per IP, in D1
`api_rate_limits`. Device binding is built but off by default so installed
builds keep activating. Enable it when you ship a build that can handle
`device_limit`:

```
npx wrangler secret put ENFORCE_DEVICE_BINDING -c wrangler.license.toml   # value 1
```

Apply the schema either way:

```
npx wrangler d1 execute jvztxnx-global-control --remote \
  --file cloudflare/migrations/0001_license_devices.sql -c wrangler.license.toml
```

## Abuse detection

Off by default. Set `MAX_DISTINCT_IPS` above 1 to count distinct networks per
key per hour — a salted SHA-256 of the IP, never the address — and freeze the
key past the limit, with a Telegram notice to the owner.

```
npx wrangler secret put MAX_DISTINCT_IPS -c wrangler.license.toml   # e.g. 8
npx wrangler d1 execute jvztxnx-global-control --remote \
  --file cloudflare/migrations/0002_license_signals.sql -c wrangler.license.toml
```

## Patch packages

Bundled `.TRYSTORE` resources carry their content key wrapped under
`APP_BUNDLE_KEY`. A bundled resource with `publicContentKey` set is rejected by
the app and by `scripts/verify_legacy_patch_bundle.py`; the key must not travel
inside the IPA. Feed packages use the same bundle wrapping, and the importer
also opens a `publicContentKey` package for older uploads.

Feed requests from installed builds:

```
Authorization: Bearer <licence key>
X-TryStore-Device-ID: <device uuid>
```

`GET /api/patches/trystore/bundle-key` validates that key through the licence
worker and returns `APP_BUNDLE_KEY` in the legacy `key` field. Feed routes are
rate limited per IP in D1 `feed_rate_limits`: 10/min bundle key, 30/min report,
120/min manifest and blob downloads.

A successful validation is cached in D1 `feed_auth_cache` for two minutes under
a hash of the key and device id. One patch is dozens of blob requests; without
the cache each one would revalidate and exhaust the licence worker's 30/min
per-IP budget midway through a download. If D1 itself fails, the feed continues
to the licence check instead of returning 500 — the auth gate is mandatory, the
counter is best effort.

KV is only used for package storage now. Its free tier allows 1,000 writes per
day, and the old per-request counter writes exhausted that, which returned 500
to every client. Repaired packages can be served from D1 `feed_blobs`; the
manifest route overlays their hash, size and URL so the client's digest check
still matches.

```sh
npx wrangler d1 execute jvztxnx-global-control --remote \
  --file cloudflare/migrations/0003_feed_state.sql -c wrangler.toml
```
TryStore downloads approved `.TRYSTORE` packages from the patch feed; the iOS target does not package the patch directory. The bundle key is not returned by the legacy GET route. The client first requests a short-lived challenge, registers a Secure Enclave-backed App Attest key when needed, then sends a fresh assertion bound to the POST bundle-key request. Only a valid license/device record and a valid App Attest assertion release the key. The app fails closed if App Attest is unsupported or the server cannot verify it. See `docs/APP_ATTEST_SETUP.md` for the required server and Apple Developer configuration.

## Device binding

The global-control Worker validates the submitted UUID-form `deviceId` against the D1 `license_devices` table and enforces each key's `max_devices` value. The App Attest key registration is bound to the same license/device row; challenges are one-use and assertion counters are persisted with compare-and-swap updates. Do not embed an admin, internal Worker, or signing secret in the iOS client.
