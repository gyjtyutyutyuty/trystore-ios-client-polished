// Higgsfield asset worker.
//
// Credentials stay on the server: the client sends a prompt and a bearer token, never
// the key pair. Verified against docs.higgsfield.ai — submission is asynchronous and
// returns a request id, then you poll /requests/{id}/status until a terminal state.
//
// Deploy:
//   wrangler deploy cloudflare/asset-worker.js --name trystore-assets
//   wrangler secret put HIGGSFIELD_API_KEY_ID --name trystore-assets
//   wrangler secret put HIGGSFIELD_API_KEY_SECRET --name trystore-assets
//   wrangler secret put ASSET_API_TOKEN --name trystore-assets
//
// Requests fail closed while ASSET_API_TOKEN is unset, so a fresh deploy cannot spend
// the account balance by accident.

const API = 'https://api.higgsfield.ai';

// Only endpoints verified in the docs are reachable. A leaked worker URL therefore
// cannot pick a model on its own, and swapping models is one line plus its documented
// path — no client change.
const MODELS = {
  image: 'higgsfield-ai/soul/v2/standard',
  video: 'bytedance/seedance-2.0/text-to-video'
};

const RESOLUTIONS = new Set(['480p', '720p', '1080p', '4k']);
const ASPECT_RATIOS = new Set(['16:9', '4:3', '1:1', '3:4', '9:16', '21:9']);
const TERMINAL = new Set(['completed', 'failed', 'nsfw', 'canceled']);

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-allow-methods': 'GET, POST, OPTIONS'
    }
  });

const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

const upstreamAuth = (env) => `Key ${env.HIGGSFIELD_API_KEY_ID}:${env.HIGGSFIELD_API_KEY_SECRET}`;

function authorised(request, env) {
  const expected = String(env.ASSET_API_TOKEN || '');
  if (!expected) return false;
  const header = request.headers.get('authorization') || '';
  // The token stays in the header. A ?token= form ends up in access logs,
  // browser history and Referer headers, so it is no longer accepted.
  if (!header.toLowerCase().startsWith('bearer ')) return false;
  const supplied = header.slice(7).trim();
  if (supplied.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i += 1) {
    diff |= expected.charCodeAt(i) ^ supplied.charCodeAt(i);
  }
  return diff === 0;
}

// Polling puts media at the top level; webhooks nest the same shapes under `payload`.
// Both are read here so one parser covers either delivery.
function collectMedia(body) {
  const media = [];
  const push = (value) => {
    if (value && typeof value.url === 'string') {
      media.push({ url: value.url, contentType: value.content_type || null });
    }
  };
  if (!body || typeof body !== 'object') return media;
  if (Array.isArray(body.images)) body.images.forEach(push);
  if (Array.isArray(body.audios)) body.audios.forEach(push);
  push(body.video);
  push(body.audio);
  if (body.payload && typeof body.payload === 'object') {
    if (Array.isArray(body.payload.images)) body.payload.images.forEach(push);
    if (Array.isArray(body.payload.audios)) body.payload.audios.forEach(push);
    push(body.payload.video);
    push(body.payload.audio);
  }
  return media;
}

function readPrompt(value) {
  const prompt = String(value || '').trim();
  if (prompt.length < 3 || prompt.length > 2000) return null;
  return prompt;
}

function imageSpec(body) {
  const prompt = readPrompt(body && body.prompt);
  if (!prompt) return { error: 'invalid_prompt' };
  return { path: MODELS.image, payload: { prompt } };
}

function videoSpec(body) {
  const prompt = readPrompt(body && body.prompt);
  if (!prompt) return { error: 'invalid_prompt' };
  const duration = body?.duration === undefined ? 5 : Number(body.duration);
  if (!Number.isInteger(duration) || duration < 4 || duration > 15) return { error: 'invalid_duration' };
  const resolution = body?.resolution === undefined ? '720p' : String(body.resolution);
  if (!RESOLUTIONS.has(resolution)) return { error: 'invalid_resolution' };
  const aspect = body?.aspect_ratio === undefined ? '16:9' : String(body.aspect_ratio);
  if (!ASPECT_RATIOS.has(aspect)) return { error: 'invalid_aspect_ratio' };
  return {
    path: MODELS.video,
    payload: {
      prompt,
      duration,
      resolution,
      aspect_ratio: aspect,
      generate_audio: body?.generate_audio !== false
    }
  };
}

