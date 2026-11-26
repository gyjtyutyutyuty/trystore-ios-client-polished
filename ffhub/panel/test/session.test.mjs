// Run with: node --test panel/test/session.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  clearedSessionCookie,
  constantTimeEqual,
  hashedClient,
  mintSession,
  parseCookies,
  secretIsUsable,
  sessionCookie,
  verifySession,
} from "../lib/session.js";

const SECRET = "a-panel-signing-key-long-enough-to-pass";
const NOW = 1_700_000_000_000;

test("a minted session verifies and carries its role", async () => {
  const { token, expiresAt } = await mintSession({
    secret: SECRET,
    subject: "device-1",
    role: "user",
    ttlSeconds: 900,
    nowMs: NOW,
  });

  const claims = await verifySession({ secret: SECRET, token, nowMs: NOW + 1000 });

  assert.equal(claims.role, "user");
  assert.equal(claims.subject, "device-1");
  assert.equal(expiresAt, (Math.floor(NOW / 1000) + 900) * 1000);
});

test("an expired token is refused", async () => {
  const { token } = await mintSession({
    secret: SECRET,
    subject: "device-1",
    role: "user",
    ttlSeconds: 60,
    nowMs: NOW,
  });

  assert.equal(await verifySession({ secret: SECRET, token, nowMs: NOW + 61_000 }), null);
});

test("a token signed with another key is refused", async () => {
  const { token } = await mintSession({
    secret: SECRET,
    subject: "device-1",
    role: "admin",
    ttlSeconds: 900,
    nowMs: NOW,
  });

  assert.equal(
    await verifySession({ secret: "another-key-that-is-also-long-enough-x", token, nowMs: NOW }),
    null,
  );
});

test("a payload edited in flight is refused", async () => {
  const { token } = await mintSession({
    secret: SECRET,
    subject: "device-1",
    role: "user",
    ttlSeconds: 900,
    nowMs: NOW,
  });
  const [version, , signature] = token.split(".");
  const forged = btoa(JSON.stringify({ sub: "x", role: "admin", aud: "ffhub-panel", iat: 1, exp: 9e9 }))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");

  assert.equal(await verifySession({ secret: SECRET, token: `${version}.${forged}.${signature}`, nowMs: NOW }), null);
});

test("garbage never throws", async () => {
  for (const token of ["", "v1", "v2.a.b", "v1..", "v1.!!!.???", "x".repeat(5000), null, undefined]) {
    assert.equal(await verifySession({ secret: SECRET, token, nowMs: NOW }), null);
  }
});

test("a short secret is refused rather than trusted", async () => {
  assert.equal(secretIsUsable("short"), false);
  assert.equal(secretIsUsable("x".repeat(32)), true);
  await assert.rejects(
    mintSession({ secret: "short", subject: "s", role: "user", ttlSeconds: 60, nowMs: NOW }),
    /weak_secret/,
  );
  assert.equal(await verifySession({ secret: "short", token: "v1.a.b" }), null);
});

test("the cookie cannot be read by scripts and stays same-site", () => {
  const cookie = sessionCookie("v1.a.b", 900);

  assert.match(cookie, /^ffhub_session=v1\.a\.b; HttpOnly; Secure; SameSite=Lax; Path=\/; Max-Age=900$/);
  assert.match(clearedSessionCookie(), /Max-Age=0$/);
});

test("cookies parse without trusting duplicates", () => {
  const cookies = parseCookies("a=1; ffhub_session=first; ffhub_session=second; broken");

  assert.equal(cookies.get("a"), "1");
  assert.equal(cookies.get("ffhub_session"), "first");
});

test("comparison ignores length differences", () => {
  assert.equal(constantTimeEqual("abc", "abc"), true);
  assert.equal(constantTimeEqual("abc", "abd"), false);
  assert.equal(constantTimeEqual("abc", "abcd"), false);
  assert.equal(constantTimeEqual(undefined, ""), true);
});

test("rate-limit buckets do not carry the address", async () => {
  const one = await hashedClient(SECRET, "203.0.113.7");
  const two = await hashedClient(SECRET, "203.0.113.7");
  const other = await hashedClient(SECRET, "203.0.113.8");

  assert.equal(one, two);
  assert.notEqual(one, other);
  assert.match(one, /^[0-9a-f]{24}$/);
});
