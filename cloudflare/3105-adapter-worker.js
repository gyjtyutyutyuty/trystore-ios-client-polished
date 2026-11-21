/*
 * 3105 Supabase-compatible adapter for the Global Key Control D1 database.
 *
 * The 3105 IPA speaks a narrow slice of PostgREST plus Supabase Realtime v1.
 * This Worker accepts those routes, validates keys through the existing
 * jvztxnx-global-control Worker (service binding LICENSE), and stores device
 * bindings plus access logs in the same D1 database.
 *
 * Deployed as: https://3105api.burgoajustin.workers.dev  (exactly 40 chars)
 */

const PROJECT_SLUG = "3105";
const TARGET = "3105";
const LEGACY_BASE = "https://uckcsnvmcomxethtfqum.supabase.co";
// Public anon key from the original 3105 build. Read-only proxy for patch
// packages and announcements only; key validation never uses it.
const LEGACY_ANON =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVja2NzbnZtY29teGV0aHRmcXVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3OTIwMDgsImV4cCI6MjEwODM2ODAwOH0._k0xyKIUDpwPtWky4JChDgHEWwLU5T6gGXcy2D7RnZc";

// RX7 build: moon-auth session tokens (Ed25519 JWS) and the /v1 patch feed.
const MOON_ISSUER = "rx7-moon-auth";
const MOON_KID = "rx7-ed25519-v1";
const MOON_PUBLIC_B64 = "64CR/7WzfVhhekWHpOaIqQYPuTv/CKa3kTmKzjw5UXQ=";
const SESSION_TTL = 30 * 24 * 60 * 60;
// The vault key belongs in a Worker secret. The previous value shipped in
// this file, so it is compromised and must be rotated regardless.
const vaultKey = (env) => String(env.VAULT_KEY_B64 || "");
const PATCH_IDS = [
  "bcb5f263-5d47-5739-9a9f-e9b64c309038",
  "369d64cc-1244-5c36-8602-dedb118501d2",
  "7fb6c143-5a59-5043-b9da-4eb6acce2937",
  "b192b699-c3e7-5210-be48-41b146484680",
  "7ea36b40-f6c7-5ae1-b911-48fa0ef2e0e0",
  "b7852e92-43ac-5290-92a5-8618e154876e",
  "c9a0ae53-4f96-5a64-87a3-33d0c5df872a",
  "12d1dd97-5304-5f35-aba6-15e6dc15e57c",
];

/*
 * The v2.0 panel (the "Panel de control" build) reads this table through
 * PostgREST.  Field names and types were recovered from the class field
 * descriptor at __swift5_fieldmd 0x10015616c: every string is SS, downloadUrl
 * and fileHash and blockMessage are SSSg, fileSize/version/sortOrder are Si,
 * isActive/isBlocked are Sb.  The list is deliberately Panther's eight
 * packages and nothing else.
 */
const PANEL_PATCHES = [
  {
    id: "7fb6c143-5a59-5043-b9da-4eb6acce2937",
    patch_key: "hsalto",
    display_name: "HS ALTO NEW IOS",
    patch_filename: "HSNEWALTO.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "5a1982935564cfeb1d6cd7ed60a60aba9b6b871bb71c8aa43f3c784b7d3e57a5",
    file_size: 46999,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 1,
  },
  {
    id: "c9a0ae53-4f96-5a64-87a3-33d0c5df872a",
    patch_key: "dragneckholo",
    display_name: "Dragneck y Holo By SRiOS",
    patch_filename: "aimdragneckyholoaypbyseniorios.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "8cff8b036148221c18cd8b220d98468b315246b1c86e95bdd8584a267e7b1444",
    file_size: 1915031,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 2,
  },
  {
    id: "b7852e92-43ac-5290-92a5-8618e154876e",
    patch_key: "pechoholo",
    display_name: "Pecho y Holo By SRiOS",
    patch_filename: "Pechoyhologramaspyabyseniorios.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "9109ab632237b08cb04091f25ca7fcc50c96b38babefb324d47840e6ae3c8653",
    file_size: 1915031,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 3,
  },
  {
    id: "bcb5f263-5d47-5739-9a9f-e9b64c309038",
    patch_key: "balasholo",
    display_name: "Balas M y Holo By SRiOS",
    patch_filename: "BALAS - HOLOGRAMAS - By SRiOS.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "3bfaf77476263574e10765341624e71e81b182b0b6e480b3df36952a148dd023",
    file_size: 1915042,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 4,
  },
  {
    id: "b192b699-c3e7-5210-be48-41b146484680",
    patch_key: "dragantena",
    display_name: "DRAG ANTENA NEW IOS",
    patch_filename: "NormalDragAntena-2.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "7a4f2920662c1b6cc54e3b97760c96909b22da71ca9a0256a59f98367c2c9420",
    file_size: 47011,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 5,
  },
  {
    id: "7ea36b40-f6c7-5ae1-b911-48fa0ef2e0e0",
    patch_key: "pechodesi",
    display_name: "PECHO DESI NEW IOS",
    patch_filename: "PECHODESIMULADO.3105",
    category: "Aimbot",
    mode: "FF NORMAL",
    icon: "scope",
    file_hash: "c0236a18557dd6bbca8f9ead09aa2c41b1a047cd895bd1b19375a99b1faa437f",
    file_size: 46995,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 6,
  },
  {
    id: "12d1dd97-5304-5f35-aba6-15e6dc15e57c",
    patch_key: "hsdragmax",
    display_name: "HS DRAG + HOLO BY N&S",
    patch_filename: "hsaltobynewiosysrios.3105",
    category: "Aimbot",
    mode: "FF MAX",
    icon: "scope",
    file_hash: "5512d565e7d1c7e3db249f4a8451784488ca1a68931cbeb9b6523d0b9f51da3f",
    file_size: 1507169,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 7,
  },
  {
    id: "369d64cc-1244-5c36-8602-dedb118501d2",
    patch_key: "dragmax",
    display_name: "DRAG NEW",
    patch_filename: "DRAGMAX-2.3105",
    category: "Aimbot",
    mode: "FF MAX",
    icon: "scope",
    file_hash: "18219d4ce15754fcb4c3d16bc991055de78e052b3b3a194126d02756b181c217",
    file_size: 47544,
    version: 1,
    is_blocked: false,
    block_message: null,
    sort_order: 8,
  },
];

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,PATCH,DELETE,OPTIONS",
  "access-control-allow-headers":
    "apikey,authorization,content-type,prefer,accept,accept-profile,content-profile,x-client-info,x-supabase-api-version",
  "access-control-max-age": "86400",
};

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...CORS,
      ...extra,
    },
  });
}

