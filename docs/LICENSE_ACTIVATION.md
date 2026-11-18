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

The validate answer is not trusted on its own. Every active answer carries a
session:

```
session = base64url(claims) . base64url(ed25519(signature over claims))
```

Claims: `v`, `iss` (`trystore-license`), `aud` (`trystore-feed`), `kid`
(`trystore-ed25519-v1`), `project`, `keyId`, `keyHint`, `device`, `nonce`,
`iat`, `exp`. `exp` is capped at one hour even when the key itself is longer
lived.

The app pins the public half in `LicenseManager.SessionVerifier`, so a
repointed endpoint cannot mint a session and an `Info.plist` edit no longer
changes who is trusted. The signing key is `SESSION_SIGNING_KEY`, a base64
PKCS#8 DER Ed25519 private key:

```
wrangler secret put SESSION_SIGNING_KEY -c wrangler.license.toml
```

Rotating it requires a client build. That is deliberate.

## Device binding and limits

`/api/v1/keys/validate` registers the first devices against a key in
`license_devices` and refuses beyond `max_devices` with outcome
`device_limit`. Both key endpoints are rate limited per IP in D1
(`api_rate_limits`): 30/min for validate, 10/min for the bundle key.

Apply the schema before deploying the worker:

```
wrangler d1 execute jvztxnx-global-control --file cloudflare/migrations/0001_license_devices.sql
```

## Abuse detection

One key is meant for one customer. The worker counts distinct networks per key
per hour, storing a salted SHA-256 of the IP — never the address itself. Past
`MAX_DISTINCT_IPS` (default 8) the key is set to `frozen`, the call returns
`outcome: "frozen"`, and the owner chat gets a Telegram message. Unfreeze from
the bot.

```
wrangler d1 execute jvztxnx-global-control --remote \
  --file cloudflare/migrations/0002_license_signals.sql -c wrangler.license.toml
```

## Patch packages

Bundled `.TRYSTORE` packages carry their content key wrapped under
`APP_BUNDLE_KEY`, released by the patch feed only after a valid session. A
package with `publicContentKey` set is rejected by the app and by
`scripts/verify_legacy_patch_bundle.py`; the key must not travel inside the
IPA.

Feed requests use the signed session, never the licence key:

```
Authorization: Bearer <session>
X-TryStore-Device-ID: <device uuid>
```

`GET /api/patches/trystore/bundle-key` does not return the master key. It
returns `wrappedKey` and `salt`; the value is sealed with AES-256-GCM under
`HKDF-SHA256(session, salt, "trystore-bundle-v1")`, and the app derives the same
key before opening it. A captured response is useless without the session it
was minted for, and the session expires.

Feed routes are rate limited per IP in KV: 10/min for `bundle-key`, 30/min for
`report`, 120/min for `manifest` and blob downloads.
