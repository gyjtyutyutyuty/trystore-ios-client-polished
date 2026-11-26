// Sessions for the panel.
//
// The panel used to be public: anyone with the URL could spend the provider
// key. A session is an HMAC-signed token in an HttpOnly cookie, so a cracked
// IPA yields the URL but not the signing key, and the key never sits in the
// binary.
//
// Two roles:
//   user  — minted by the licence Worker after App Attest proves this is the
//           real app on a licensed device. Short lived.
//   admin — minted here from PANEL_ADMIN_PASSWORD, for the owner.
//
// Everything is stateless on purpose: a session is a claim the Worker can
// verify with a secret, with no database read on the hot path.

export const SESSION_COOKIE = "ffhub_session";
export const AUDIENCE = "ffhub-panel";
export const ROLES = ["user", "admin"];

const VERSION = "v1";
const MAX_TOKEN_LENGTH = 4096;
const encoder = new TextEncoder();

function bytesToBase64Url(bytes) {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function base64UrlToBytes(value) {
  const normalized = String(value || "").replaceAll("-", "+").replaceAll("_", "/");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized)) throw new Error("bad_base64");
  const raw = atob(normalized);
  const bytes = new Uint8Array(raw.length);
  for (let index = 0; index < raw.length; index += 1) bytes[index] = raw.charCodeAt(index);
  return bytes;
}

/// Comparison that does not leak the position of the first mismatch. Used for
/// signatures and for the admin password.
export function constantTimeEqual(left, right) {
  const a = String(left ?? "");
  const b = String(right ?? "");
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let index = 0; index < a.length; index += 1) {
    mismatch |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return mismatch === 0;
}

async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(String(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function signature(secret, payloadText) {
  const key = await hmacKey(secret);
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(payloadText));
  return bytesToBase64Url(new Uint8Array(digest));
}

/// A secret short enough to guess is worse than no session: refuse to mint.
export function secretIsUsable(secret, minimum = 32) {
  return typeof secret === "string" && secret.length >= minimum;
}

export async function mintSession({ secret, subject, role, ttlSeconds, nowMs = Date.now() }) {
  if (!secretIsUsable(secret)) throw new Error("weak_secret");
  if (!ROLES.includes(role)) throw new Error("bad_role");
  const issuedAt = Math.floor(nowMs / 1000);
  const claims = {
    sub: String(subject || role).slice(0, 128),
    role,
    aud: AUDIENCE,
    iat: issuedAt,
    exp: issuedAt + Math.max(60, Math.floor(ttlSeconds)),
  };
  const payloadText = bytesToBase64Url(encoder.encode(JSON.stringify(claims)));
  const signed = `${VERSION}.${payloadText}`;
  return { token: `${signed}.${await signature(secret, signed)}`, expiresAt: claims.exp * 1000 };
}

/// Returns the claims, or null for anything that is not a live, signed token
/// for this audience. Never throws on hostile input.
export async function verifySession({ secret, token, nowMs = Date.now() }) {
  if (!secretIsUsable(secret)) return null;
  const raw = String(token || "");
  if (!raw || raw.length > MAX_TOKEN_LENGTH) return null;
  const parts = raw.split(".");
  if (parts.length !== 3 || parts[0] !== VERSION) return null;
  const signed = `${parts[0]}.${parts[1]}`;
  let expected;
  try {
    expected = await signature(secret, signed);
  } catch {
    return null;
  }
  if (!constantTimeEqual(expected, parts[2])) return null;

  let claims;
  try {
    claims = JSON.parse(new TextDecoder().decode(base64UrlToBytes(parts[1])));
  } catch {
    return null;
  }
  if (!claims || typeof claims !== "object") return null;
  if (claims.aud !== AUDIENCE || !ROLES.includes(claims.role)) return null;
  const nowSeconds = Math.floor(nowMs / 1000);
  if (!Number.isFinite(claims.exp) || claims.exp <= nowSeconds) return null;
  // A token issued in the future means a clock was used to extend it.
  if (!Number.isFinite(claims.iat) || claims.iat > nowSeconds + 60) return null;
  if (claims.exp - claims.iat > 60 * 60 * 24) return null;
  return { subject: String(claims.sub || ""), role: claims.role, issuedAt: claims.iat, expiresAt: claims.exp };
}

export function parseCookies(header) {
  const cookies = new Map();
  for (const chunk of String(header || "").split(";")) {
    const separator = chunk.indexOf("=");
    if (separator < 0) continue;
    const name = chunk.slice(0, separator).trim();
    if (!name || cookies.has(name)) continue;
    cookies.set(name, chunk.slice(separator + 1).trim());
  }
  return cookies;
}

/// SameSite=Lax keeps the cookie off cross-site POSTs; the Worker also checks
/// Origin on mutations. Secure is required: the panel is https only.
export function sessionCookie(token, maxAgeSeconds) {
  return `${SESSION_COOKIE}=${token}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${Math.max(0, Math.floor(maxAgeSeconds))}`;
}

export function clearedSessionCookie() {
  return `${SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`;
}

/// Bucket key for rate limiting: the limiter never stores a raw address.
export async function hashedClient(secret, address) {
  const salt = secretIsUsable(secret) ? String(secret) : "ffhub-rate-limit";
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(`${salt}:${address}`));
  return [...new Uint8Array(digest)].slice(0, 12).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
