// Feed contract test: a session minted by the licence worker opens the
// bundle key, a tampered one does not, and the key never appears in the clear.
//
//   node cloudflare/test/feed-session.test.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import licenseWorker from "../license-worker.js";
import feedWorker from "../patch-feed-worker.js";

const here = dirname(fileURLToPath(import.meta.url));
const secrets = JSON.parse(readFileSync(join(here, "../../.secrets/session-key.json"), "utf8"));

const now = Math.floor(Date.now() / 1000);
const keyRow = {
  id: 7,
  key_hint: "ABCDEFGHIJ",
  status: "active",
  expires_at: now + 86400,
  max_devices: 1,
  slug: "trystore",
  project_id: 1,
  created_at: now - 60,
  updated_at: now - 60,
  reseller_id: 1,
};

function licenseDB() {
  return {
    prepare(sql) {
      const stmt = {
        bind() {
          return stmt;
        },
        async first() {
          if (sql.startsWith("SELECT count FROM api_rate_limits")) return null;
          if (sql.includes("FROM global_keys g JOIN projects")) return keyRow;
          return null;
        },
        async all() {
          return { results: [] };
        },
        async run() {
          return { success: true };
        },
      };
      return stmt;
    },
  };
}

const bundleKey = crypto.getRandomValues(new Uint8Array(32));
const bundleB64 = Buffer.from(bundleKey).toString("base64");

function feedEnv() {
  const store = new Map();
  return {
    APP_BUNDLE_KEY: bundleB64,
    PATCHES: {
      async get(key) {
        return store.get(key) ?? null;
      },
      async put(key, value) {
        store.set(key, value);
      },
    },
  };
}

const device = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";

const licenseResponse = await licenseWorker.fetch(
  new Request("https://licence.test/api/v1/keys/validate", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.20" },
    body: JSON.stringify({ key: "TRY-AAAAAA-BBBBBB-CCCCCC", deviceId: device, projectId: "trystore" }),
  }),
  {
    DB: licenseDB(),
    SESSION_SIGNING_KEY: secrets.private_pkcs8_b64,
    LICENSE_SIGNING_SECRET: "test-secret",
  },
);
const licenseBody = await licenseResponse.json();
assert.equal(licenseBody.valid, true);
assert.ok(licenseBody.session, "validate must return a session");

async function bundleKeyRequest(session) {
  return feedWorker.fetch(
    new Request("https://feed.test/api/patches/trystore/bundle-key", {
      headers: {
        authorization: `Bearer ${session}`,
        "x-trystore-device-id": device,
        "cf-connecting-ip": "203.0.113.21",
      },
    }),
    feedEnv(),
  );
}

const ok = await bundleKeyRequest(licenseBody.session);
assert.equal(ok.status, 200);
const okBody = await ok.json();
assert.equal(okBody.valid, true);
assert.ok(okBody.wrappedKey && okBody.salt);
assert.notEqual(okBody.wrappedKey, bundleB64);
assert.equal(JSON.stringify(okBody).includes(bundleB64), false, "bundle key must not appear in the clear");

// Rebuild the HKDF key and open the sealed bundle key.
const salt = Uint8Array.from(Buffer.from(okBody.salt, "base64"));
const wrapped = Uint8Array.from(Buffer.from(okBody.wrappedKey, "base64"));
const base = await crypto.subtle.importKey(
  "raw",
  new TextEncoder().encode(licenseBody.session),
  "HKDF",
  false,
  ["deriveKey"],
);
const kek = await crypto.subtle.deriveKey(
  {
    name: "HKDF",
    hash: "SHA-256",
    salt,
    info: new TextEncoder().encode("trystore-bundle-v1"),
  },
  base,
  { name: "AES-GCM", length: 256 },
  false,
  ["decrypt"],
);
const opened = new Uint8Array(
  await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: wrapped.subarray(0, 12) },
    kek,
    wrapped.subarray(12),
  ),
);
assert.deepEqual(Buffer.from(opened), Buffer.from(bundleKey));
console.log("ok: session opens the bundle key, wire value is sealed");

// Tampered payload must fail the signature.
const [payload, signature] = licenseBody.session.split(".");
const tampered = Buffer.from(
  Buffer.from(payload.replaceAll("-", "+").replaceAll("_", "/"), "base64")
    .toString("utf8")
    .replace('"keyId":7', '"keyId":8'),
).toString("base64url");
const forged = `${tampered}.${signature}`;
const rejected = await bundleKeyRequest(forged);
assert.equal(rejected.status, 401);
console.log("ok: tampered session rejected");

// No session at all must not reach the key.
const anonymous = await feedWorker.fetch(
  new Request("https://feed.test/api/patches/trystore/bundle-key", {
    headers: { "x-trystore-device-id": device, "cf-connecting-ip": "203.0.113.22" },
  }),
  feedEnv(),
);
assert.equal(anonymous.status, 401);
console.log("ok: anonymous bundle-key rejected");

const manifest = await feedWorker.fetch(
  new Request("https://feed.test/api/patches/trystore/manifest.json", {
    headers: {
      authorization: `Bearer ${licenseBody.session}`,
      "x-trystore-device-id": device,
      "cf-connecting-ip": "203.0.113.23",
    },
  }),
  feedEnv(),
);
assert.equal(manifest.status, 200);
console.log("ok: manifest served to a valid session");

console.log("\nall feed checks passed");
