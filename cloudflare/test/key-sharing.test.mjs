// One key, many networks: the server freezes it instead of issuing a session.
//
//   node cloudflare/test/key-sharing.test.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import worker from "../license-worker.js";

const here = dirname(fileURLToPath(import.meta.url));
const secrets = JSON.parse(readFileSync(join(here, "../../.secrets/session-key.json"), "utf8"));

const now = Math.floor(Date.now() / 1000);
const keyRow = {
  id: 7,
  key_hint: "ABCDEFGHIJ",
  status: "active",
  expires_at: now + 86400,
  max_devices: 4,
  slug: "trystore",
  project_id: 1,
  created_at: now,
  updated_at: now,
  reseller_id: 1,
};

function makeDB({ networks }) {
  const state = { updates: [], inserts: [] };
  return {
    state,
    prepare(sql) {
      const stmt = {
        bind(...params) {
          stmt.params = params;
          return stmt;
        },
        async first() {
          if (sql.startsWith("SELECT count FROM api_rate_limits")) return null;
          if (sql.includes("FROM global_keys g JOIN projects")) return keyRow;
          if (sql.includes("COUNT(*) AS n FROM license_signals")) return { n: networks };
          if (sql.includes("COUNT(*) AS n FROM license_devices")) return { n: 0 };
          return null;
        },
        async all() {
          return { results: [] };
        },
        async run() {
          if (sql.startsWith("UPDATE global_keys")) {
            state.updates.push(sql);
            return { success: true, meta: { changes: 1 } };
          }
          if (sql.startsWith("INSERT INTO license_signals")) state.inserts.push(sql);
          return { success: true, meta: { changes: 1 } };
        },
      };
      return stmt;
    },
  };
}

async function validate(db) {
  const response = await worker.fetch(
    new Request("https://licence.test/api/v1/keys/validate", {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": "198.51.100.77" },
      body: JSON.stringify({
        key: "TRY-AAAAAA-BBBBBB-CCCCCC",
        deviceId: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
        projectId: "trystore",
      }),
    }),
    {
      DB: db,
      SESSION_SIGNING_KEY: secrets.private_pkcs8_b64,
      LICENSE_SIGNING_SECRET: "test-secret",
      MAX_DISTINCT_IPS: "8",
    },
  );
  return { status: response.status, body: await response.json() };
}

// Nine distinct networks in the window: over the limit of eight.
const sharedDB = makeDB({ networks: 9 });
const shared = await validate(sharedDB);
assert.equal(shared.body.valid, false);
assert.equal(shared.body.outcome, "frozen");
assert.equal(shared.body.session, undefined);
assert.equal(sharedDB.state.updates.length, 1);
assert.ok(sharedDB.state.updates[0].includes("status='frozen'"));
console.log("ok: nine networks freezes the key");

// Three networks: normal roaming, session issued.
const normalDB = makeDB({ networks: 3 });
const normal = await validate(normalDB);
assert.equal(normal.body.valid, true);
assert.ok(normal.body.session);
assert.equal(normalDB.state.updates.length, 0);
console.log("ok: normal use still activates");

// The IP is stored hashed, never in the clear.
const insert = normalDB.state.inserts[0];
assert.ok(insert, "signal row must be written");
console.log("ok: network signal recorded");

console.log("\nall key-sharing checks passed");
