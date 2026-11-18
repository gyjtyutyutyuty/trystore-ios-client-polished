// Legacy IPA compatibility test. Uses an isolated mock licence service; no
// production signing keys or credentials are required.
//
//   node cloudflare/test/feed-legacy-compat.test.mjs

import assert from "node:assert/strict";
import feedWorker from "../patch-feed-worker.js";

const device = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const licenseKey = "TRY-AAAAAA-BBBBBB-CCCCCC";
const bundleKey = crypto.getRandomValues(new Uint8Array(32));
const bundleKeyB64 = Buffer.from(bundleKey).toString("base64");

function feedEnv({ licenseValid = false, values = new Map(), rateLimitUnavailable = false } = {}) {
  const rateLimits = new Map();
  return {
    APP_BUNDLE_KEY: bundleKeyB64,
    RESELLER: {
      async fetch(request) {
        const body = await request.json();
        const valid = licenseValid
          && body.key === licenseKey
          && body.deviceId === device
          && body.projectId === "trystore"
          && body.appVersion === "1.1.1";
        return new Response(JSON.stringify({
          valid,
          outcome: valid ? "active" : "invalid",
          expiresAt: new Date(Date.now() + 60_000).toISOString(),
        }), { headers: { "content-type": "application/json" } });
      },
    },
    PATCHES: {
      async get(key, type) {
        if (rateLimitUnavailable && key.startsWith("rl:")) {
          throw new Error("simulated KV quota failure");
        }
        const value = values.get(key) ?? rateLimits.get(key) ?? null;
        if (type === "arrayBuffer" && value instanceof Uint8Array) {
          return value.slice().buffer;
        }
        return value;
      },
      async put(key, value) {
        if (rateLimitUnavailable && key.startsWith("rl:")) {
          throw new Error("simulated KV quota failure");
        }
        rateLimits.set(key, value);
      },
    },
  };
}

function request(path, authorization = `Bearer ${licenseKey}`) {
  const headers = {
    "x-trystore-device-id": device,
    "cf-connecting-ip": "203.0.113.40",
  };
  if (authorization) headers.authorization = authorization;
  return new Request(`https://feed.test${path}`, { headers });
}

const authorizedEnv = () => feedEnv({ licenseValid: true });

const keyResponse = await feedWorker.fetch(
  request("/api/patches/trystore/bundle-key"),
  authorizedEnv(),
);
assert.equal(keyResponse.status, 200);
const keyBody = await keyResponse.json();
assert.equal(keyBody.valid, true);
assert.equal(keyBody.key, bundleKeyB64);
assert.equal(keyBody.keyVersion, "1");
assert.equal(keyBody.wrappedKey, undefined);
console.log("ok: legacy IPA receives the expected bundle-key response");

const invalidKeyResponse = await feedWorker.fetch(
  request("/api/patches/trystore/bundle-key"),
  feedEnv({ licenseValid: false }),
);
assert.equal(invalidKeyResponse.status, 401);

const anonymousKeyResponse = await feedWorker.fetch(
  request("/api/patches/trystore/bundle-key", null),
  authorizedEnv(),
);
assert.equal(anonymousKeyResponse.status, 401);
console.log("ok: invalid and anonymous bundle-key requests are denied");

const patchBytes = new TextEncoder().encode("legacy-ipa-patch");
const values = new Map([
  ["patches/trystore/manifest.json", JSON.stringify({
    schemaVersion: 1,
    project: "trystore",
    patches: [],
  })],
  ["patches/trystore/sample.TRYSTORE", patchBytes],
]);
const manifestResponse = await feedWorker.fetch(
  request("/api/patches/trystore/manifest.json"),
  feedEnv({ licenseValid: true, values }),
);
assert.equal(manifestResponse.status, 200);
assert.equal((await manifestResponse.json()).project, "trystore");

const blobResponse = await feedWorker.fetch(
  request("/patches/trystore/sample.TRYSTORE"),
  feedEnv({ licenseValid: true, values }),
);
assert.equal(blobResponse.status, 200);
assert.deepEqual(new Uint8Array(await blobResponse.arrayBuffer()), patchBytes);

const quotaFailureBlobResponse = await feedWorker.fetch(
  request("/patches/trystore/sample.TRYSTORE"),
  feedEnv({ licenseValid: true, values, rateLimitUnavailable: true }),
);
assert.equal(quotaFailureBlobResponse.status, 200);

const quotaFailureAnonymousResponse = await feedWorker.fetch(
  request("/patches/trystore/sample.TRYSTORE", null),
  feedEnv({ licenseValid: true, values, rateLimitUnavailable: true }),
);
assert.equal(quotaFailureAnonymousResponse.status, 401);

const anonymousBlobResponse = await feedWorker.fetch(
  request("/patches/trystore/sample.TRYSTORE", null),
  authorizedEnv(),
);
assert.equal(anonymousBlobResponse.status, 401);
console.log("ok: legacy licensed IPA can download manifest and patch bytes; anonymous access stays blocked");
console.log("ok: KV rate-counter failures do not block licensed downloads or authorize anonymous requests");

console.log("\nall legacy IPA compatibility checks passed");