function empty(status = 201, extra = {}) {
  return new Response(null, {
    status,
    headers: { "cache-control": "no-store", ...CORS, ...extra },
  });
}

function clientIP(request) {
  return request.headers.get("cf-connecting-ip")
    || request.headers.get("x-real-ip")
    || "unknown";
}

// Same D1 counter the licence Worker uses. A failure here must not turn a
// working panel into a 500, so a missing table reads as "allow".
async function allowDb(env, bucket, subject, limit, windowSeconds) {
  if (!env.DB) return true;
  const window = Math.floor(Date.now() / 1000 / windowSeconds);
  try {
    await env.DB.prepare(
      "INSERT INTO api_rate_limits(bucket,subject,window_start,hits) VALUES(?1,?2,?3,1) " +
      "ON CONFLICT(bucket,subject,window_start) DO UPDATE SET hits=hits+1"
    )
      .bind(bucket, subject, window)
      .run();
    const row = await env.DB.prepare(
      "SELECT hits FROM api_rate_limits WHERE bucket=?1 AND subject=?2 AND window_start=?3"
    )
      .bind(bucket, subject, window)
      .first();
    return Number(row?.hits || 1) <= limit;
  } catch {
    return true;
  }
}

// access_logs used to receive the licence key verbatim, which turned a single
// D1 read into working credentials for every account in the table. Only a
// peppered reference is stored now; without the Worker secret the column is
// useless. The prefix keeps old and new rows distinguishable during the scrub.
async function accessLogRef(env, value) {
  const text = String(value || "").trim();
  const pepper = String(env.ACCESS_LOG_PEPPER || "");
  if (!text || pepper.length < 16) return "";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode("3105-access-log-v1\n" + text)
  );
  return "k1:" + [...new Uint8Array(mac).slice(0, 16)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// The public anon JWT is compiled into the 3105 client and cannot be a hard
// secret, but requiring it stops drive-by scanners and keeps the legacy proxy
// honest. ADAPTER_API_KEY lets a future client build move to its own value.
function panelKeyAccepted(env, presented) {
  const value = String(presented || "").trim();
  if (!value) return false;
  const accepted = [String(env.ADAPTER_API_KEY || ""), LEGACY_ANON].filter(Boolean);
  return accepted.includes(value);
}

function panelKeyFrom(request, url) {
  const header = request.headers.get("apikey");
  if (header) return header;
  const authorization = request.headers.get("authorization") || "";
  if (authorization.toLowerCase().startsWith("bearer ")) return authorization.slice(7).trim();
  return url.searchParams.get("apikey") || "";
}

function redactQuery(url) {
  if (!url.searchParams.toString()) return "";
  const clean = new URLSearchParams();
  for (const [name, value] of url.searchParams) {
    clean.set(name, /key_value|apikey|authorization|token/i.test(name) ? "[redacted]" : value);
  }
  return "?" + clean.toString();
}

function maskDevice(value) {
  const text = String(value || "");
  if (text.length <= 8) return "unknown";
  return text.slice(0, 8) + "\u2026";
}

function iso(seconds) {
  const n = Number(seconds);
  if (!Number.isFinite(n) || n <= 0) return null;
  return new Date(n * 1000).toISOString().replace("Z", "+00:00");
}

function epoch(value) {
  if (value == null) return Math.floor(Date.now() / 1000);
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : Math.floor(Date.now() / 1000);
}

function eqValue(params, name) {
  const raw = params.get(name);
  if (!raw) return null;
  return raw.startsWith("eq.") ? raw.slice(3) : raw;
}

function statusFromRow(row) {
  const now = Math.floor(Date.now() / 1000);
  if (row.status === "revoked") return "revoked";
  if (Number(row.expires_at) <= now) return "expired";
  if (row.status === "frozen") return "frozen";
  return row.status === "active" ? "active" : row.status || "frozen";
}

function rowFromDb(row, keyValue = "") {
  const outcome = statusFromRow(row);
  return {
    id: String(row.id),
    key_value: keyValue || row.key_hint || "",
    is_active: outcome === "active",
    is_banned: outcome === "revoked",
    label: "cracked by: @jvztxn",
    expires_at: iso(row.expires_at),
    max_devices: Number(row.max_devices || 0),
    created_at: iso(row.created_at),
    updated_at: iso(row.updated_at),
  };
}

async function resolveKey(env, key, request) {
  const body = JSON.stringify({ key, projectId: PROJECT_SLUG });
  const headers = { "content-type": "application/json" };
  // Without the caller's address the licence Worker buckets every adapter
  // request under "unknown", so one script could exhaust the shared 30/min
  // resolve limit and block all real activations.
  const ip = request ? clientIP(request) : "unknown";
  if (ip !== "unknown") headers["cf-connecting-ip"] = ip;
  const requestInit = { method: "POST", headers, body };
  const forward = new Request("https://license.internal/api/v1/keys/resolve", requestInit);
  let response;
  if (env.LICENSE) {
    response = await env.LICENSE.fetch(forward);
  } else {
    const origin = env.LICENSE_ORIGIN || "https://jvztxnx-global-control.burgoajustin.workers.dev";
    response = await fetch(origin + "/api/v1/keys/resolve", requestInit);
  }
  if (!response.ok) throw new Error("license resolve failed: " + response.status);
  return response.json();
}

function supabaseIso(value) {
  if (!value) return null;
  const text = String(value);
  return text.endsWith("Z") ? text.slice(0, -1) + "+00:00" : text;
}

function resolvedRow(resolved, keyValue) {
  const outcome = String(resolved.outcome || (resolved.valid ? "active" : "invalid"));
  return {
    id: String(resolved.keyId),
    key_value: keyValue,
    is_active: outcome === "active",
    is_banned: outcome === "revoked",
    // The panel prints this as "<label>–<last six of the key>".
    label: "cracked by: @jvztxn",
    expires_at: supabaseIso(resolved.expiresAt),
    max_devices: Number(resolved.maxDevices || 0),
    created_at: supabaseIso(resolved.createdAt),
    updated_at: supabaseIso(resolved.updatedAt),
  };
}

async function dbKeyById(env, id) {
  return env.DB.prepare(
    "SELECT g.*, p.slug, p.name FROM global_keys g JOIN projects p ON p.id=g.project_id WHERE g.id=?1 AND p.slug=?2 LIMIT 1"
  )
    .bind(Number(id), PROJECT_SLUG)
    .first();
}

function b64urlEncode(bytes) {
  let text = "";
  for (const byte of new Uint8Array(bytes)) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64Decode(text) {
  const normalized = String(text || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const raw = atob(padded);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

async function moonSign(env, data) {
  const der = b64Decode(env.MOON_PRIVATE_KEY || "");
  let key;
  try {
    key = await crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"]);
    return new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, key, data));
  } catch (error) {
    key = await crypto.subtle.importKey(
      "pkcs8",
      der,
      { name: "NODE-ED25519", namedCurve: "NODE-ED25519" },
      false,
      ["sign"]
    );
    return new Uint8Array(await crypto.subtle.sign("NODE-ED25519", key, data));
  }
}

async function moonVerify(signature, data) {
  const raw = b64Decode(MOON_PUBLIC_B64);
  try {
    const key = await crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, key, signature, data);
  } catch (error) {
    const key = await crypto.subtle.importKey(
      "raw",
      raw,
      { name: "NODE-ED25519", namedCurve: "NODE-ED25519" },
      false,
      ["verify"]
    );
    return await crypto.subtle.verify("NODE-ED25519", key, signature, data);
  }
}

function isoFromEpoch(seconds) {
  // verifySessionToken parses dates with ISO8601DateFormatter options 0xf73
  // (withFractionalSeconds) and only falls back to 0x773. Keep the millis.
  return new Date(Number(seconds) * 1000).toISOString();
}

async function issueSession(env, { keyId, deviceId, challenge, uid, licenseExp, maxDevices }) {
  const now = Math.floor(Date.now() / 1000);
  const exp = Math.min(Number(licenseExp) || now + SESSION_TTL, now + SESSION_TTL);
  const encoder = new TextEncoder();
  const licenseExpiry = Number(licenseExp) || exp;
  const slots = Number(maxDevices) === 1 ? 1 : 999;

  // sendAndVerifySession verifies the signature over this blob, then reads the
  // session fields out of the blob itself: valid, nonce, server_time,
  // session_token, session_expires_at, max_devices, uid_verified,
  // vault_key_base64, expires_at.
  //
  // verifySessionToken is strict about the JWT: header alg is compared to the
  // exact string "EDDSA" (not "EdDSA"), typ must be "JWT", kid must be
  // rx7-ed25519-v1; payload iss/aud are exact, sub and jti must parse as
  // UUIDs, sub must equal the device ID, nonce must equal the challenge.
  const header = { alg: "EDDSA", typ: "JWT", kid: MOON_KID };
  const payload = {
    iss: MOON_ISSUER,
    aud: "rx7-ios",
    sub: deviceId,
    device_id: deviceId,
    nonce: challenge,
    iat: now,
    exp,
    jti: crypto.randomUUID(),
    key_id: String(keyId || ""),
    uid: uid || deviceId,
  };
  const body =
    b64urlEncode(encoder.encode(JSON.stringify(header))) +
    "." +
    b64urlEncode(encoder.encode(JSON.stringify(payload)));
  const signature = await moonSign(env, encoder.encode(body));
  const token = body + "." + b64urlEncode(signature);

  const envelopeClaims = {
    valid: true,
    nonce: challenge,
    device_id: deviceId,
    uid: uid || deviceId,
    server_time: isoFromEpoch(now),
    session_token: token,
    session_expires_at: isoFromEpoch(exp),
    max_devices: slots,
    uid_verified: true,
    vault_key_base64: vaultKey(env),
    expires_at: isoFromEpoch(licenseExpiry),
    key_id: String(keyId || ""),
  };
  const envelopeBytes = encoder.encode(JSON.stringify(envelopeClaims));
  const envelopeSignature = await moonSign(env, envelopeBytes);

  return {
    token,
    envelope: b64urlEncode(envelopeBytes),
    envelopeSignature: b64urlEncode(envelopeSignature),
    exp,
    maxDevices: slots,
    licenseExp: licenseExpiry,
  };
}

async function readSession(request) {
  const header = request.headers.get("authorization") || "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const encoder = new TextEncoder();
  let valid;
  try {
    valid = await moonVerify(b64Decode(parts[2]), encoder.encode(parts[0] + "." + parts[1]));
  } catch {
    return null;
  }
  if (!valid) return null;
  let payload;
  try {
    payload = JSON.parse(new TextDecoder().decode(b64Decode(parts[1])));
  } catch {
    return null;
  }
  if (!payload || Number(payload.exp) <= Math.floor(Date.now() / 1000)) return null;
  return payload;
}

async function bindDevice(env, keyId, deviceId) {
  const key = await env.DB.prepare(
    "SELECT g.id,g.max_devices FROM global_keys g JOIN projects p ON p.id=g.project_id WHERE g.id=?1 AND p.slug=?2"
  )
    .bind(keyId, PROJECT_SLUG)
    .first();
  if (!key) return { ok: false, reason: "unknown_key" };
  const maxDevices = Number(key.max_devices || 0);
  const existing = await env.DB.prepare(
    "SELECT id FROM global_key_devices WHERE key_id=?1 AND device_hash=?2 AND target=?3"
  )
    .bind(keyId, deviceId, TARGET)
    .first();
  if (!existing && maxDevices > 0) {
    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM global_key_devices WHERE key_id=?1 AND target=?2"
    )
      .bind(keyId, TARGET)
      .first();
    if (Number(count?.n || 0) >= maxDevices) return { ok: false, reason: "device_limit" };
  }
  const seen = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    "INSERT INTO global_key_devices(key_id,device_hash,target,first_seen_at,last_seen_at) VALUES (?1,?2,?3,?4,?4) ON CONFLICT(key_id,device_hash,target) DO UPDATE SET last_seen_at=excluded.last_seen_at"
  )
    .bind(keyId, deviceId, TARGET, seen)
    .run();
  return { ok: true, maxDevices };
}

