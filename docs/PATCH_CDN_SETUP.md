# Patch feed — Cloudflare + Telegram

Update patch packages without building a new IPA. The app pulls a manifest at
launch, compares SHA-256 against what is installed, and imports only what
changed. Uploads happen from Telegram.

## Components

| Piece | Path |
| --- | --- |
| Worker (manifest + blobs + bot webhook) | `cloudflare/patch-feed-worker.js` |
| Wrangler config | `cloudflare/wrangler.toml` |
| Client sync | `ThreeOneOSFive/helpers/PatchFeedService.swift` |
| Launch hook | `ThreeOneOSFive/ContentView.swift` (`DashboardView.task`) |

Projects served from one worker: `trystore`, `apple-music`, `hyper-regedit`.

## R2 layout

```
patches/<project>/manifest.json
patches/<project>/<FILE>.TRYSTORE
```

Manifest shape:

```json
{
  "schemaVersion": 1,
  "project": "trystore",
  "updatedAt": "2026-10-27T18:20:00.000Z",
  "patches": [
    {
      "file": "HEAD.TRYSTORE",
      "name": "HEAD",
      "sha256": "…",
      "size": 48213,
      "version": "2026-10-27T18:20:00.000Z",
      "url": "/patches/trystore/HEAD.TRYSTORE"
    }
  ]
}
```

## Deploy

```bash
npm i -g wrangler
wrangler login
wrangler r2 bucket create trystore-patches

cd cloudflare
wrangler secret put TELEGRAM_BOT_TOKEN
wrangler secret put TELEGRAM_WEBHOOK_SECRET
wrangler secret put TELEGRAM_OWNER_ID

wrangler deploy
```

Point the bot at the worker:

```bash
curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://trystore-patch-feed.<subdomain>.workers.dev/api/telegram/webhook" \
  -d "secret_token=$TELEGRAM_WEBHOOK_SECRET" \
  -d "allowed_updates=[\"message\",\"callback_query\"]"
```

Public endpoints:

- `GET /api/patches/trystore/manifest.json`
- `GET /patches/trystore/HEAD.TRYSTORE`
- `GET /health`

## Bot commands

| Command | Effect |
| --- | --- |
| `/projects` | counts per project |
| `/upload trystore` | opens a 15-minute upload session |
| *(send document)* | publishes `.TRYSTORE` / `.3105` / `.tipa`, updates manifest |
| `/list trystore` | files + sizes |
| `/remove trystore HEAD.TRYSTORE` | deletes blob and manifest entry |

Same filename replaces the previous build, so re-uploading `HEAD.TRYSTORE`
bumps it in place. SHA-256 is computed server-side and sent back.

## Client behaviour

`PatchFeedService.syncIfDue` runs on the dashboard's `.task`, at most once per
30 minutes:

1. fetch `manifest.json` for `trystore`
2. skip entries whose local file digest matches
3. download to `tmp/PatchFeed/<file>`, verify SHA-256
4. hand the file to `PatchProjectStore.importPackage(at:)`

Failed verification deletes the download and keeps the installed copy. Network
failures are logged and ignored so the app still opens offline.

## Base URL

`PatchFeedService.baseURL` defaults to
`https://trystore-patch-feed.burgoajustin.workers.dev`. Change the constant if
the worker moves, and keep `PUBLIC_BASE_URL` in `wrangler.toml` in sync.
