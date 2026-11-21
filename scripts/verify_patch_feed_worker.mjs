#!/usr/bin/env node
// Mock-only access-control smoke test for cloudflare/patch-feed-worker.js.
// Run after `npm ci --prefix cloudflare` with `node scripts/verify_patch_feed_worker.mjs`.
import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
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
      if (key === 'patches/apple-music/manifest.json') {
        return JSON.stringify({ schemaVersion: 1, project: 'apple-music', patches: [] });
      }
      if (key === 'patches/apple-music/HS SLA PECHO.APPLE' && type === 'arrayBuffer') return blob.buffer;
      if (key === 'patches/hyper-regedit/track.3105' && type === 'arrayBuffer') return blob.buffer;
      if (key === 'vault/trystore/manifest.json') {
        return JSON.stringify({
          schemaVersion: 1,
          project: 'trystore',
          version: 'v1',
          keyFingerprint: 'b'.repeat(64),
          files: [{ path: 'rouk/rouk.mtl.tsc', sha256: 'a'.repeat(64), size: 6 }],
        });
      }
      if (key === 'vault/trystore/rouk/rouk.mtl.tsc' && type === 'arrayBuffer') {
        return new Uint8Array([0x54, 0x53, 0x43, 0x32, 1, 2]).buffer;
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
      if (body.key === 'APPLE-KEY-001' && body.projectId === 'apple-music') {
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

const manifestSigning = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
env.MANIFEST_SIGNING_KEY = Buffer.from(
  await crypto.subtle.exportKey('pkcs8', manifestSigning.privateKey),
).toString('base64');
env.FEED_TOKEN_SECRET = 'feed-token-secret-'.padEnd(48, 'x');

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
const appleHeaders = {
  authorization: 'Bearer APPLE-KEY-001',
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

  const expectedFingerprint = createHash('sha256').update(Buffer.alloc(32, 0xab)).digest('hex');
  response = await worker.fetch(request('/api/patches/trystore/bundle-key/fingerprint'), env);
  const fingerprintBody = await response.json();
  check('key fingerprint route publishes the served key hash', response.status === 200
    && fingerprintBody.version === '1'
    && fingerprintBody.fingerprint === expectedFingerprint);
  response = await worker.fetch(request('/api/patches/trystore/bundle-key/fingerprint'), {
    ...env,
    APP_BUNDLE_KEY: '',
  });
  check('fingerprint route fails closed without a key', response.status === 503);

  response = await worker.fetch(request('/api/patches/trystore/character-vault/version'), env);
  const vaultVersion = await response.json();
  check('vault version route publishes the KV manifest version', response.status === 200
    && vaultVersion.version === 'v1' && vaultVersion.files === 1
    && vaultVersion.keyFingerprint === 'b'.repeat(64));

  response = await worker.fetch(request('/api/patches/trystore/character-vault/manifest.json'), env);
  check('vault manifest requires a licence', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/character-vault/manifest.json', authorizedHeaders), env);
  const vaultSignature = response.headers.get('x-trystore-signature') || '';
  const vaultBytes = new Uint8Array(await response.arrayBuffer());
  check('licensed vault manifest is signed', response.status === 200 && vaultSignature.length > 40);
  check('vault manifest signature verifies against the pinned key', await crypto.subtle.verify(
    { name: 'Ed25519' },
    manifestSigning.publicKey,
    Uint8Array.from(Buffer.from(vaultSignature.replaceAll('-', '+').replaceAll('_', '/'), 'base64')),
    vaultBytes,
  ));
  const vaultManifest = JSON.parse(Buffer.from(vaultBytes).toString('utf8'));
  check('vault manifest lists the sealed blob', vaultManifest.version === 'v1'
    && vaultManifest.files[0].path === 'rouk/rouk.mtl.tsc');

  response = await worker.fetch(request('/api/patches/trystore/character-vault/rouk/rouk.mtl.tsc'), env);
  check('vault blob requires a licence', response.status === 401);
  response = await worker.fetch(request('/api/patches/trystore/character-vault/rouk/rouk.mtl.tsc', authorizedHeaders), env);
  check('licensed vault blob is served uncached', response.status === 200
    && (await response.arrayBuffer()).byteLength === 6
    && response.headers.get('cache-control') === 'no-store');
  response = await worker.fetch(request('/api/patches/trystore/character-vault/rouk/..%2Fmanifest.json', authorizedHeaders), env);
  check('vault path traversal is rejected', response.status === 404);

  response = await worker.fetch(request('/patches/trystore/HEAD.TRYSTORE', {
    authorization: 'Bearer REVOKED-KEY-001',
    'x-trystore-device-id': deviceID,
  }), env);
  check('inactive license is denied for package blobs', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/manifest.json', authorizedHeaders), env);
  check('active license receives the TryStore manifest', response.status === 200);
  check('manifest carries a detached signature', (response.headers.get('x-trystore-signature') || '').length > 40);
  const manifestSignature = response.headers.get('x-trystore-signature') || '';
  const manifestBytes = new Uint8Array(await response.arrayBuffer());
  const manifestSignatureBytes = Uint8Array.from(Buffer.from(
    manifestSignature.replaceAll('-', '+').replaceAll('_', '/'),
    'base64',
  ));
  check('manifest signature verifies against the pinned public key', await crypto.subtle.verify(
    { name: 'Ed25519' },
    manifestSigning.publicKey,
    manifestSignatureBytes,
    manifestBytes,
  ));
  check('license validation uses the TryStore project scope', validationCalls === 4);

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
  check('bundle key carries a short-lived feed token', typeof keyResponse.feedToken === 'string'
    && keyResponse.feedToken.includes('.') && typeof keyResponse.expiresAt === 'string');
  const tokenClaims = (value) => JSON.parse(Buffer.from(
    value.split('.')[0].replaceAll('-', '+').replaceAll('_', '/'),
    'base64',
  ).toString('utf8'));
  check('attested feed token records its mode', tokenClaims(keyResponse.feedToken).mode === 'attest');

  const attestCallsBeforeLicenceRelease = attestCalls;
  response = await worker.fetch(request('/api/patches/trystore/bundle-key', {
    ...authorizedHeaders,
    'x-trystore-attestation-mode': 'licence',
  }, 'POST', {}), env);
  const licenceKeyResponse = await response.json();
  check('licence-bound release returns the key without App Attest', response.status === 200
    && licenceKeyResponse.valid === true && licenceKeyResponse.key === env.APP_BUNDLE_KEY);
  check('licence-bound release does not call App Attest', attestCalls === attestCallsBeforeLicenceRelease);
  check('licence-bound release still mints a feed token', typeof licenceKeyResponse.feedToken === 'string');
  check('licence-bound feed token records its mode',
    tokenClaims(licenceKeyResponse.feedToken).mode === 'licence');

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', {
    'x-trystore-attestation-mode': 'licence',
  }, 'POST', {}), env);
  check('licence-bound release denies a missing licence', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', {
    authorization: 'Bearer REVOKED-KEY-001',
    'x-trystore-device-id': deviceID,
    'x-trystore-attestation-mode': 'licence',
  }, 'POST', {}), env);
  check('licence-bound release denies a revoked licence', response.status === 401);

  const validationsBeforeToken = validationCalls;
  response = await worker.fetch(request('/api/patches/trystore/manifest.json', {
    'x-trystore-device-id': deviceID,
    'x-trystore-feed-token': keyResponse.feedToken,
  }), env);
  check('feed token authorizes the manifest without another licence lookup', response.status === 200
    && validationCalls === validationsBeforeToken);

  response = await worker.fetch(request('/api/patches/trystore/manifest.json', {
    'x-trystore-device-id': '11111111-2222-4333-8444-555555555555',
    'x-trystore-feed-token': keyResponse.feedToken,
  }), env);
  check('feed token is bound to its device', response.status === 401);

  const unsignedEnv = { ...env, MANIFEST_SIGNING_KEY: '' };
  response = await worker.fetch(request('/api/patches/trystore/manifest.json', {
    'x-trystore-device-id': deviceID,
    'x-trystore-feed-token': keyResponse.feedToken,
  }), unsignedEnv);
  check('missing signing key refuses to serve a manifest', response.status === 503);

  const missingSecretEnv = { ...env, APP_ATTEST_INTERNAL_TOKEN: '' };
  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
  }), missingSecretEnv);
  check('missing internal Worker secret fails closed', response.status === 503);

  response = await worker.fetch(request('/api/patches/apple-music/manifest.json'), env);
  check('Apple Music manifest denies requests without a license', response.status === 401);
  check('Apple Music denial does not call license validation', validationCalls === 7);

  response = await worker.fetch(request('/api/patches/apple-music/manifest.json', appleHeaders), env);
  check('active Apple Music license receives its manifest', response.status === 200);
  check('Apple Music license validation uses its own project scope', validationCalls === 8);

  response = await worker.fetch(request('/patches/apple-music/HS%20SLA%20PECHO.APPLE', appleHeaders), env);
  check('active Apple Music license receives its package', response.status === 200);
  check('Apple Music package responses are not cacheable', response.headers.get('cache-control') === 'no-store');
  check('Apple Music response varies on authorization headers', /authorization/i.test(response.headers.get('vary') || ''));

  response = await worker.fetch(request('/api/patches/hyper-regedit/manifest.json'), env);
  check('unlicensed project manifest remains public', response.status === 200);
  response = await worker.fetch(request('/patches/hyper-regedit/track.3105'), env);
  check('unlicensed project blob remains public and cacheable', response.status === 200
    && response.headers.get('cache-control')?.startsWith('public'));

  // Opt-in controls: vault strict mode and per-licence fetch budgets. Both are
  // flipped with Worker vars, so an operator can tighten the feed without a
  // client build.
  const licenceCacheDb = ({ attested, rateCount = 0 }) => ({
    prepare(sql) {
      let args = [];
      return {
        bind(...values) { args = values; return this; },
        async first() {
          if (sql.includes('feed_key_state')) return { key_version: '2' };
          if (sql.includes('feed_auth_cache')) {
            const subject = String(args[0] || '');
            if (subject.startsWith('attest|') && !attested) return null;
            return { expires_at: 9_999_999_999 };
          }
          if (sql.includes('feed_rate_limits')) return { count: rateCount };
          return null;
        },
        async run() { return { success: true }; },
        async all() { return { results: [] }; },
      };
    },
  });

  response = await worker.fetch(
    request('/api/patches/trystore/character-vault/manifest.json', authorizedHeaders),
    { ...env, REQUIRE_VAULT_ATTESTATION: '1', DB: licenceCacheDb({ attested: false }) },
  );
  check('strict vault mode rejects a licence-only device',
    response.status === 403 && (await response.json()).error === 'attestation_required');

  response = await worker.fetch(
    request('/api/patches/trystore/character-vault/manifest.json', authorizedHeaders),
    { ...env, REQUIRE_VAULT_ATTESTATION: '1', DB: licenceCacheDb({ attested: true }) },
  );
  check('strict vault mode serves an attested device', response.status === 200);

  response = await worker.fetch(
    request('/api/patches/trystore/character-vault/rouk/rouk.mtl.tsc', authorizedHeaders),
    {
      ...env,
      VAULT_FETCH_LIMIT_PER_HOUR: '8',
      DB: licenceCacheDb({ attested: true, rateCount: 9 }),
    },
  );
  check('per-licence vault budget rejects a scraper',
    response.status === 429 && (await response.json()).error === 'fetch_quota_exceeded');

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

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', {}, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
  }), keyEnv);
  check('bundle key still requires a license', response.status === 401);

  response = await worker.fetch(request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
    challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
  }), keyEnv);
  const keyBody = await response.json();
  check('bundle key reports the rotated version', keyBody.keyVersion === '2');
  check('bundle key serves the v2 secret', keyBody.key === keyEnv.APP_BUNDLE_KEY_V2);
  check('bundle key responses stay uncacheable', response.headers.get('cache-control') === 'no-store');

  response = await worker.fetch(
    request('/api/patches/trystore/bundle-key', authorizedHeaders, 'POST', {
      challengeID: 'challenge-id', challenge: 'challenge-value', keyId: 'key-id', assertion: 'VALID-ASSERTION',
    }),
    { ...keyEnv, APP_BUNDLE_KEY_V2: '' },
  );
  check('bundle key fails closed when the served version has no secret', response.status === 503);
} finally {
  await rm(scratch, { recursive: true, force: true });
}
if (failures) process.exitCode = 1;
