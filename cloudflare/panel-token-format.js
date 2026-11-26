// The wire format of an FFHub panel session, shared by the licence Worker (which
// mints) and ffhub/panel/lib/session.js (which verifies). It is a separate
// module so the format can be tested without pulling in App Attest.
//
//   v1.<base64url(JSON claims)>.<base64url(HMAC-SHA256(secret, "v1.<claims>"))>
//
// claims: { sub: deviceId, role: "user", aud: "ffhub-panel", iat, exp }
// Changing any of that means changing the panel too.

export const PANEL_AUDIENCE = "ffhub-panel";
export const PANEL_TOKEN_TTL = 600;

const encoder = new TextEncoder();

export function bytesToBase64Url(bytes) {
  let text = "";
  for (const byte of new Uint8Array(bytes)) text += String.fromCharCode(byte);
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function hmac(secret, text) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(String(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(text)));
}

export async function mintPanelToken({ secret, deviceId, nowSeconds, ttlSeconds = PANEL_TOKEN_TTL }) {
  if (String(secret || "").length < 32) throw new Error("weak_secret");
  if (!String(deviceId || "").trim()) throw new Error("missing_device");
  const issuedAt = Math.floor(nowSeconds);
  const claims = {
    sub: String(deviceId).slice(0, 128),
    role: "user",
    aud: PANEL_AUDIENCE,
    iat: issuedAt,
    exp: issuedAt + Math.max(60, Math.floor(ttlSeconds)),
    // Two handoffs for the same device in the same second must be two
    // sessions; the panel registers them by hash and revokes one at a time.
    jti: crypto.randomUUID(),
  };
  const payload = bytesToBase64Url(encoder.encode(JSON.stringify(claims)));
  const signed = `v1.${payload}`;
  return { token: `${signed}.${bytesToBase64Url(await hmac(secret, signed))}`, expiresAt: claims.exp };
}
