# Generated assets — Higgsfield pipeline

Higgsfield's API is a separate product from the higgsfield.ai website: pay-as-you-go in
US dollars, one key pair, asynchronous generation. This repository uses it for art that
ships with the app or supports a release — backdrop textures, App Store screenshots,
short promo clips — never for anything the app needs at runtime to function.

Contract verified against `docs.higgsfield.ai` (see the reference links at the end).

## 1. The contract

| | |
| --- | --- |
| Base URL | `https://api.higgsfield.ai` |
| Auth | `Authorization: Key <API_KEY_ID>:<API_KEY_SECRET>` — one header, two parts |
| Submit | `POST /<model path>` with a JSON body |
| Response | `{ status, request_id, status_url, cancel_url }`, status starts `queued` |
| Poll | `GET /requests/{request_id}/status` (or the returned `status_url`) |
| Terminal states | `completed`, `failed`, `nsfw`, `canceled` |
| Non-terminal | `queued`, `in_progress` |
| Media on poll | `images[i].url`, `video.url`, `audio.url`, `audios[i].url` |
| Media on webhook | the same shapes, nested under `payload` |
| Webhook | `?hf_webhook=https://…` on submit; signed with Standard Webhooks headers |
| Retention | outputs stay available for roughly seven days — download them |

## 2. Endpoints this repo allows

`cloudflare/asset-worker.js` holds an allowlist, so a leaked Worker URL cannot choose a
model or a price on its own:

| Kind | Path | Body |
| --- | --- | --- |
| image | `higgsfield-ai/soul/v2/standard` | `prompt` |
| video | `bytedance/seedance-2.0/text-to-video` | `prompt`, `duration` 4–15 (default 5), `resolution` 480p/720p/1080p/4k, `aspect_ratio` 16:9/4:3/1:1/3:4/9:16/21:9, `generate_audio` bool |

Adding a model is one line in `MODELS` plus its documented path — no client change.

## 3. Setup

1. Create an API key at `open.higgsfield.ai` (Console). It is shown once, as an id and a
   secret; store both, and top up the balance before the first generation.
2. Put the credentials in the Worker, never in the app, the repo or a chat message:

   ```bash
   npx wrangler deploy cloudflare/asset-worker.js --name trystore-assets
   npx wrangler secret put HIGGSFIELD_API_KEY_ID
   npx wrangler secret put HIGGSFIELD_API_KEY_SECRET
   npx wrangler secret put ASSET_API_TOKEN      # any long random string you generate
   ```

3. `GET /health` reports `credentials` and `gated` without echoing anything secret.
   Requests fail closed while `ASSET_API_TOKEN` is unset, so a fresh deploy cannot spend
   the balance by accident.
4. Generate:

   ```bash
   # through the Worker (recommended: the key never leaves Cloudflare)
   ASSET_WORKER_URL=https://trystore-assets.<subdomain>.workers.dev \
   ASSET_API_TOKEN=<the token you set> \
     node scripts/asset_studio.mjs image "brushed black panel, mint rim light, top-down"

   # or directly against the API for a one-off, key pair in the environment only
   HIGGSFIELD_API_KEY_ID=… HIGGSFIELD_API_KEY_SECRET=… \
     node scripts/asset_studio.mjs video "slow mint sheen crossing a dark glass card" --duration 5
   ```

   Files land in `artifacts/assets/`, named by timestamp and prompt slug.

## 4. What it costs

Published starting rates (check the pricing page before a batch — they move):

| Model | Rate |
| --- | --- |
| Soul 2 (image) | about $0.0032 per image |
| Soul Cinema (image) | about $0.0032 per image |
| Seedance 2.0 (video) | listed at about $0.93 per second — expensive, keep clips short |
| Kling 2.6 (video) | about $0.07 per second |
| DoP (video) | about $0.125 per generation |

Failed requests are not charged, and spending stops at a zero balance. Image work is
cheap enough to iterate; video is not, so storyboard with stills first.

## 5. Security posture

- Credentials live only in Worker secrets. The iOS binary cannot keep a secret: anything
  embedded is extractable, which is why the app has no Higgsfield key at all.
- The Worker requires a bearer token and compares it in constant time; it fails closed.
- Prompts are capped at 2000 characters, request ids are validated against
  `^[A-Za-z0-9_-]{8,64}$`, and responses are `no-store`.
- Webhooks must be `https` and are length-capped before being forwarded upstream.
- Before exposing this publicly, put it behind the licence check the licence worker
  already performs — otherwise anyone with the URL can spend the balance.

## 6. Deliberately not done

There is no Asset Lab screen and no in-app generation. A new Swift file is only compiled
if it is added to the project's build phases (`project.pbxproj` uses explicit file
references, not a synchronised folder), so shipping a client that nothing calls would
add dead code. The pipeline above produces files; wiring it into the interface is a
separate change with its own screen, cost guard and licence gate.

## Reference

- API overview — <https://docs.higgsfield.ai/docs>
- Request lifecycle and status enum — <https://docs.higgsfield.ai/docs/concepts/requests>
- Request status schema — <https://docs.higgsfield.ai/docs/api-reference/requests/get-request-status>
- Webhooks — <https://docs.higgsfield.ai/docs/how-to/webhooks>
- Seedance 2.0 text-to-video schema — <https://docs.higgsfield.ai/docs/models/seedance-2/text-to-video>
- Rate limits and concurrency — <https://docs.higgsfield.ai/docs/concepts/rate-limits>