async function handleMoonAuth(env, request) {
  if (request.method !== "POST") return json({ message: "Acción no válida." }, 405);
  let body;
  try {
    body = await request.json();
  } catch {
    body = {};
  }
  const action = String(body.action || "");
  const challenge = String(body.challenge || "");
  const deviceId = String(body.device_id || "").trim();
  const now = Math.floor(Date.now() / 1000);
  console.log("MOON", action || "(none)", deviceId || "(no device)", challenge ? "challenge" : "no-challenge");
  // The client verifies the Ed25519 signature before it reads `valid`, so even
  // failures travel as a signed envelope. Unsigned errors surface as the
  // generic "Supabase returned an invalid response." on the device.
  const deny = async (message, code = "LICENSE_INACTIVE") => {
    const encoder = new TextEncoder();
    const claims = {
      valid: false,
      nonce: challenge,
      server_time: isoFromEpoch(now),
      message,
      code,
    };
    const bytes = encoder.encode(JSON.stringify(claims));
    const signature = await moonSign(env, bytes);
    return json({
      valid: false,
      nonce: challenge,
      server_time: isoFromEpoch(now),
      envelope: b64urlEncode(bytes),
      signature: b64urlEncode(signature),
      message,
      code,
    });
  };
  if (!challenge || !deviceId) return deny("La conexión de licencias debe usar HTTPS.");

  if (action === "validate-key") {
    const keyValue = String(body.key || "").trim();
    // Never reject a login on key resolution. Unknown or expired keys fall
    // back to a long-lived shared license so the client always gets a session.
    if (!keyValue) return deny("Introduce una licencia válida.", "LICENSE_REQUIRED");
    let resolved;
    try {
      resolved = await resolveKey(env, keyValue);
    } catch {
      return deny("No se pudo validar la licencia.", "LICENSE_UNAVAILABLE");
    }
    const outcome = String(resolved?.outcome || (resolved?.valid ? "active" : "invalid")).toLowerCase();
    const keyId = Number(resolved?.keyId) || 0;
    const licenseExp = epoch(resolved?.expiresAt);
    if (outcome !== "active" || !keyId || !(licenseExp > now + 60)) {
      return deny("La licencia no está activa.", "LICENSE_INACTIVE");
    }
    const rawSlots = Number(resolved?.maxDevices);
    const maxDevices = Number.isFinite(rawSlots) && rawSlots > 0 ? rawSlots : 1;
    let bound;
    try {
      bound = await bindDevice(env, keyId, deviceId);
    } catch {
      return deny("No se pudo verificar el dispositivo.", "DEVICE_UNAVAILABLE");
    }
    if (!bound?.ok) {
      return deny(
        bound?.reason === "device_limit" ? "Límite de dispositivos alcanzado." : "Dispositivo no autorizado.",
        "DEVICE_LIMIT",
      );
    }
    const session = await issueSession(env, {
      keyId,
      deviceId,
      challenge,
      uid: deviceId,
      licenseExp,
      maxDevices,
    });
    return json({
      valid: true,
      nonce: challenge,
      server_time: isoFromEpoch(now),
      session_token: session.token,
      session_expires_at: isoFromEpoch(session.exp),
      envelope: session.envelope,
      signature: session.envelopeSignature,
      vault_key_base64: vaultKey(env),
      uid: deviceId,
      uid_verified: true,
      expires_at: isoFromEpoch(session.licenseExp),
      max_devices: session.maxDevices,
    });
  }

  if (action === "verify-uid" || action === "verify-session") {
    const uid = String(body.uid || "").trim();
    const saved = await readSession(request);
    const keyId = saved ? Number(saved.key_id) : 0;
    if (!Number.isFinite(keyId) || keyId <= 0) {
      return deny("La sesión no es válida.", "SESSION_INVALID");
    }
    let row;
    try {
      row = await dbKeyById(env, keyId);
    } catch {
      return deny("No se pudo validar la licencia.", "LICENSE_UNAVAILABLE");
    }
    const licenseExp = Number(row?.expires_at);
    if (!row || !(licenseExp > now + 60)) {
      return deny("La licencia no está activa.", "LICENSE_INACTIVE");
    }
    const rawSlots = Number(row.max_devices);
    const maxDevices = Number.isFinite(rawSlots) && rawSlots > 0 ? rawSlots : 1;
    let bound;
    try {
      bound = await bindDevice(env, keyId, deviceId);
    } catch {
      return deny("No se pudo verificar el dispositivo.", "DEVICE_UNAVAILABLE");
    }
    if (!bound?.ok) {
      return deny(
        bound?.reason === "device_limit" ? "Límite de dispositivos alcanzado." : "Dispositivo no autorizado.",
        "DEVICE_LIMIT",
      );
    }
    const session = await issueSession(env, {
      keyId: keyId || "0",
      deviceId,
      challenge,
      uid: uid || deviceId,
      licenseExp,
      maxDevices,
    });
    return json({
      valid: true,
      nonce: challenge,
      server_time: isoFromEpoch(now),
      session_token: session.token,
      session_expires_at: isoFromEpoch(session.exp),
      envelope: session.envelope,
      signature: session.envelopeSignature,
      vault_key_base64: vaultKey(env),
      uid: uid || deviceId,
      uid_verified: true,
      expires_at: isoFromEpoch(session.licenseExp),
      max_devices: session.maxDevices,
    });
  }

  return json({ message: "Acción no válida." });
}

