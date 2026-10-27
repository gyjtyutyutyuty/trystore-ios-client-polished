#!/usr/bin/env node
// Generate a TryStore art asset through Higgsfield.
//
// Direct mode (default) talks to api.higgsfield.ai with your own key pair:
//   HIGGSFIELD_API_KEY_ID=... HIGGSFIELD_API_KEY_SECRET=... \
//     node scripts/asset_studio.mjs image "dark brushed metal backdrop, teal rim light"
//
// Worker mode keeps the key in Cloudflare instead (recommended for anything shared):
//   ASSET_WORKER_URL=https://trystore-assets.<subdomain>.workers.dev ASSET_API_TOKEN=... \
//     node scripts/asset_studio.mjs video "mint light sweeping across a black panel" --duration 5
//
// Output is downloaded to artifacts/assets/ because Higgsfield keeps files for roughly
// seven days. Images land as .png/.jpg, video as .mp4, audio as .mp3/.wav.

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const API = process.env.HIGGSFIELD_API_BASE || 'https://api.higgsfield.ai';
const IMAGE_MODEL = 'higgsfield-ai/soul/v2/standard';
const VIDEO_MODEL = 'bytedance/seedance-2.0/text-to-video';
const TERMINAL = new Set(['completed', 'failed', 'nsfw', 'canceled']);
const POLL_MS = 3000;
const TIMEOUT_MS = 10 * 60 * 1000;
const OUT_DIR = path.resolve('artifacts/assets');

function die(message, code = 1) {
  console.error(message);
  process.exit(code);
}

function parseArgs(argv) {
  const [mode, ...rest] = argv;
  const promptParts = [];
  const flags = {};
  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (token.startsWith('--')) {
      const key = token.slice(2);
      const next = rest[i + 1];
      if (next === undefined || next.startsWith('--')) {
        flags[key] = true;
      } else {
        flags[key] = next;
        i += 1;
      }
    } else {
      promptParts.push(token);
    }
  }
  return { mode, prompt: promptParts.join(' ').trim(), flags };
}

function workerMode() {
  return Boolean(process.env.ASSET_WORKER_URL && process.env.ASSET_API_TOKEN);
}

function directCredentials() {
  const id = process.env.HIGGSFIELD_API_KEY_ID;
  const secret = process.env.HIGGSFIELD_API_KEY_SECRET;
  if (!id || !secret) {
    die(
      'Missing HIGGSFIELD_API_KEY_ID / HIGGSFIELD_API_KEY_SECRET.\n' +
        'Create a key at open.higgsfield.ai (shown once), then export both parts.\n' +
        'Do not paste keys into chat or commit them.'
    );
  }
  return `Key ${id}:${secret}`;
}

async function call(method, url, { auth, body } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(auth ? { authorization: auth } : {}),
      ...(body ? { 'content-type': 'application/json' } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await response.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text.slice(0, 400) };
  }
  if (!response.ok) {
    die(`${method} ${url} failed (${response.status}): ${JSON.stringify(parsed).slice(0, 400)}`);
  }
  return parsed;
}

function collectMedia(body) {
  const media = [];
  const push = (value) => {
    if (value && typeof value.url === 'string') media.push({ url: value.url, contentType: value.content_type || null });
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

async function submit(mode, prompt, flags) {
  if (workerMode()) {
    const base = process.env.ASSET_WORKER_URL.replace(/\/$/, '');
    const body = { prompt };
    if (mode === 'video') {
      if (flags.duration) body.duration = Number(flags.duration);
      if (flags.resolution) body.resolution = String(flags.resolution);
      if (flags.ratio) body.aspect_ratio = String(flags.ratio);
      if (flags['no-audio']) body.generate_audio = false;
    }
    const submitted = await call('POST', `${base}/api/assets/${mode}`, {
      auth: `Bearer ${process.env.ASSET_API_TOKEN}`,
      body
    });
    return { submitted, pollUrl: `${base}/api/assets/status?id=${submitted.request_id}`, auth: `Bearer ${process.env.ASSET_API_TOKEN}` };
  }

  const auth = directCredentials();
  const model = mode === 'video' ? VIDEO_MODEL : IMAGE_MODEL;
  const body = { prompt };
  if (mode === 'video') {
    if (flags.duration) body.duration = Number(flags.duration);
    if (flags.resolution) body.resolution = String(flags.resolution);
    if (flags.ratio) body.aspect_ratio = String(flags.ratio);
    if (flags['no-audio']) body.generate_audio = false;
  }
  const submitted = await call('POST', `${API}/${model}`, { auth, body });
  return {
    submitted,
    pollUrl: submitted.status_url || `${API}/requests/${submitted.request_id}/status`,
    auth
  };
}

async function waitForResult(pollUrl, auth) {
  const started = Date.now();
  let last = '';
  for (;;) {
    const body = await call('GET', pollUrl, { auth });
    const status = String(body.status || 'unknown');
    if (status !== last) {
      console.log(`status: ${status}`);
      last = status;
    }
    if (TERMINAL.has(status)) {
      const media = collectMedia(body);
      if (status !== 'completed' || media.length === 0) {
        die(`generation ended as "${status}"${body.error ? `: ${body.error}` : ''}`, 2);
      }
      return media;
    }
    if (Date.now() - started > TIMEOUT_MS) die('timed out waiting for the render', 3);
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

function extensionFor(url, contentType) {
  if (contentType && contentType.includes('png')) return '.png';
  if (contentType && contentType.includes('jpeg')) return '.jpg';
  if (contentType && contentType.includes('mp4')) return '.mp4';
  if (contentType && contentType.includes('webm')) return '.webm';
  if (contentType && contentType.includes('mpeg')) return '.mp3';
  const match = /\.(png|jpe?g|webp|mp4|webm|mov|mp3|wav)(\?|$)/i.exec(url);
  return match ? `.${match[1].toLowerCase().replace('jpeg', 'jpg')}` : '.bin';
}

function slug(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48) || 'asset';
}

async function download(media, prompt) {
  await mkdir(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const written = [];
  for (const [index, item] of media.entries()) {
    const response = await fetch(item.url);
    if (!response.ok) die(`download failed (${response.status}) for ${item.url}`);
    const buffer = Buffer.from(await response.arrayBuffer());
    const suffix = media.length > 1 ? `-${index + 1}` : '';
    const file = path.join(OUT_DIR, `${stamp}-${slug(prompt)}${suffix}${extensionFor(item.url, item.contentType)}`);
    await writeFile(file, buffer);
    written.push(file);
  }
  return written;
}

const { mode, prompt, flags } = parseArgs(process.argv.slice(2));
if (!['image', 'video'].includes(mode)) {
  die('Usage: node scripts/asset_studio.mjs <image|video> "prompt" [--duration 5] [--resolution 720p] [--ratio 16:9] [--no-audio]');
}
if (prompt.length < 3) die('Give the model a real prompt.');

console.log(`mode: ${mode}${workerMode() ? ' (via worker)' : ''}`);
const { pollUrl, auth, submitted } = await submit(mode, prompt, flags);
console.log(`request: ${submitted.request_id || 'unknown'}`);
const media = await waitForResult(pollUrl, auth);
const files = await download(media, prompt);
console.log(`saved: ${files.join(', ')}`);
console.log('Higgsfield keeps outputs for about seven days; these local copies are the record.');
