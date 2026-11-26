// Run with: node --test cloudflare/test/panel-token.test.mjs
//
// The minting side lives in the licence Worker and the verifying side in the
// FFHub panel. These two must agree on the wire format, so this test imports
// both and feeds one into the other.

import assert from "node:assert/strict";
import { test } from "node:test";

import { mintPanelToken } from "../panel-token-format.js";
import { verifySession } from "../../ffhub/panel/lib/session.js";

const SECRET = "panel-token-key-0123456789abcdef01234567";
const NOW = 1_700_000_000;

test("the panel accepts a token minted for a device", async () => {
  const { token, expiresAt } = await mintPanelToken({
    secret: SECRET,
    deviceId: "device-abc",
    nowSeconds: NOW,
  });

  const claims = await verifySession({ secret: SECRET, token, nowMs: NOW * 1000 + 5000 });

  assert.equal(claims.role, "user");
  assert.equal(claims.subject, "device-abc");
  assert.equal(expiresAt, NOW + 600);
});

test("two handoffs in the same second are different sessions", async () => {
  const first = await mintPanelToken({ secret: SECRET, deviceId: "device-abc", nowSeconds: NOW });
  const second = await mintPanelToken({ secret: SECRET, deviceId: "device-abc", nowSeconds: NOW });

  assert.notEqual(first.token, second.token);
  assert.ok(await verifySession({ secret: SECRET, token: first.token, nowMs: NOW * 1000 }));
  assert.ok(await verifySession({ secret: SECRET, token: second.token, nowMs: NOW * 1000 }));
});

test("the panel refuses a token signed with another key", async () => {
  const { token } = await mintPanelToken({ secret: SECRET, deviceId: "d", nowSeconds: NOW });

  assert.equal(
    await verifySession({ secret: "another-secret-that-is-long-enough-xx", token, nowMs: NOW * 1000 }),
    null,
  );
});

test("the panel refuses an expired token", async () => {
  const { token } = await mintPanelToken({
    secret: SECRET,
    deviceId: "d",
    nowSeconds: NOW,
    ttlSeconds: 60,
  });

  assert.equal(await verifySession({ secret: SECRET, token, nowMs: (NOW + 61) * 1000 }), null);
});

test("a device id cannot be swapped into the payload", async () => {
  const { token } = await mintPanelToken({ secret: SECRET, deviceId: "device-abc", nowSeconds: NOW });
  const [version, , signature] = token.split(".");
  const payload = btoa(JSON.stringify({ sub: "other", role: "admin", aud: "ffhub-panel", iat: NOW, exp: NOW + 600 }))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");

  assert.equal(await verifySession({ secret: SECRET, token: `${version}.${payload}.${signature}`, nowMs: NOW * 1000 }), null);
});

test("minting refuses a weak key instead of shipping a guessable token", async () => {
  await assert.rejects(mintPanelToken({ secret: "short", deviceId: "d", nowSeconds: NOW }), /weak_secret/);
});