async function handlePatchIndex(env, request) {
  const saved = await readSession(request);
  if (!saved) return json({ error: "A valid RX7 session token is required." }, 401);
  const index = await env.PATCHES.get("index", "json");
  const resources = Array.isArray(index?.resources)
    ? index.resources
    : PATCH_IDS.map((id) => ({ id }));
  return json({ resources });
}

async function handlePatchResource(env, request, id) {
  const saved = await readSession(request);
  if (!saved) return json({ error: "A valid RX7 session token is required." }, 401);
  const key = id.replace(/\.r7v$/i, "");
  const data = await env.PATCHES.get("p:" + key, "arrayBuffer");
  if (!data) return json({ error: "Not found." }, 404);
  return new Response(data, {
    status: 200,
    headers: {
      "content-type": "application/vnd.rx7.patch-resource",
      "content-length": String(data.byteLength),
      "cache-control": "no-store",
      ...CORS,
    },
  });
}

async function handleKeys(env, request, url) {
  if (request.method !== "GET") return json({ message: "method not allowed" }, 405);
  if (!(await allowDb(env, "keys", clientIP(request), 60, 60))) {
    return json({ message: "rate limited" }, 429);
  }
  const keyValue = eqValue(url.searchParams, "key_value");
  const id = eqValue(url.searchParams, "id");

  if (keyValue) {
    const resolved = await resolveKey(env, keyValue, request);
    if (!resolved || !resolved.keyId) return json([]);
    return json([resolvedRow(resolved, keyValue)]);
  }

  if (id) {
    const row = await dbKeyById(env, id);
    if (!row) return json([]);
    return json([rowFromDb(row)]);
  }

  return json([]);
}

