# Patch feed — Cloudflare + Telegram

Update patch packages without building a new IPA. The app pulls a manifest at
launch, compares SHA-256 against what is installed, and imports only what
changed. Uploads happen from Telegram, either with the button UI or commands.

## Components

| Piece | Path |
| --- | --- |
| Worker (manifest + blobs + bot webhook) | `cloudflare/patch-feed-worker.js` |
| Wrangler config | `cloudflare/wrangler.toml` |
| Client sync | `ThreeOneOSFive/helpers/PatchFeedService.swift` |
| Launch hook | `ThreeOneOSFive/ContentView.swift` |

Projects served from one worker: `trystore`, `apple-music`, `hyper-regedit`.

## Storage layout

KV namespace `PATCHES` (`a7f21b4f1ae54d0bbbf2773bd3f850fd`), keyed by project:

```
patches/<project>/manifest.json
patches/<project>/<FILE>.TRYSTORE
patches/<project>/<FILE>.APPLE
```

KV is used because R2 is not enabled on the account. Values are capped at
25 MB; the bot rejects uploads above 24 MB.

Manifest shape:

```json
{
  "schemaVersion": 1,
  "project": "trystore",
  "updatedAt": "2026-10-28T02:00:00.000Z",
  "patches": [
    {
      "file": "HEAD.TRYSTORE",
      "name": "HEAD",
      "sha256": "…",
      "size": 48138,
      "version": "2026-10-28T02:00:00.000Z",
      "url": "/patches/trystore/HEAD.TRYSTORE?v=<sha256>"
    }
  ]
}
```

Blob URLs carry the digest as `?v=`. Replacements reuse the filename, so the
query is what keeps the old CDN/HTTP cache from serving the previous bytes.
The manifest route is `no-store`; blobs are immutable per digest.

Legacy schema-9 visual packages (`HOLOGRAMA EXCLUSIVO 4/5`) stay bundled in
the IPA and are not published to the feed. The current importer only accepts
schema 1 and 2; putting schema 9 in the manifest makes the whole sync abort
with `patch.error.unsupported_version`.

## Deploy

```bash
cd cloudflare
npm install
npx wrangler login
npx wrangler secret put TELEGRAM_BOT_TOKEN
npx wrangler secret put TELEGRAM_WEBHOOK_SECRET
npx wrangler secret put TELEGRAM_OWNER_ID
npx wrangler deploy
```

`wrangler.toml` binds the `jvztxnx-global-control` worker as `RESELLER`. The
patch worker owns the Telegram webhook, handles `pm:` callbacks, and forwards
every other update through that service binding so the original licence and
reseller panel keeps working unchanged.

Point the bot at the patch worker:

```bash
curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://trystore-patch-feed.burgoajustin.workers.dev/api/telegram/webhook" \
  -d "secret_token=$TELEGRAM_WEBHOOK_SECRET" \
  -d 'allowed_updates=["message","callback_query"]'
```

The secret must match the one on `jvztxnx-global-control`; the forwarded update
carries the same header.

Public endpoints:

- `GET /api/patches/<project>/manifest.json`
- `GET /patches/<project>/<file>`
- `POST /api/patches/<project>/report` (small sync report, 32 KB cap)
- `GET /health`

## Bot UI

`/patches` (or `/projects`) opens the button panel:

- project buttons with live patch counts
- patch buttons with size
- patch detail: Replace, Delete, Download
- Add file as a first-class button, not a hidden command

Replace flow:

1. tap a patch, tap `🔁 Replace`
2. send the new package as a document
3. the worker rewrites its internal project id/name to the target package and
   stores it under the same filename
4. the manifest is updated; the app replaces the existing package on its next
   sync

This is what makes an upload a true in-place replacement instead of a second
patch alongside the old one. The old target bytes are backed up to KV under
`backup/<project>/<timestamp>-<file>` for 30 days.

Legacy commands still work:

| Command | Effect |
| --- | --- |
| `/patches`, `/projects` | button panel |
| `/upload <project>` | opens a 15-minute upload session |
| `/list <project>` | project panel |
| `/remove <project> <file>` | project panel |
| `/cancel` | clears the session |

## Client behaviour

`PatchFeedService.syncOnLaunch` runs once per process, then `syncIfDue` runs at
most once per minute and whenever the app returns to the foreground:

1. fetch `manifest.json` for `trystore`
2. skip entries whose local file digest matches
3. download to `tmp/PatchFeed/<file>`, verify SHA-256
4. reject schema versions outside 1-2 and password-protected packages before
   import, so one legacy visual cannot abort the whole pass
5. import entries one at a time, waiting for each write to land before starting
   the next one

The patch screen prints the last result under the module bus, for example
`FEED 6 | 4 updated | 2 current | 0 skipped | 0 failed | 20:40`. The same
counts are posted to `/api/patches/trystore/report` and kept in KV under
`reports/trystore/latest.json` for seven days.

The worker removes known-incompatible entries from the manifest at read time.
`publishPatch` records `schemaVersion` and `isPasswordProtected` on every new
entry, and the Telegram upload reply warns when a file is stored but not
published.

Bundled patches are installed before the feed runs. A bundled package is never
written over an existing package with the same package ID, so a remote
replacement survives the next launch even before the manifest check. Raw
`TryStore` packages use a source-revision key so a rebuilt IPA can still
refresh the bundled Balas Magicas payload once.

Current TryStore slot mapping (the dashboard renders these six files):

| Slot file | Source project |
| --- | --- |
| `HEAD.TRYSTORE` | HEAD |
| `NECK.TRYSTORE` | CUELLO3105 |
| `HS SLA PECHO.TRYSTORE` | Pecho3105 |
| `HSPESSCOSO.TRYSTORE` | Cuello y Drag |
| `TryStore.TRYSTORE` | Balas Magicas |
| `EXCLUSIVO AZUL.TRYSTORE` | Holograma Armas |

The source packages stay in KV. Only the repacked slot bytes go into the
manifest; the extra project names are not listed as separate dashboard tiles.

Failed verification deletes the download and keeps the installed copy. Network
failures are logged and ignored so the app still opens offline.

Replacing an active slot updates the package bytes, but iOS keeps the applied
transaction receipt until the slot is toggled. Turn the slot off and back on
once to apply the new content; the package ID stays the same on purpose, so the
app overwrites instead of creating a duplicate.

## Base URL

`PatchFeedService.baseURL` defaults to
`https://trystore-patch-feed.burgoajustin.workers.dev`. Change the constant if
the worker moves, and keep `PUBLIC_BASE_URL` in `wrangler.toml` in sync.