async function submit(env, spec, webhook) {
  const target = new URL(`${API}/${spec.path}`);
  if (webhook) target.searchParams.set('hf_webhook', webhook);
  const response = await fetch(target.toString(), {
    method: 'POST',
    headers: { authorization: upstreamAuth(env), 'content-type': 'application/json' },
    body: JSON.stringify(spec.payload)
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = { raw: text.slice(0, 400) };
  }
  if (!response.ok) return json({ error: 'upstream_error', upstreamStatus: response.status, detail: body }, 502);
  if (!isRecord(body) || typeof body.request_id !== 'string' || body.request_id.length === 0) {
    return json({ error: 'invalid_upstream_response' }, 502);
  }
  return json({ ...body, model: spec.path, poll: `/api/assets/status?id=${encodeURIComponent(body.request_id)}` });
}

async function poll(env, id) {
  const response = await fetch(`${API}/requests/${id}/status`, {
    headers: { authorization: upstreamAuth(env) }
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = { raw: text.slice(0, 400) };
  }
  if (!response.ok) return json({ error: 'upstream_error', upstreamStatus: response.status, detail: body }, 502);
  if (!isRecord(body)) return json({ error: 'invalid_upstream_response' }, 502);
  const media = collectMedia(body);
  return json({
    ...body,
    media,
    done: TERMINAL.has(String(body.status || '')),
    ready: body.status === 'completed' && media.length > 0
  });
}

async function cancel(env, id) {
  const response = await fetch(`${API}/requests/${id}/cancel`, {
    method: 'POST',
    headers: { authorization: upstreamAuth(env) }
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = { raw: text.slice(0, 400) };
  }
  if (!response.ok) return json({ error: 'upstream_error', upstreamStatus: response.status, detail: body }, 502);
  if (!isRecord(body)) return json({ error: 'invalid_upstream_response' }, 502);
  return json(body);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') return json({ ok: true });
    if (url.pathname === '/health') {
      return json({
        status: 'ok',
        service: 'trystore-assets',
        models: MODELS,
        credentials: Boolean(env.HIGGSFIELD_API_KEY_ID && env.HIGGSFIELD_API_KEY_SECRET),
        gated: Boolean(env.ASSET_API_TOKEN)
      });
    }
    if (request.method !== 'POST' && request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405);

    if (!env.HIGGSFIELD_API_KEY_ID || !env.HIGGSFIELD_API_KEY_SECRET) {
      return json({ error: 'credentials_not_configured' }, 503);
    }
    if (!authorised(request, env)) return json({ error: 'unauthorized' }, 401);

    try {
      if (url.pathname === '/api/assets/image' && request.method === 'POST') {
        const spec = imageSpec(await request.json().catch(() => ({})));
        if (spec.error) return json(spec, 400);
        return submit(env, spec, null);
      }
      if (url.pathname === '/api/assets/video' && request.method === 'POST') {
        const body = await request.json().catch(() => ({}));
        const spec = videoSpec(body);
        if (spec.error) return json(spec, 400);
        const webhook = String(body?.webhook || '');
        if (webhook && (!webhook.startsWith('https://') || webhook.length > 300)) {
          return json({ error: 'invalid_webhook' }, 400);
        }
        return submit(env, spec, webhook || null);
      }
      if (url.pathname === '/api/assets/status' && request.method === 'GET') {
        const id = String(url.searchParams.get('id') || '');
        if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) return json({ error: 'invalid_request_id' }, 400);
        return poll(env, id);
      }
      if (url.pathname === '/api/assets/cancel' && request.method === 'POST') {
        const body = await request.json().catch(() => ({}));
        const id = String(body?.id || '');
        if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) return json({ error: 'invalid_request_id' }, 400);
        return cancel(env, id);
      }
      return json({ error: 'not_found' }, 404);
    } catch {
      return json({ error: 'server_error' }, 500);
    }
  }
};