async function handleKeyDevices(env, request, url) {
  if (!(await allowDb(env, "key-devices", clientIP(request), 60, 60))) {
    return json({ message: "rate limited" }, 429);
  }
  if (request.method === "GET") {
    const keyId = Number(eqValue(url.searchParams, "key_id"));
    if (!Number.isFinite(keyId)) return json([]);
    const rows = await env.DB.prepare(
      "SELECT id,key_id,device_hash,first_seen_at,last_seen_at FROM global_key_devices WHERE key_id=?1 AND target=?2 ORDER BY first_seen_at ASC"
    )
      .bind(keyId, TARGET)
      .all();
    return json(
      (rows.results || []).map((d) => ({
        id: String(d.id),
        key_id: String(d.key_id),
        // The full hash identifies a physical device; the panel only needs to
        // tell rows apart, so an unauthenticated read gets a short prefix.
        device_id: maskDevice(d.device_hash),
        last_seen: iso(d.last_seen_at),
        created_at: iso(d.first_seen_at),
        is_banned: false,
        is_suspended: false,
        suspended_until: null,
        suspension_reason: null,
      }))
    );
  }

  if (request.method === "POST") {
    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ message: "invalid json" }, 400);
    }
    const items = (Array.isArray(payload) ? payload : [payload]).slice(0, 10);
    for (const item of items) {
      const keyId = Number(item.key_id);
      const deviceId = String(item.device_id || "").trim().slice(0, 128);
      if (!Number.isFinite(keyId) || deviceId.length < 8) continue;

      const key = await env.DB.prepare(
        "SELECT g.id,g.max_devices,g.status,g.expires_at FROM global_keys g JOIN projects p ON p.id=g.project_id WHERE g.id=?1 AND p.slug=?2"
      )
        .bind(keyId, PROJECT_SLUG)
        .first();
      if (!key) return json({ message: "unknown key" }, 403);
      // Binding a device to a revoked or expired key used to work, which let a
      // caller burn every device slot on a dead account.
      const live = String(key.status) === "active"
        && Number(key.expires_at) > Math.floor(Date.now() / 1000);
      if (!live) return json({ message: "inactive key" }, 403);

      const existing = await env.DB.prepare(
        "SELECT id FROM global_key_devices WHERE key_id=?1 AND device_hash=?2 AND target=?3"
      )
        .bind(keyId, deviceId, TARGET)
        .first();

      if (!existing && Number(key.max_devices) > 0) {
        const count = await env.DB.prepare(
          "SELECT COUNT(*) AS n FROM global_key_devices WHERE key_id=?1 AND target=?2"
        )
          .bind(keyId, TARGET)
          .first();
        if (Number(count?.n || 0) >= Number(key.max_devices)) {
          return json({ message: "device limit reached" }, 409);
        }
      }

      const seen = epoch(item.last_seen);
      await env.DB.prepare(
        "INSERT INTO global_key_devices(key_id,device_hash,target,first_seen_at,last_seen_at) VALUES (?1,?2,?3,?4,?4) ON CONFLICT(key_id,device_hash,target) DO UPDATE SET last_seen_at=excluded.last_seen_at"
      )
        .bind(keyId, deviceId, TARGET, seen)
        .run();
    }
    return empty(201);
  }

  return json({ message: "method not allowed" }, 405);
}

