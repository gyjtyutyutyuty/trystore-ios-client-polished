# Telegram key generation with Cloudflare Workers

The repository already contains the application-facing license validation worker in `cloudflare/license-worker.js` and the Telegram key-generation flow in `cloudflare/telegram-worker.js`. The iOS app only needs the public validation URL; **Cloudflare and Telegram credentials must remain Worker secrets and must never be committed to GitHub or embedded in the iOS binary**.

## What is separated

| Component | Location | Role |
|---|---|---|
| iOS client | `ThreeOneOSFive/` | Validates a user-entered key through the configured license URL |
| License gateway | `cloudflare/license-worker.js` | Public gateway, validation, activation, heartbeat, and Telegram webhook routing |
| Telegram generator | `cloudflare/telegram-worker.js` | Generates keys for authorized reseller chats |
| Imported archive | `vendor/ProxyVN_header/` | Preserved separately and excluded from the Xcode target |

## Required setup

1. Create or select a Cloudflare Worker and D1 database. Use the schema/SQL statements referenced by the existing Worker source for the tables used by projects, resellers, assignments, keys, and Telegram state.
2. Configure the Worker bindings expected by the existing code. Review both Worker files before deployment because the current source is compact/minified and may contain deployment-specific upstream URLs.
3. Store credentials as encrypted Worker secrets, not in `wrangler.toml`, source files, `Info.plist`, GitHub Actions logs, or the iOS app:

```sh
wrangler secret put TELEGRAM_BOT_TOKEN
wrangler secret put TELEGRAM_WEBHOOK_SECRET
wrangler secret put ADMIN_TELEGRAM_ID
```

Use the exact secret names referenced in the Worker source if they differ in your deployment. A Cloudflare API token is only needed by the deployment operator/CI; it is not needed at runtime by the Worker and must not be sent to Telegram or the app.

4. Deploy the Worker from the repository, then set Telegram's webhook to the Worker endpoint. Use a secret path or Telegram's secret-token header and verify it in the Worker before accepting updates.
5. Set the iOS build setting `TRYSTORE_LICENSE_API_URL` to the deployed public endpoint ending in `/api/v1/keys/validate`, and set `TRYSTORE_PROJECT_ID` to the project slug used by the D1 data.
6. Test `/health`, key validation, reseller authorization, duration selection, expiry handling, and webhook replay protection before distributing the app.

## Secret handling

Do not paste Cloudflare API tokens or Telegram bot tokens into chat or commit them to this repository. If deployment is desired, provide credentials through an approved secret/connector flow or configure them locally with `wrangler secret put`. Rotate any token that has already been exposed.

## Safety boundary

The imported class-dump headers are intentionally not compiled or linked. This change does not add exploit, memory-patching, process-injection, or bypass behavior to the app; it only preserves the supplied archive separately and documents the legitimate license/key-management integration.
