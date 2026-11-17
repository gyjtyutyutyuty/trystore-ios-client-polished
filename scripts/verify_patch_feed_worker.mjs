#!/usr/bin/env node
// Mock-only access-control smoke test for cloudflare/patch-feed-worker.js.
// Run after `npm ci --prefix cloudflare` with `node scripts/verify_patch_feed_worker.mjs`.
import { mkdtemp, copyFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve('cloudflare');
const scratch = await mkdtemp(path.join(root, '.patch-feed-test-'));
const copy = path.join(scratch, 'worker.mjs');
await copyFile(path.join(root, 'patch-feed-worker.js'), copy);

let validationCalls = 0;
let attestCalls = 0;
const internalToken = 'mock-internal-token'.padEnd(64, 'x');
const manifest = { schemaVersion: 1, project: 'trystore', patches: [] };
const blob = new Uint8Array([0x31, 0x30, 0x35]);
const env = {
  APP_ATTEST_INTERNAL_TOKEN: internalToken,
  APP_BUNDLE_KEY: Buffer.alloc(32, 0xab).toString('base64'),
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
      const url = new URL(request.url);
      const body = await request.json();
      if (url.pathname.startsWith('/api/v1/app-attest/')) {
        attestCalls += 1;
        if (request.headers.get('x-app-attest-internal-token') !== internalToken) {
          return new Response(JSON.stringify({ error: 'not_found' }), { status: 404 });
        }
        if (body.key !== 'ACTIVE-KEY-001' || body.projectId !== 'trystore') {
          return new Response(JSON.stringify({ error: 'license_required' }), { status: 401 });
        }
        if (url.pathname.endsWith('/challenge')) {
          return new Response(JSON.stringify({ challengeId: 'challenge-id', challenge: 'challenge-value', mode: 'attest' }), {
            status: 200, headers: { 'content-type': 'application/json' },
          });
        }
        if (url.pathname.endsWith('/register')) {
          return new Response(JSON.stringify({ valid: true }), { status: 200, headers: { 'content-type': 'application/json' } });
        }
        return body.assertion === 'VALID-ASSERTION'
          ? new Response(JSON.stringify({ valid: true }), { status: 200, headers: { 'content-type': 'application/json' } })
          : new Response(JSON.stringify({ error: 'assertion_rejected' }), { status: 403, headers: { 'content-type': 'application/json' } });
      }
      validationCalls += 1;
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
const request = (route, headers = {}, method = 'GET', body = undefined) => new Request(`https://feed.test${route}`, {
  method,
  headers: body === undefined ? headers : { 'content-type': 'application/json', ...headers },
  body: body === undefined ? undefined : JSON.stringify(body),
});
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

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders), env);
  check('legacy TryStore GET bundle-key route is denied', response.status === 405);
  check('denied GET does not reach the authorization service', attestCalls === 0);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', {}, 'POST', {
    challengeID: 'c', challenge: 'n', keyId: 'k', assertion: 'VALID-ASSERTION',
  }), env);
  check('bundle-key POST without license/device credentials is denied', response.status === 401);
  check('missing credentials do not call App Attest authorization', attestCalls === 0);

  response = await worker.fetch(request('/api/patches/trystore/app-attest/challenge', authorizedHeaders, 'POST', {}), env);
  const challenge = await response.json();
  check('challenge route proxies through the authenticated service binding', response.status === 200
    && challenge.mode === 'attest' && attestCalls === 1);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'BAD-ASSERTION',
  }), env);
  check('invalid server-side assertion response prevents bundle-key release', response.status === 403);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
  }), env);
  const keyResponse = await response.json();
  check('valid authorization returns the wrapped key without caching', response.status === 200
    && keyResponse.valid === true && keyResponse.key === env.APP_BUNDLE_KEY
    && response.headers.get('cache-control') === 'no-store');

  const missingSecretEnv = { ...env, APP_ATTEST_INTERNAL_TOKEN: '' };
  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
  }), missingSecretEnv);
  check('missing internal Worker secret fails closed', response.status === 503);

  response = await worker.fetch(request('/api/patches/apple-music/manifest.json'), env);
  check('other-project manifest behavior remains public', response.status === 200);
  response = await worker.fetch(request('/patches/apple-music/track.apple'), env);
  check('other-project blob behavior remains public and cacheable', response.status === 200
    && response.headers.get('cache-control')?.startsWith('public'));
} finally {
  await rm(scratch, { recursive: true, force: true });
}
if (failures) process.exitCode = 1;