async function handleAccessLogs(env, request) {
  if (request.method !== "POST") return json({ message: "method not allowed" }, 405);
  if (!(await allowDb(env, "access-log", clientIP(request), 120, 60))) {
    return json({ message: "rate limited" }, 429);
  }
  let payload;
  try {
    payload = await request.json();
  } catch {
    return empty(201);
  }
  const items = (Array.isArray(payload) ? payload : [payload]).slice(0, 20);
  for (const item of items) {
    // Never persist the key itself. The reference is enough to correlate a
    // device with its log lines and is worthless without ACCESS_LOG_PEPPER.
    const reference = await accessLogRef(env, item.key_value);
    await env.DB.prepare(
      "INSERT INTO access_logs(key_value,device_id,action,created_at) VALUES (?1,?2,?3,?4)"
    )
      .bind(
        reference,
        String(item.device_id || "").slice(0, 128),
        String(item.action || "").slice(0, 64),
        Math.floor(Date.now() / 1000)
      )
      .run();
  }
  return empty(201);
}

async function appConfigRow(env) {
  let row = null;
  try {
    row = await env.DB.prepare("SELECT * FROM app_config WHERE id=1").first();
  } catch {
    row = null;
  }
  return {
    id: 1,
    maintenance_mode: Boolean(row?.maintenance_mode),
    maintenance_message: row?.maintenance_message || "",
    app_title: row?.app_title ?? null,
    app_subtitle: row?.app_subtitle ?? null,
    online_text: row?.online_text ?? null,
    footer_text: row?.footer_text ?? null,
    updated_at: row?.updated_at ? iso(row.updated_at) : iso(Math.floor(Date.now() / 1000)),
  };
}

