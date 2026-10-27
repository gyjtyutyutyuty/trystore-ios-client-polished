#!/usr/bin/env node
// Exercises cloudflare/asset-worker.js against a mocked upstream.
//
// The worker ships as an ES module but the repo has no package.json, so `.js` is treated
// as CommonJS by node. It is copied to a temporary `.mjs` to import it here — no change
// to the deployed file, no dependency added.
//
//   node scripts/verify_asset_worker.mjs

import { mkdtemp, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const source = path.resolve('cloudflare/asset-worker.js');
const scratch = await mkdtemp(path.join(tmpdir(), 'asset-worker-'));
const copy = path.join(scratch, 'worker.mjs');
await copyFile(source, copy);

const calls = [];
const submitResponse = {
  status: 'queued',
  request_id: 'abc12345',
  status_url: 'https://api.higgsfield.ai/requests/abc12345/status'
};
const statusResponse = {
  status: 'completed',
  request_id: 'abc12345',
  images: [{ url: 'https://cdn.example/x.png', content_type: 'image/png' }]
};
const cancelResponse = { status: 'canceled', request_id: 'abc12345' };
let nextSubmitResponse = submitResponse;
let nextStatusResponse = statusResponse;
let nextCancelResponse = cancelResponse;
globalThis.fetch = async (url, init = {}) => {
  calls.push({ url: String(url), init });
  const target = String(url);
  const headers = { 'content-type': 'application/json' };
  if (target.includes('/requests/') && target.endsWith('/status')) {
    return new Response(JSON.stringify(nextStatusResponse), { status: 200, headers });
  }
  if (target.includes('/requests/') && target.endsWith('/cancel')) {
    return new Response(JSON.stringify(nextCancelResponse), { status: 200, headers });
  }
  return new Response(JSON.stringify(nextSubmitResponse), { status: 200, headers });
};

const worker = (await import(pathToFileURL(copy).href)).default;
const env = {
  HIGGSFIELD_API_KEY_ID: 'kid',
  HIGGSFIELD_API_KEY_SECRET: 'ksec',
  ASSET_API_TOKEN: 'tok'
};
const auth = { authorization: 'Bearer tok', 'content-type': 'application/json' };
const req = (route, init) => new Request('https://worker.test' + route, init);

let failures = 0;
const check = (name, condition) => {
  console.log(`${condition ? 'ok  ' : 'FAIL'} ${name}`);
  if (!condition) failures += 1;
};
const post = (route, body, headers = auth) =>
  worker.fetch(req(route, { method: 'POST', headers, body: typeof body === 'string' ? body : JSON.stringify(body) }), env);

// Health is reachable without a token: it reports capability, never secrets.
let response = await worker.fetch(req('/health'), env);
let body = await response.json();
check('health is public and reports capability', response.status === 200 && body.credentials === true && body.gated === true);
check('health does not echo the credentials', !JSON.stringify(body).includes('ksec') && !JSON.stringify(body).includes('kid'));

// Auth is checked before routing, so an unauthenticated caller learns nothing about routes.
check('missing token is rejected', (await worker.fetch(req('/api/assets/image', { method: 'POST', body: '{}' }), env)).status === 401);
check('unknown routes are also gated', (await worker.fetch(req('/nope'), env)).status === 401);

response = await post('/api/assets/image', { prompt: 'dark metal panel' });
body = await response.json();
check('image submit returns the request id', body.request_id === 'abc12345');
check('image submit advertises its poll path', body.poll === '/api/assets/status?id=abc12345');
const upstream = calls.at(-1);
check('image hits the allowlisted model path', upstream.url === 'https://api.higgsfield.ai/higgsfield-ai/soul/v2/standard');
check('upstream uses the documented Key id:secret header', upstream.init.headers.authorization === 'Key kid:ksec');
check('image forwards only the prompt', JSON.stringify(JSON.parse(upstream.init.body)) === JSON.stringify({ prompt: 'dark metal panel' }));

response = await worker.fetch(req('/api/assets/status?id=abc12345', { headers: auth }), env);
body = await response.json();
check('status extracts media from images[]', body.media?.[0]?.url === 'https://cdn.example/x.png');
check('status reports completion', body.done === true && body.ready === true);

check('short prompts are refused', (await post('/api/assets/image', { prompt: 'x' })).status === 400);
check('prompt over 2000 chars is refused', (await post('/api/assets/image', { prompt: 'a'.repeat(2001) })).status === 400);

check('duration below 4 is refused', (await post('/api/assets/video', { prompt: 'valid prompt', duration: 3 })).status === 400);
check('duration above 15 is refused', (await post('/api/assets/video', { prompt: 'valid prompt', duration: 30 })).status === 400);
check('unknown resolution is refused', (await post('/api/assets/video', { prompt: 'valid prompt', resolution: '900p' })).status === 400);
check('unknown aspect ratio is refused', (await post('/api/assets/video', { prompt: 'valid prompt', aspect_ratio: '2:1' })).status === 400);
check('non-https webhook is refused', (await post('/api/assets/video', { prompt: 'valid prompt', webhook: 'http://example.com/hook' })).status === 400);

response = await post('/api/assets/video', { prompt: 'slow mint sheen', duration: 6, resolution: '1080p', aspect_ratio: '9:16' });
body = await response.json();
check('video uses the verified model path', body.model === 'bytedance/seedance-2.0/text-to-video');
const videoBody = JSON.parse(calls.at(-1).init.body);
check('video forwards duration, resolution and ratio', videoBody.duration === 6 && videoBody.resolution === '1080p' && videoBody.aspect_ratio === '9:16');
check('video defaults audio on', videoBody.generate_audio === true);
check('video omits the webhook when none was given', !calls.at(-1).url.includes('hf_webhook'));

await post('/api/assets/video', { prompt: 'sheen with hook', webhook: 'https://example.com/hook' });
check('https webhook is attached to the submit url', calls.at(-1).url.includes('hf_webhook=https%3A%2F%2Fexample.com%2Fhook'));

check('status refuses a missing token', (await worker.fetch(req('/api/assets/status?id=abc12345'), env)).status === 401);
check('status refuses a traversal attempt', (await worker.fetch(req('/api/assets/status?id=../../etc/passwd', { headers: auth }), env)).status === 400);
check('empty body is refused', (await post('/api/assets/image', '{}')).status === 400);
check('bad json is refused', (await post('/api/assets/image', 'not json')).status === 400);
check('missing credentials fail closed', (await worker.fetch(req('/api/assets/image', { method: 'POST', headers: auth, body: JSON.stringify({ prompt: 'valid prompt' }) }), { ASSET_API_TOKEN: 'tok' })).status === 503);

nextSubmitResponse = [];
check('malformed submit response is rejected', (await post('/api/assets/image', { prompt: 'valid prompt' })).status === 502);
nextSubmitResponse = submitResponse;

nextStatusResponse = [];
check('malformed status response is rejected', (await worker.fetch(req('/api/assets/status?id=abc12345', { headers: auth }), env)).status === 502);
nextStatusResponse = statusResponse;

nextCancelResponse = [];
check('malformed cancel response is rejected', (await post('/api/assets/cancel', { id: 'abc12345' })).status === 502);
nextCancelResponse = cancelResponse;

response = await worker.fetch(req('/nope', { headers: auth }), env);
check('authenticated unknown route is 404', response.status === 404);

response = await worker.fetch(req('/api/assets/image', { method: 'POST', headers: auth, body: JSON.stringify({ prompt: 'valid prompt' }) }), {
  ...env,
  ASSET_API_TOKEN: 'different'
});
check('a wrong token is rejected', response.status === 401);

await rm(scratch, { recursive: true, force: true });
console.log(failures === 0 ? 'ASSET WORKER: PASS' : `ASSET WORKER: FAIL (${failures})`);
process.exit(failures === 0 ? 0 : 1);
