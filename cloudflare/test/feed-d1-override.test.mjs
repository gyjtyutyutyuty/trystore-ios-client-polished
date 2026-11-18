// D1 is the repair channel when the KV write quota is exhausted, and the
// manifest must advertise the bytes the blob route actually serves.
//
//   node cloudflare/test/feed-d1-override.test.mjs

import assert from "node:assert/strict";
import worker from "../patch-feed-worker.js";

const fixed = new TextEncoder().encode("fixed-package-bytes");
const fixedHash = "5b6319e548588b0996176e59a7ef07a1746f703a2d57f100fef0bd1cf3593e46";
const manifest = {
  schemaVersion: 1,
  project: "trystore",
  updatedAt: "2026-11-14T18:12:52.652Z",
  patches: [
    {
      file: "Cuello y Drag.TRYSTORE",
      name: "Cuello y Drag",
      sha256: "d78a61f4d10482ca3113c7552cd9a136f36bc191a1e4dbe5213f6f70f6a2cbdd",
      size: 48151,
      url: "https://trystore-patch-feed.burgoajustin.workers.dev/patches/trystore/Cuello%20y%20Drag.TRYSTORE?v=d78a61f4d10482ca3113c7552cd9a136f36bc191a1e4dbe5213f6f70f6a2cbdd",
      schemaVersion: 2,
      isPasswordProtected: false,
    },
  ],
};

const db = {
  prepare(sql) {
    const stmt = {
      bind(...params) {
        stmt.params = params;
        return stmt;
      },
      async first() {
        if (sql.startsWith("SELECT count FROM feed_rate_limits")) return { count: 1 };
        if (sql.startsWith("SELECT expires_at FROM feed_auth_cache")) return null;
        if (sql.startsWith("SELECT name, sha256, size FROM feed_blobs")) return null;
        if (sql.startsWith("SELECT bytes FROM feed_blobs")) {
          return { bytes: fixed.buffer.slice(fixed.byteOffset, fixed.byteOffset + fixed.byteLength) };
        }
        return null;
      },
      async all() {
        if (sql.startsWith("SELECT name, sha256, size FROM feed_blobs")) {
          return { results: [{ name: "Cuello y Drag.TRYSTORE", sha256: fixedHash, size: fixed.length }] };
        }
        return { results: [] };
      },
      async run() {
        return { success: true, meta: { changes: 1 } };
      },
    };
    return stmt;
  },
};

const env = {
  DB: db,
  PATCHES: {
    async get(key) {
      if (key === "patches/trystore/manifest.json") return JSON.stringify(manifest);
      return null;
    },
    async put() {},
  },
  RESELLER: {
    async fetch() {
      return new Response(JSON.stringify({ valid: true, outcome: "active", expiresAt: null }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  },
  APP_BUNDLE_KEY: Buffer.alloc(32, 7).toString("base64"),
  PUBLIC_BASE_URL: "https://trystore-patch-feed.burgoajustin.workers.dev",
};

const headers = {
  authorization: "Bearer TRY-TEST-TEST-TEST",
  "x-trystore-device-id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "cf-connecting-ip": "198.51.100.9",
};

const manifestResponse = await worker.fetch(
  new Request("https://feed.test/api/patches/trystore/manifest.json", { headers }),
  env,
);
assert.equal(manifestResponse.status, 200);
const served = await manifestResponse.json();
const patch = served.patches[0];
assert.equal(patch.sha256, fixedHash);
assert.equal(patch.size, fixed.length);
assert.ok(patch.url.includes(`v=${fixedHash}`));
console.log("ok: manifest advertises the repaired hash and size");

const blobResponse = await worker.fetch(
  new Request("https://feed.test/patches/trystore/Cuello%20y%20Drag.TRYSTORE", { headers }),
  env,
);
assert.equal(blobResponse.status, 200);
const bytes = new Uint8Array(await blobResponse.arrayBuffer());
assert.deepEqual(bytes, fixed);
console.log("ok: repaired bytes come from D1 when KV has none");

console.log("\nall D1 override checks passed");