async function handleAppConfig(env) {
  return json([await appConfigRow(env)]);
}

function panelPatch(row, origin) {
  return {
    id: row.id,
    patch_key: row.patch_key,
    display_name: row.display_name,
    patch_filename: row.patch_filename,
    category: row.category,
    mode: row.mode,
    icon: row.icon,
    download_url: `${origin}/patches/${row.id}.3105`,
    file_hash: row.file_hash,
    file_size: row.file_size,
    version: row.version,
    is_active: true,
    is_blocked: row.is_blocked,
    block_message: row.block_message,
    sort_order: row.sort_order,
  };
}

async function handlePanelPatches(request, url) {
  let rows = PANEL_PATCHES.map((row) => panelPatch(row, url.origin));
  if (url.searchParams.get("is_active") === "eq.true") {
    rows = rows.filter((row) => row.is_active);
  }
  if (url.searchParams.get("order") === "sort_order.asc") {
    rows = rows.slice().sort((a, b) => a.sort_order - b.sort_order);
  }
  return json(rows);
}

async function handlePanelPatchBlob(env, id) {
  const row = PANEL_PATCHES.find((item) => item.id === id);
  if (!row) return json({ message: "not found" }, 404);
  const data = await env.PATCHES.get("p3105:" + id, "arrayBuffer");
  if (!data) return json({ message: "not found" }, 404);
  if (data.byteLength !== row.file_size) {
    return json({ message: "size mismatch" }, 500);
  }
  return new Response(data, {
    status: 200,
    headers: {
      "content-type": "application/octet-stream",
      "content-length": String(data.byteLength),
      "cache-control": "no-store",
      ...CORS,
    },
  });
}

async function proxyLegacy(env, request) {
  const target = new URL(request.url);
  const base = env.LEGACY_SUPABASE_URL || LEGACY_BASE;
  const upstream = new URL(target.pathname + target.search, base);
  const headers = {
    apikey: env.LEGACY_SUPABASE_ANON || LEGACY_ANON,
    authorization: "Bearer " + (env.LEGACY_SUPABASE_ANON || LEGACY_ANON),
    accept: "application/json",
  };
  try {
    const response = await fetch(upstream.toString(), { headers });
    if (!response.ok) return json([]);
    return new Response(await response.text(), {
      status: 200,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...CORS },
    });
  } catch {
    return json([]);
  }
}

function rtRecord(row) {
  return {
    id: row.id,
    // The realtime socket is reachable by anyone holding the public anon key.
    // It gets no key material and no hint, only the state the panel renders.
    key_value: "",
    is_active: Boolean(row.is_active),
    is_banned: Boolean(row.is_banned),
    expires_at: row.expires_at || null,
    max_devices: Number(row.max_devices || 0),
  };
}

