#!/usr/bin/env node
// Route/state smoke tests for the App Attest Worker module. These do not replace
// Apple-hardware tests with genuine attestation/assertion objects.
import { webcrypto } from "node:crypto";
import { handleAppAttestRoute } from "../cloudflare/app-attest.js";

globalThis.crypto ??= webcrypto;
const deviceId = "550e8400-e29b-41d4-a716-446655440000";
const license = {
  id: 7,
  slug: "trystore",
  status: "active",
  expires_at: Math.floor(Date.now() / 1000) + 3600,
  max_devices: 1,
};
class FakeD1 {
  challenges = new Map();
  keyRecord = null;
  prepare(sql) {
    const state = this;
    return {
      params: [],
      bind(...params) { this.params = params; return this; },
      async first() {
        const p = this.params;
        if (sql.includes("SELECT key_id FROM app_attest_keys")) {
          return state.keyRecord?.key_id === p[0] ? { key_id: state.keyRecord.key_id } : null;
        }
        if (sql.includes("FROM app_attest_challenges WHERE challenge_id")) return state.challenges.get(p[0]) || null;
        if (sql.includes("SELECT public_key_pem, sign_count, environment")) return state.keyRecord;
        return null;
      },
      async run() {
        const p = this.params;
        if (sql.includes("INSERT INTO app_attest_challenges")) {
          state.challenges.set(p[0], {
            challenge_id: p[0], challenge_hash: p[1], license_key_id: p[2], device_id: p[3],
            key_id: p[4], purpose: p[5], issued_at: p[6], expires_at: p[7], consumed_at: null,
          });
          return { meta: { changes: 1 } };
        }
        if (sql.includes("UPDATE app_attest_challenges SET consumed_at")) {
          const challenge = state.challenges.get(p[1]);
          if (!challenge || challenge.consumed_at !== null || challenge.purpose !== p[2] || challenge.expires_at <= p[0]) {
            return { meta: { changes: 0 } };
          }
          challenge.consumed_at = p[0];
          return { meta: { changes: 1 } };
        }
        return { meta: { changes: 1 } };
      },
    };
  }
}

const db = new FakeD1();
const token = "test-internal-token-".padEnd(64, "x");
const env = {
  DB: db,
  APP_ATTEST_APP_ID: "K976G5HK7K.cc.forcequit.worse-query",
  APP_ATTEST_ENVIRONMENT: "production",
  APP_ATTEST_INTERNAL_TOKEN: token,
};
const dependencies = {
  json: (value, status = 200) => Response.json(value, { status }),
  now: () => Math.floor(Date.now() / 1000),
  validDevice: (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value),
  findKey: async (_env, value) => value === "ACTIVE-KEY-001" ? license : null,
  claimDevice: async () => ({ ok: true }),
};
const makeRequest = (pathname, body, headers = {}) => new Request(`https://reseller.internal${pathname}`, {
  method: "POST",
  headers: { "content-type": "application/json", "x-app-attest-internal-token": token, ...headers },
  body: JSON.stringify(body),
});
let failures = 0;
const check = (name, condition) => {
  console.log(`${condition ? "ok  " : "FAIL"} ${name}`);
  if (!condition) failures += 1;
};

let response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/challenge", { key: "ACTIVE-KEY-001", deviceId, projectId: "trystore" }, { "x-app-attest-internal-token": "" }),
  env,
  "/api/v1/app-attest/challenge",
  dependencies,
);
check("App Attest routes are hidden without the service-binding token", response.status === 404);

const missingConfig = { ...env, APP_ATTEST_APP_ID: "" };
response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/challenge", { key: "ACTIVE-KEY-001", deviceId, projectId: "trystore" }),
  missingConfig,
  "/api/v1/app-attest/challenge",
  dependencies,
);
check("missing registered App ID fails closed", response.status === 503);

response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/challenge", { key: "ACTIVE-KEY-001", deviceId, projectId: "trystore" }),
  env,
  "/api/v1/app-attest/challenge",
  dependencies,
);
const challenge = await response.json();
check("active device receives a short-lived registration challenge", response.status === 200
  && challenge.mode === "attest" && challenge.challengeId && challenge.challenge
  && db.challenges.has(challenge.challengeId));

response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/register", {
    key: "ACTIVE-KEY-001", deviceId, projectId: "trystore", challengeID: challenge.challengeId,
    challenge: challenge.challenge, keyId: "not-a-real-key", attestation: "bm90LWNhcGJvci1hdHRlc3RhdGlvbg==",
  }),
  env,
  "/api/v1/app-attest/register",
  dependencies,
);
check("malformed Apple attestation is rejected", response.status === 403);
check("failed attestation does not consume the challenge", db.challenges.get(challenge.challengeId).consumed_at === null);

const knownKeyID = "dGVzdC1rZXktaWQ=";
db.keyRecord = {
  key_id: knownKeyID,
  license_key_id: license.id,
  device_id: deviceId,
  public_key_pem: "not-a-real-pem",
  sign_count: 0,
  environment: "production",
};
response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/challenge", { key: "ACTIVE-KEY-001", deviceId, projectId: "trystore", keyId: knownKeyID }),
  env,
  "/api/v1/app-attest/challenge",
  dependencies,
);
const assertionChallenge = await response.json();
check("registered key receives an assertion challenge bound to bundle-key purpose", response.status === 200
  && assertionChallenge.mode === "assertion"
  && db.challenges.get(assertionChallenge.challengeId)?.purpose === "bundle-key");

response = await handleAppAttestRoute(
  makeRequest("/api/v1/app-attest/authorize-bundle-key", {
    key: "ACTIVE-KEY-001", deviceId, projectId: "trystore", challengeID: assertionChallenge.challengeId,
    challenge: assertionChallenge.challenge, keyId: knownKeyID, assertion: "bm90LWNhcGJvci1hc3NlcnRpb24=",
  }),
  env,
  "/api/v1/app-attest/authorize-bundle-key",
  dependencies,
);
check("invalid assertion cannot authorize bundle-key release", response.status === 403);
check("failed assertion leaves its challenge unused but does not release a key", db.challenges.get(assertionChallenge.challengeId).consumed_at === null);

if (failures) process.exitCode = 1;
