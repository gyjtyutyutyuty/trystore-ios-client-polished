// Issues the session token the FFHub panel accepts.
//
// The panel is private: without a session its Worker answers 401, and the only
// way to obtain one is this route. It demands what a cracked IPA cannot
// produce — a fresh App Attest assertion from the enrolled device, signed over
// the challenge this server issued — and then mints a ten-minute HMAC token.
//
// The signing key (PANEL_TOKEN_KEY) lives in Worker secrets on both sides. It
// is never in the app, so extracting the app yields the panel URL and nothing
// that opens it.
//
// Token layout matches ffhub/panel/lib/session.js exactly:
//   v1.<base64url(claims)>.<base64url(HMAC-SHA256(secret, "v1.<claims>"))>
// with aud "ffhub-panel". Keep the two in step; the panel rejects anything else.

import { verifyAssertion } from "@bradford-tech/supabase-integrity-attest/assertion";
import { mintPanelToken, PANEL_TOKEN_TTL } from "./panel-token-format.js";

const PROJECT = "trystore";
const PURPOSE = "bundle-key";
const TOKEN_TTL = PANEL_TOKEN_TTL;
const MAX_ASSERTION = 12_000;
const PANEL_PATH = "/api/patches/trystore/panel-token";
const APP_BUNDLE_ID = "cc.forcequit.worse-query";

const encoder = new TextEncoder();

const hex = (bytes) => [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");

async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

function config(env) {
  const secret = String(env.PANEL_TOKEN_KEY || "");
  const appId = String(env.APP_ATTEST_APP_ID || "").trim();
  const environment = String(env.APP_ATTEST_ENVIRONMENT || "").trim().toLowerCase();
  if (secret.length < 32) return null;
  if (!appId.endsWith(`.${APP_BUNDLE_ID}`) || !/^[A-Z0-9]{1,64}\./.test(appId)) return null;
  if (!["production", "development"].includes(environment)) return null;
  return { secret, appId, developmentEnv: environment === "development", environment };
}

function internalRequest(request, env) {
  const expected = String(env.APP_ATTEST_INTERNAL_TOKEN || "");
  const supplied = String(request.headers.get("x-app-attest-internal-token") || "");
  if (expected.length < 32 || supplied.length !== expected.length) return false;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
  }
  return mismatch === 0;
}

/// What the app signs. The method and path are part of it, so an assertion made
/// for the bundle key can never be replayed here.
function clientData(challengeId, challenge, deviceId) {
  return encoder.encode(
    ["TryStore App Attest v1", challengeId, challenge, "POST", PANEL_PATH, deviceId].join("\n"),
  );
}

async function authorizeLicense(env, body, deps) {
  const key = String(body.key || "").trim();
  const deviceId = String(body.deviceId || "").trim();
  if (!key || key.length > 256 || body.projectId !== PROJECT || !deps.validDevice(deviceId)) return null;
  const license = await deps.findKey(env, key);
  if (!license || license.slug !== PROJECT || license.status !== "active") return null;
  if (Number(license.expires_at) <= deps.now()) return null;
  const claimed = await deps.claimDevice(env, license, deviceId);
  if (!claimed.ok) return null;
  return { license, deviceId };
}

export async function handlePanelToken(request, env, deps) {
  const response = deps.json;
  if (!internalRequest(request, env)) return response({ error: "not_found" }, 404);
  const settings = config(env);
  if (!settings) return response({ error: "panel_unavailable" }, 503);

  let body;
  try {
    body = await request.json();
  } catch {
    return response({ error: "invalid_request" }, 400);
  }

  const authorized = await authorizeLicense(env, body, deps);
  if (!authorized) return response({ error: "license_required" }, 401);

  const challengeId = String(body.challengeID || "");
  const challenge = String(body.challenge || "");
  const keyId = String(body.keyId || "");
  const assertion = String(body.assertion || "");
  if (!/^[0-9a-f-]{36}$/i.test(challengeId) || challenge.length > 128) {
    return response({ error: "invalid_assertion" }, 400);
  }
  if (!keyId || keyId.length > 128 || !assertion || assertion.length > MAX_ASSERTION) {
    return response({ error: "invalid_assertion" }, 400);
  }

  let challengeBytes;
  try {
    const normalized = challenge.replaceAll("-", "+").replaceAll("_", "/");
    const raw = atob(normalized);
    challengeBytes = Uint8Array.from(raw, (char) => char.charCodeAt(0));
  } catch {
    return response({ error: "invalid_assertion" }, 400);
  }
  if (challengeBytes.length !== 32) return response({ error: "invalid_assertion" }, 400);

  const record = await env.DB.prepare(
    "SELECT challenge_id, challenge_hash, license_key_id, device_id, key_id, purpose, expires_at, consumed_at FROM app_attest_challenges WHERE challenge_id=?1",
  )
    .bind(challengeId)
    .first();
  const expectedHash = hex(await sha256(challengeBytes));
  const usable =
    record &&
    record.consumed_at === null &&
    Number(record.expires_at) > deps.now() &&
    Number(record.license_key_id) === Number(authorized.license.id) &&
    record.device_id === authorized.deviceId &&
    record.purpose === PURPOSE &&
    record.key_id === keyId &&
    record.challenge_hash === expectedHash;
  if (!usable) return response({ error: "attestation_required" }, 401);

  const key = await env.DB.prepare(
    "SELECT public_key_pem, sign_count, environment FROM app_attest_keys WHERE key_id=?1 AND license_key_id=?2 AND device_id=?3",
  )
    .bind(keyId, authorized.license.id, authorized.deviceId)
    .first();
  if (!key || !key.public_key_pem || key.environment !== settings.environment) {
    return response({ error: "attestation_required" }, 401);
  }

  let verified;
  try {
    verified = await verifyAssertion(
      { appId: settings.appId },
      assertion,
      clientData(challengeId, challenge, authorized.deviceId),
      key.public_key_pem,
      Number(key.sign_count),
    );
  } catch {
    return response({ error: "assertion_rejected" }, 403);
  }

  const consumed = await env.DB.prepare(
    "UPDATE app_attest_challenges SET consumed_at=?1 WHERE challenge_id=?2 AND purpose=?3 AND consumed_at IS NULL AND expires_at>?1",
  )
    .bind(deps.now(), challengeId, PURPOSE)
    .run();
  if (Number(consumed?.meta?.changes || 0) !== 1) {
    return response({ error: "challenge_expired_or_used" }, 409);
  }

  // The counter must move: an assertion replayed with the old sign count would
  // otherwise keep minting tokens.
  const saved = await env.DB.prepare(
    "UPDATE app_attest_keys SET sign_count=?1, last_seen_at=?2 WHERE key_id=?3 AND license_key_id=?4 AND device_id=?5 AND sign_count=?6",
  )
    .bind(verified.signCount, deps.now(), keyId, authorized.license.id, authorized.deviceId, Number(key.sign_count))
    .run();
  if (Number(saved?.meta?.changes || 0) !== 1) return response({ error: "assertion_replayed" }, 409);

  const minted = await mintPanelToken({
    secret: settings.secret,
    deviceId: authorized.deviceId,
    nowSeconds: deps.now(),
    ttlSeconds: TOKEN_TTL,
  });
  return response({
    token: minted.token,
    expiresAt: new Date(minted.expiresAt * 1000).toISOString(),
    ttlSeconds: TOKEN_TTL,
  });
}
