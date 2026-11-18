// Exercises the signed licence session end to end against the public half of
// the pinned Ed25519 key. No network, no D1: the database is a stub that only
// answers the queries the validate path issues.
//
//   node cloudflare/test/license-session.test.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import worker from "../license-worker.js";

const here = dirname(fileURLToPath(import.meta.url));
const secrets = JSON.parse(readFileSync(join(here, "../../.secrets/session-key.json"), "utf8"));
const publicKey = new Uint8Array(Buffer.from(secrets.public_raw_b64, "base64"));

const now = Math.floor(Date.now() / 1000);
const row = {
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

function stubDB() {
  return {
    prepare(sql) {
      const stmt = {
        params: [],
        bind(...params) {
          stmt.params = params;
          return stmt;
        },
        async first() {
          if (sql.startsWith("SELECT count FROM api_rate_limits")) return null;
          if (sql.includes("FROM global_keys g JOIN projects")) return row;
          return null;
        },
        async all() {
          if (sql.includes("FROM license_devices")) return { results: [] };
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

const env = {
  DB: stubDB(),
  SESSION_SIGNING_KEY: secrets.private_pkcs8_b64,
  LICENSE_SIGNING_SECRET: "test-secret",
};

function b64urlToBytes(text) {
  const normalized = text.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(Buffer.from(normalized, "base64"));
}

async function verify(session, device) {
  const [payload, signature] = session.split(".");
  assert.ok(payload && signature, "session must have two parts");

  const key = await crypto.subtle.importKey("raw", publicKey, { name: "Ed25519" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("Ed25519", key, b64urlToBytes(signature), new TextEncoder().encode(payload));
  assert.ok(ok, "signature must verify against the pinned public key");

  const claims = JSON.parse(Buffer.from(b64urlToBytes(payload)).toString("utf8"));
  assert.equal(claims.v, 1);
  assert.equal(claims.iss, "trystore-license");
  assert.equal(claims.aud, "trystore-feed");
  assert.equal(claims.kid, "trystore-ed25519-v1");
  assert.equal(claims.project, "trystore");
  assert.equal(claims.device, device);
  assert.equal(claims.keyId, 7);
  assert.ok(claims.nonce.length >= 16);
  assert.ok(claims.exp > now);
  return claims;
}

const device = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";

const response = await worker.fetch(
  new Request("https://worker.test/api/v1/keys/validate", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.10" },
    body: JSON.stringify({ key: "TRY-AAAAAA-BBBBBB-CCCCCC", deviceId: device, projectId: "trystore" }),
  }),
  env,
);

assert.equal(response.status, 200);
const body = await response.json();
assert.equal(body.valid, true);
assert.equal(body.outcome, "active");
const claims = await verify(body.session, device);
console.log("ok: session verifies, keyId", claims.keyId, "exp", claims.exp);

// A body without a device must not mint a session.
const missing = await worker.fetch(
  new Request("https://worker.test/api/v1/keys/validate", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.11" },
    body: JSON.stringify({ key: "TRY-AAAAAA-BBBBBB-CCCCCC" }),
  }),
  env,
);
const missingBody = await missing.json();
assert.equal(missingBody.outcome, "invalid_device");
console.log("ok: missing device rejected");

// Tampering with the payload must break the signature.
const [payload, signature] = body.session.split(".");
const tampered = Buffer.from(b64urlToBytes(payload)).toString("utf8").replace('"keyId":7', '"keyId":8');
const forgedPayload = Buffer.from(tampered).toString("base64url");
const verifyKey = await crypto.subtle.importKey("raw", publicKey, { name: "Ed25519" }, false, ["verify"]);
const forgedOK = await crypto.subtle.verify(
  "Ed25519",
  verifyKey,
  b64urlToBytes(signature),
  new TextEncoder().encode(forgedPayload),
);
assert.equal(forgedOK, false);
console.log("ok: tampered claims rejected");

console.log("\nall session checks passed");



