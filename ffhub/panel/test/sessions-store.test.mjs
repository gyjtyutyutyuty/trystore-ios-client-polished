// Run with: node --test panel/test/sessions-store.test.mjs
//
// The D1 store is exercised end to end by test/local-chain.mjs; these are the
// semantics both stores must share.

import assert from "node:assert/strict";
import { test } from "node:test";

import { memorySessionStore } from "../lib/sessions-store.js";

const NOW = 1_700_000_000;

function session(overrides = {}) {
  return {
    id: "id-1",
    subject: "device-1",
    role: "user",
    issuedAt: NOW,
    expiresAt: NOW + 600,
    nowSeconds: NOW,
    ...overrides,
  };
}

test("register is idempotent and never revives a revoked session", async () => {
  const store = memorySessionStore();
  const entry = session();

  await store.register(entry);
  assert.equal(await store.isActive(entry), true);
  assert.equal(await store.revoke({ id: entry.id, nowSeconds: NOW + 1 }), 1);
  assert.equal(await store.isActive(entry), false);

  // Redeeming the same token again inserts nothing, so it stays dead.
  await store.register(entry);
  assert.equal(await store.isActive(entry), false);
  assert.equal(await store.revoke({ id: entry.id, nowSeconds: NOW + 2 }), 0);
});

test("a session only opens for the subject and role it was issued to", async () => {
  const store = memorySessionStore();
  await store.register(session());

  assert.equal(await store.isActive(session({ subject: "device-2" })), false);
  assert.equal(await store.isActive(session({ role: "admin" })), false);
  assert.equal(await store.isActive(session()), true);
});

test("expired sessions are dead and are not counted", async () => {
  const store = memorySessionStore();
  await store.register(session());

  assert.equal(await store.isActive(session({ nowSeconds: NOW + 600 })), false);
  assert.equal(await store.countRole({ role: "user", nowSeconds: NOW + 600 }), 0);
});

test("revoking one role leaves the other sessions alone", async () => {
  const store = memorySessionStore();
  await store.register(session({ id: "user-1", subject: "device-1" }));
  await store.register(session({ id: "user-2", subject: "device-2" }));
  await store.register(session({ id: "admin-1", subject: "owner", role: "admin" }));

  assert.equal(await store.countRole({ role: "user", nowSeconds: NOW }), 2);
  assert.equal(await store.revokeRole({ role: "user", nowSeconds: NOW + 1 }), 2);

  assert.equal(await store.countRole({ role: "user", nowSeconds: NOW + 1 }), 0);
  assert.equal(await store.isActive(session({ id: "user-1" })), false);
  assert.equal(
    await store.isActive(
      session({ id: "admin-1", subject: "owner", role: "admin" }),
    ),
    true,
  );
});
