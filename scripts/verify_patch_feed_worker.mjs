#!/usr/bin/env node
// Mock-only access-control smoke test for cloudflare/patch-feed-worker.js.
// Run after `npm ci --prefix cloudflare` with `node scripts/verify_patch_feed_worker.mjs`.
import { Buffer } from 'node:buffer';
import { mkdtemp, copyFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve('cloudflare');
const scratch = await mkdtemp(path.join(root, '.patch-feed-test-'));
const copy = path.join(scratch, 'worker.mjs');
await copyFile(path.join(root, 'patch-feed-worker.js'), copy);

let validationCalls = 0;
const manifest = { schemaVersion: 1, project: 'trystore', patches: [] };
const blob = new Uint8Array([0x31, 0x30, 0x35]);
const env = {
  PATCHES: {
    async get(key, type) {
      if (key === 'patches/trystore/manifest.json') return JSON.stringify(manifest);
      if (key === 'patches/trystore/HEAD.TRYSTORE' && type === 'arrayBuffer') return blob.buffer;
      if (key === 'patches/apple-music/track.apple' && type === 'arrayBuffer') return blob.buffer;
      if (key === 'patches/apple-music/manifest.json') {
        return JSON.stringify({ schemaVersion: 1, project: 'apple-music', patches: [] });
      }
      return null;
    },
  },
  RESELLER: {
    async fetch(request) {
      validationCalls += 1;
      const body = await request.json();
      if (body.key === 'ACTIVE-KEY-001' && body.projectId === 'trystore') {
        return new Response(JSON.stringify({
          valid: true,
          outcome: 'active',
          expiresAt: new Date(Date.now() + 60_000).toISOString(),
        }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      return new Response(JSON.stringify({ valid: false, outcome: 'revoked' }), {
        status: 403,
        headers: { 'content-type': 'application/json' },
      });
    },
  },
};

let failures = 0;
const check = (name, condition) => {
  console.log(`${condition ? 'ok  ' : 'FAIL'} ${name}`);
  if (!condition) failures += 1;
};
const deviceID = '550e8400-e29b-41d4-a716-446655440000';
const authorizedHeaders = {
  authorization: 'Bearer ACTIVE-KEY-001',
  'x-trystore-device-id': deviceID,
};
const request = (route, headers = {}) => new Request(`https://feed.test${route}`, { headers });

try {
  const worker = (await import(pathToFileURL(copy).href)).default;
  let response = await worker.fetch(request('/api/patches/trystore/manifest.json'), env);
  check('TryStore manifest denies requests without a license', response.status === 401);
  check('missing credentials do not call license validation', validationCalls === 0);

  response = await worker.fetch(request('/patches/trystore/HEAD.TRYSTORE', {
    authorization: 'Bearer REVOKED-KEY-001',
    'x-trystore-device-id': deviceID,
  }), env);
  check('inactive license is denied for package blobs', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/manifest.json', authorizedHeaders), env);
  check('active license receives the TryStore manifest', response.status === 200);
  check('license validation uses the TryStore project scope', validationCalls === 2);

  response = await worker.fetch(request('/patches/trystore/HEAD.TRYSTORE', authorizedHeaders), env);
  check('active license receives a TryStore package', response.status === 200);
  check('TryStore package responses are not cacheable', response.headers.get('cache-control') === 'no-store');
  check('TryStore response varies on authorization headers', /authorization/i.test(response.headers.get('vary') || ''));

  response = await worker.fetch(request('/api/patches/apple-music/manifest.json'), env);
  check('other-project manifest behavior remains public', response.status === 200);
  response = await worker.fetch(request('/patches/apple-music/track.apple'), env);
  check('other-project blob behavior remains public and cacheable', response.status === 200
    && response.headers.get('cache-control')?.startsWith('public'));

  // Bundle-key rotation: the served version lives in D1, so retiring a key does
  // not need a deploy, and a missing secret must fail closed instead of falling
  // back to the retired one.
  const keyEnv = {
    ...env,
    APP_BUNDLE_KEY: Buffer.alloc(32, 1).toString('base64'),
    APP_BUNDLE_KEY_V2: Buffer.alloc(32, 2).toString('base64'),
    DB: {
      prepare(sql) {
        return {
          bind() { return this; },
          async first() {
            if (sql.includes('feed_key_state')) return { key_version: '2' };
            return null;
          },
          async run() { return { success: true }; },
          async all() { return { results: [] }; },
        };
      },
    },
  };

  response = await worker.fetch(request('/api/patches/trystore/bundle-key'), keyEnv);
  check('bundle key still requires a license', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders), keyEnv);
  const keyBody = await response.json();
  check('bundle key reports the rotated version', keyBody.keyVersion === '2');
  check('bundle key serves the v2 secret', keyBody.key === keyEnv.APP_BUNDLE_KEY_V2);
  check('bundle key responses stay uncacheable', response.headers.get('cache-control') === 'no-store');

  response = await worker.fetch(
    request('/api/patches/trystore/bundle-key', authorizedHeaders),
    { ...keyEnv, APP_BUNDLE_KEY_V2: '' },
  );
  check('bundle key fails closed when the served version has no secret', response.status === 503);
} finally {
  await rm(scratch, { recursive: true, force: true });
}

if (failures) process.exitCode = 1;