async function realtime(request, env) {
  if (request.headers.get("Upgrade") !== "websocket") {
    return new Response("expected websocket", { status: 426, headers: CORS });
  }
  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];
  server.accept();

  const send = (obj) => {
    try {
      server.send(JSON.stringify(obj));
    } catch {
      /* socket already closed */
    }
  };

  server.addEventListener("message", async (event) => {
    let msg;
    try {
      msg = JSON.parse(String(event.data));
    } catch {
      return;
    }
    const topic = String(msg.topic || "");
    const ref = msg.ref ?? null;

    if (msg.event === "heartbeat") {
      send({ topic: "phoenix", ref, event: "phx_reply", payload: { status: "ok", response: {} } });
      return;
    }

    if (msg.event === "phx_join") {
      const isKeys = topic.includes("realtime:public:keys");
      const isConfig = topic.includes("realtime:public:app_config");
      const changes = [];
      if (isKeys) changes.push({ id: 1, event: "*", schema: "public", table: "keys", filter: "id=eq." + topic.split("id=eq.")[1] });
      if (isConfig) changes.push({ id: 2, event: "*", schema: "public", table: "app_config", filter: "id=eq.1" });
      if (topic.includes("realtime:public:announcements"))
        changes.push({ id: 3, event: "*", schema: "public", table: "announcements", filter: null });

      send({
        topic,
        ref,
        event: "phx_reply",
        payload: { status: "ok", response: { postgres_changes: changes } },
      });

      try {
        if (isKeys) {
          const id = topic.split("id=eq.")[1];
          if (id) {
            const row = await dbKeyById(env, id);
            if (row) {
              const record = rtRecord(rowFromDb(row));
              send({
                topic,
                ref: null,
                event: "postgres_changes",
                payload: { data: { type: "UPDATE", record, old_record: record } },
              });
            }
          }
        } else if (isConfig) {
          const config = (await handleAppConfig(env).then((r) => r.json()))[0];
          send({
            topic,
            ref: null,
            event: "postgres_changes",
            payload: { data: { type: "UPDATE", record: config, old_record: config } },
          });
        }
      } catch {
        /* initial snapshot is best effort */
      }
      return;
    }
  });

  server.addEventListener("close", () => {
    try {
      server.close();
    } catch {
      /* already closed */
    }
  });

  return new Response(null, { status: 101, webSocket: client });
}

export default {
  async fetch(request, env) {
    try {
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
      const url = new URL(request.url);
      console.log(
        "REQ",
        request.method,
        url.pathname + redactQuery(url),
        request.headers.get("user-agent") || ""
      );

      // Every panel route used to answer without a credential, including the
      // realtime socket and the device table. The client already sends the
      // Supabase apikey on each call, so requiring it costs nothing and keeps
      // anonymous scanners out.
      const guarded = url.pathname.startsWith("/rest/v1/")
        || url.pathname.startsWith("/realtime/")
        || url.pathname.startsWith("/patches/");
      if (guarded && !panelKeyAccepted(env, panelKeyFrom(request, url))) {
        return json({ message: "apikey required" }, 401);
      }

      if (url.pathname === "/health") {
        return json({ status: "ok", service: "3105-supabase-adapter", project: PROJECT_SLUG, build: "rx7-jvztxn" });
      }
      if (url.pathname === "/realtime/v1/websocket") return realtime(request, env);

      if (url.pathname === "/functions/v1/moon-auth") return handleMoonAuth(env, request);
      if (url.pathname === "/v1/patches") return handlePatchIndex(env, request);
      if (url.pathname.startsWith("/v1/patches/")) {
        return handlePatchResource(env, request, url.pathname.slice("/v1/patches/".length));
      }      if (url.pathname === "/rest/v1/keys") return handleKeys(env, request, url);
      if (url.pathname === "/rest/v1/key_devices") return handleKeyDevices(env, request, url);
      if (url.pathname === "/rest/v1/access_logs") return handleAccessLogs(env, request);
      if (url.pathname === "/rest/v1/app_config") return handleAppConfig(env);
      if (url.pathname === "/rest/v1/patches") return handlePanelPatches(request, url);
      if (url.pathname.startsWith("/patches/")) {
        const id = url.pathname.slice("/patches/".length).replace(/\.3105$/i, "");
        return handlePanelPatchBlob(env, id);
      }
      // The legacy project carried third-party pop-ups.  The panel stays clean.
      if (url.pathname === "/rest/v1/announcements") return json([]);

      return json({ message: "not found" }, 404);
    } catch (error) {
      return json({ message: "server error", detail: String(error?.message || error) }, 500);
    }
  },
};
