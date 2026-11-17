# App Attest rollout and configuration

This implementation is deliberately fail-closed. Until both Workers have their shared internal secret, the license Worker has its verified App ID/environment, and the database migration is applied, TryStore activation cannot open the licensed app session or release the bundle key. No Worker deployment was performed as part of this source change.

## Apple Developer and iOS signing

1. In Certificates, Identifiers & Profiles, confirm the App ID for Bundle ID `cc.forcequit.worse-query`, with App Attest enabled. Do not assume that the Team ID is the App ID prefix; the exact identifier must be `APP_ATTEST_APP_ID` in `prefix.cc.forcequit.worse-query` form.
2. Ensure the provisioning profile includes `com.apple.developer.devicecheck.appattest-environment`. The Xcode target now requests `development` for Debug and `production` for Release. Signing must use matching profiles; production builds must use a production App Attest entitlement.
3. Test development builds only against a development-configured license Worker/database. Production Workers must set `APP_ATTEST_ENVIRONMENT=production`; production rejects keys registered with a development environment.
4. App Attest is device-supported only. A simulator or unsupported device will fail closed; there is no legacy key-download fallback.

## Cloudflare license Worker

Apply `cloudflare/migrations/0003_app_attest.sql` to the same D1 database already bound as `DB` to the Global Key Control Worker. The migration creates the registration and short-lived challenge tables; it does not create or replace the existing license tables.

Set these Worker variables on Global Key Control:

- `APP_ATTEST_APP_ID`: the exact, portal-confirmed App ID, including the correct prefix and `cc.forcequit.worse-query` bundle ID.
- `APP_ATTEST_ENVIRONMENT`: `production` for production, or `development` only for a separate development deployment.

Set `APP_ATTEST_INTERNAL_TOKEN` as a secret on both Global Key Control and `trystore-patch-feed`. Use the same cryptographically random value of at least 32 characters in both Workers. The patch-feed Worker sends this token over its service binding; it must never be included in the app, Info.plist, Git, or public CI artifacts. Continue to configure `APP_BUNDLE_KEY` on the patch-feed Worker as before.

The license Worker must be deployed as a bundled ES module that includes `cloudflare/app-attest.js` and the `@bradford-tech/supabase-integrity-attest` dependency. Build it from the repository root with `npm run build:license --prefix cloudflare`; this writes `cloudflare/dist/license-worker.js`. The patch-feed Worker must be redeployed with its existing KV namespace and reseller service binding preserved. Do not deploy until the target Worker’s D1/service bindings and secret names have been confirmed.

## Verification and rollout

Run the repository’s static and Worker smoke tests listed in `docs/CLIENT_SECURITY.md`. Then test on physical supported iOS hardware with a production-signed build. Confirm: a genuine app can register and request its bundle key; missing/expired licenses fail; an invalid attestation/assertion fails; a challenge cannot be replayed; the assertion counter must advance; production rejects development attestations; the old TryStore GET route returns HTTP 405; and the key is never returned when the internal service or configuration is missing.

App Attest raises the cost of unauthorized API access; it does not make an installable app impossible to inspect, patch, or instrument. Any data or keys delivered to an authorized app remain accessible to a device owner controlling that app.
