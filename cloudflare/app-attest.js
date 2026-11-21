import { verifyAssertion } from "@bradford-tech/supabase-integrity-attest/assertion";
import { verifyAttestation } from "@bradford-tech/supabase-integrity-attest/attestation";

const APP_BUNDLE_ID = "cc.forcequit.worse-query";
const PURPOSE_ATTEST = "attestation";
const PURPOSE_BUNDLE = "bundle-key";
const CHALLENGE_TTL = 180;
const encoder = new TextEncoder();

const bytesToBase64 = (bytes) => btoa(String.fromCharCode(...bytes));
const base64ToBytes = (value) => {
  const normalized = String(value || "").replaceAll("-", "+").replaceAll("_", "/");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) throw new Error("bad_base64");
  const raw = atob(normalized);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
};
const hex = (bytes) => [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}
function config(env) {
  const appId = String(env.APP_ATTEST_APP_ID || "").trim();
  const environment = String(env.APP_ATTEST_ENVIRONMENT || "").trim().toLowerCase();
  if (!appId.endsWith(`.${APP_BUNDLE_ID}`) || !/^[A-Z0-9]{1,64}\./.test(appId)
      || !["production", "development"].includes(environment)) return null;
  return { appId, developmentEnv: environment === "development", environment };
}
function internalRequest(request, env) {
  const expected = String(env.APP_ATTEST_INTERNAL_TOKEN || "");
  const supplied = String(request.headers.get("x-app-attest-internal-token") || "");
  if (expected.length < 32 || supplied.length !== expected.length) return false;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index += 1) mismatch |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
  return mismatch === 0;
}
async function authorizeLicense(env, body, deps) {
  const key = String(body.key || "").trim();
  const deviceId = String(body.deviceId || "").trim();
  if (!key || key.length > 256 || body.projectId !== "trystore" || !deps.validDevice(deviceId)) return null;
  const license = await deps.findKey(env, key);
  if (!license || license.slug !== "trystore" || license.status !== "active" || Number(license.expires_at) <= deps.now()) return null;
  const claimed = await deps.claimDevice(env, license, deviceId);
  if (!claimed.ok) return null;
  return { license, deviceId };
}
function challengeClientData(challengeId, challenge, deviceId) {
  return encoder.encode([
    "TryStore App Attest v1",
    challengeId,
    challenge,
    "POST",
    "/api/patches/trystore/bundle-key",
    deviceId,
  ].join("\n"));
}
async function issueChallenge(request, env, body, deps, response) {
  const authorized = await authorizeLicense(env, body, deps);
  if (!authorized) return response({ error: "license_required" }, 401);
  const suppliedKeyId = String(body.keyId || "");
  let mode = "attest";
  let keyId = null;
  if (suppliedKeyId && suppliedKeyId.length <= 128) {
    const registered = await env.DB.prepare(
      "SELECT key_id FROM app_attest_keys WHERE key_id=?1 AND license_key_id=?2 AND device_id=?3",
    ).bind(suppliedKeyId, authorized.license.id, authorized.deviceId).first();
    if (registered) {
      mode = "assertion";
      keyId = registered.key_id;
    }
  }
  const challengeId = crypto.randomUUID();
  const challengeBytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = bytesToBase64(challengeBytes);
  const challengeHash = hex(await sha256(challengeBytes));
  const purpose = mode === "assertion" ? PURPOSE_BUNDLE : PURPOSE_ATTEST;
  const issuedAt = deps.now();
  await env.DB.prepare(
    "INSERT INTO app_attest_challenges (challenge_id, challenge_hash, license_key_id, device_id, key_id, purpose, issued_at, expires_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
  ).bind(challengeId, challengeHash, authorized.license.id, authorized.deviceId, keyId, purpose, issuedAt, issuedAt + CHALLENGE_TTL).run();
  return response({ challengeId, challenge, mode, expiresAt: new Date((issuedAt + CHALLENGE_TTL) * 1000).toISOString() });
}
async function readChallenge(env, body, authorized, purpose, deps) {
  const challengeId = String(body.challengeID || "");
  const challenge = String(body.challenge || "");
  if (!/^[0-9a-f-]{36}$/i.test(challengeId)) return null;
  let bytes;
  try { bytes = base64ToBytes(challenge); } catch { return null; }
  if (bytes.length !== 32) return null;
  const record = await env.DB.prepare(
    "SELECT challenge_id, challenge_hash, license_key_id, device_id, key_id, purpose, expires_at, consumed_at FROM app_attest_challenges WHERE challenge_id=?1",
  ).bind(challengeId).first();
  if (!record || record.consumed_at !== null || Number(record.expires_at) <= deps.now()
      || Number(record.license_key_id) !== Number(authorized.license.id)
      || record.device_id !== authorized.deviceId || record.purpose !== purpose
      || hex(await sha256(bytes)) !== record.challenge_hash) return null;
  return { record, challengeId, challenge, bytes };
}
async function consumeChallenge(env, challengeId, purpose, deps) {
  const result = await env.DB.prepare(
    "UPDATE app_attest_challenges SET consumed_at=?1 WHERE challenge_id=?2 AND purpose=?3 AND consumed_at IS NULL AND expires_at>?1",
  ).bind(deps.now(), challengeId, purpose).run();
  return Number(result?.meta?.changes || 0) === 1;
}
async function register(request, env, body, deps, response) {
  const settings = config(env);
  if (!settings) return response({ error: "attestation_unavailable" }, 503);
  const authorized = await authorizeLicense(env, body, deps);
  if (!authorized) return response({ error: "license_required" }, 401);
  const challenge = await readChallenge(env, body, authorized, PURPOSE_ATTEST, deps);
  const keyId = String(body.keyId || "");
  const attestation = String(body.attestation || "");
  if (!challenge || !keyId || keyId.length > 128 || !attestation || attestation.length > 12000) {
    return response({ error: "invalid_attestation_request" }, 400);
  }
  let result;
  try {
    result = await verifyAttestation(
      { appId: settings.appId, developmentEnv: settings.developmentEnv },
      keyId,
      await sha256(challenge.bytes),
      attestation,
    );
  } catch {
    return response({ error: "attestation_rejected" }, 403);
  }
  if (!await consumeChallenge(env, challenge.challengeId, PURPOSE_ATTEST, deps)) {
    return response({ error: "challenge_expired_or_used" }, 409);
  }
  const createdAt = deps.now();
  try {
    await env.DB.prepare(
      "INSERT INTO app_attest_keys (key_id, license_key_id, device_id, public_key_pem, sign_count, environment, created_at, last_seen_at) VALUES (?1,?2,?3,?4,?5,?6,?7,?7) ON CONFLICT(license_key_id,device_id) DO UPDATE SET key_id=excluded.key_id, public_key_pem=excluded.public_key_pem, sign_count=excluded.sign_count, environment=excluded.environment, created_at=excluded.created_at, last_seen_at=excluded.last_seen_at",
    ).bind(keyId, authorized.license.id, authorized.deviceId, result.publicKeyPem, result.signCount, settings.environment, createdAt).run();
  } catch {
    return response({ error: "attestation_registration_failed" }, 409);
  }
  return response({ valid: true, keyId, environment: settings.environment });
}
async function authorizeBundleKey(request, env, body, deps, response) {
  const settings = config(env);
  if (!settings) return response({ error: "attestation_unavailable" }, 503);
  const authorized = await authorizeLicense(env, body, deps);
  if (!authorized) return response({ error: "license_required" }, 401);
  const keyId = String(body.keyId || "");
  const challenge = await readChallenge(env, body, authorized, PURPOSE_BUNDLE, deps);
  if (!challenge || !keyId || challenge.record.key_id !== keyId) {
    return response({ error: "attestation_required" }, 401);
  }
  const key = await env.DB.prepare(
    "SELECT public_key_pem, sign_count, environment FROM app_attest_keys WHERE key_id=?1 AND license_key_id=?2 AND device_id=?3",
  ).bind(keyId, authorized.license.id, authorized.deviceId).first();
  if (!key || !key.public_key_pem || key.environment !== settings.environment
      || !Number.isSafeInteger(Number(key.sign_count))) {
    return response({ error: "attestation_required" }, 401);
  }
  const assertion = String(body.assertion || "");
  if (!assertion || assertion.length > 12000) return response({ error: "invalid_assertion" }, 400);
  let verified;
  try {
    verified = await verifyAssertion(
      { appId: settings.appId },
      assertion,
      challengeClientData(challenge.challengeId, challenge.challenge, authorized.deviceId),
      key.public_key_pem,
      Number(key.sign_count),
    );
  } catch {
    return response({ error: "assertion_rejected" }, 403);
  }
  if (!await consumeChallenge(env, challenge.challengeId, PURPOSE_BUNDLE, deps)) {
    return response({ error: "challenge_expired_or_used" }, 409);
  }
  const saved = await env.DB.prepare(
    "UPDATE app_attest_keys SET sign_count=?1, last_seen_at=?2 WHERE key_id=?3 AND license_key_id=?4 AND device_id=?5 AND sign_count=?6",
  ).bind(verified.signCount, deps.now(), keyId, authorized.license.id, authorized.deviceId, Number(key.sign_count)).run();
  if (Number(saved?.meta?.changes || 0) !== 1) return response({ error: "assertion_replayed" }, 409);
  return response({ valid: true, expiresAt: new Date(Number(authorized.license.expires_at) * 1000).toISOString() });
}

export async function handleAppAttestRoute(request, env, pathname, dependencies) {
  const response = dependencies.json;
  if (!internalRequest(request, env)) return response({ error: "not_found" }, 404);
  if (!config(env)) return response({ error: "attestation_unavailable" }, 503);
  let body;
  try { body = await request.json(); } catch { return response({ error: "invalid_request" }, 400); }
  try {
    if (pathname === "/api/v1/app-attest/challenge") return await issueChallenge(request, env, body, dependencies, response);
    if (pathname === "/api/v1/app-attest/register") return await register(request, env, body, dependencies, response);
    if (pathname === "/api/v1/app-attest/authorize-bundle-key") return await authorizeBundleKey(request, env, body, dependencies, response);
    return response({ error: "not_found" }, 404);
  } catch {
    return response({ error: "server_error" }, 500);
  }
}
