// ffhub on Cloudflare: static panel, provider lookup, outfit assembly and the
// finished GLB, all in the Worker. No VPS behind it.
//
// The provider key is a Worker secret and never reaches the browser. Assembly
// is synchronous because a merge of these files is milliseconds: there is no
// queue, and the finished GLB is cached by its reuse key so two players with
// the same outfit get one file.
//
// The edge is deliberately narrow: fixed routes, JSON-only mutations from this
// origin, a body cap, and security headers on everything.

import { assembleOutfit, AssembleFailure, loadIndex } from "./lib/assemble.js";
import {
  fetchImage,
  fetchProfile,
  PROVIDER_BASE,
  ProviderFailure,
  providerRegion,
} from "./lib/provider.js";
import { limiter, memoryStore } from "./lib/ratelimit.js";
import {
  clearedSessionCookie,
  constantTimeEqual,
  hashedClient,
  mintSession,
  parseCookies,
  secretIsUsable,
  sessionCookie,
  SESSION_COOKIE,
  verifySession,
} from "./lib/session.js";

const API_ROUTES = [
  { method: "POST", pattern: /^\/api\/profile$/ },
  { method: "GET", pattern: /^\/api\/thumbnail\/[0-9]{4,20}$/ },
  { method: "POST", pattern: /^\/api\/jobs$/ },
  // The download URL names the outfit, so the GLB can be rebuilt on demand
  // instead of depending on a cache entry surviving between requests.
  { method: "GET", pattern: /^\/api\/outfits\/[^/]{1,128}\/[^/]{1,2048}\.glb$/ },
];

const UID_PATTERN = /^[0-9]{5,15}$/;
const ITEM_PATTERN = /^[0-9]{4,20}$/;

// A lookup carries a uid, a region and a list of ids. Exports post the same
// thing plus the avatar they are rebuilding.
const MAX_BODY_BYTES = 8 * 1024;
const EXPORTER_VERSION = "panel-1";

// A provider lookup costs money, so /api/jobs is capped twice: per client and
// for the whole day. Both counters live in D1 so they hold across isolates.
const JOBS_PER_CLIENT_HOUR = 12;
const JOBS_PER_DAY = 400;
const PROFILE_PER_CLIENT_MINUTE = 30;
const THUMBNAIL_PER_CLIENT_MINUTE = 120;
// The admin password is the only guessable secret here: five tries a minute.
const LOGIN_PER_CLIENT_MINUTE = 5;

const ADMIN_SESSION_SECONDS = 8 * 60 * 60;
const MAX_SESSION_SECONDS = 15 * 60;

const SECURITY_HEADERS = {
  "content-security-policy": [
    "default-src 'self'",
    "script-src 'self' https://unpkg.com",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    // model-viewer hands GLB-embedded textures to GLTFLoader as blob URLs; with
    // 'self' alone they are refused and the model renders untextured white.
    "connect-src 'self' blob:",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join("; "),
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
  "cross-origin-opener-policy": "same-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=()",
};

let indexPromise = null;

function harden(response, extra = {}) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries({ ...SECURITY_HEADERS, ...extra })) {
    headers.set(name, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function json(body, status = 200) {
  return harden(Response.json(body, { status }), { "cache-control": "no-store" });
}

function deny(status, error, extra) {
  return harden(Response.json({ error }, { status }), extra);
}

// --- the gate --------------------------------------------------------------
//
// The panel is private. Everything below this line runs only for a request
// carrying a session cookie signed with PANEL_TOKEN_KEY, which never ships in
// the app: a cracked IPA has the URL and nothing to sign with. The only public
// surfaces are the login screen and /api/session itself.

function panelSecret(env) {
  return secretIsUsable(env.PANEL_TOKEN_KEY) ? String(env.PANEL_TOKEN_KEY) : null;
}

async function currentSession(request, env) {
  const secret = panelSecret(env);
  if (!secret) return null;
  const token = parseCookies(request.headers.get("cookie")).get(SESSION_COOKIE);
  if (!token) return null;
  return await verifySession({ secret, token });
}

function clientAddress(request) {
  return String(request.headers.get("cf-connecting-ip") || "");
}

// One limiter per environment: the D1 handle and the table check are memoised,
// so a burst does not run the DDL every time. Keyed by env rather than by
// module, because a test (or a route with different bindings) must not inherit
// the counters of another.
const limitersByEnv = new WeakMap();
function limitStore(env) {
  let store = limitersByEnv.get(env);
  if (!store) {
    store = limiter({
      db: env.DB,
      fallback: memoryStore(),
      onFallback: () => console.warn("ffhub: D1 unavailable, rate limits are per-isolate"),
    });
    limitersByEnv.set(env, store);
  }
  return store;
}

// A deployment can tighten or loosen a quota without a code change; a missing
// or nonsense value falls back to the constant above.
function limitFrom(env, name, fallback) {
  const value = Number(env?.[name]);
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

async function checkLimit(env, request, name, limit, windowSeconds) {
  const who = await hashedClient(panelSecret(env) || "ffhub-rate-limit", clientAddress(request));
  return await limitStore(env).consume({
    bucket: `${name}:${who}`,
    limit,
    windowSeconds,
  });
}

function tooMany(result) {
  return deny(429, "rate_limited", { "retry-after": String(result.retryAfter) });
}

function loginPage(env, { error = "", status = 200 } = {}) {
  const ready = panelSecret(env)
    ? ""
    : `<p class="warn">Falta PANEL_TOKEN_KEY en los secretos del sitio: nadie puede entrar.</p>`;
  const admin = secretIsUsable(env.PANEL_ADMIN_PASSWORD, 12)
    ? `<form method="post" action="/api/session">
      <label>Contraseña de administrador
        <input type="password" name="admin" autocomplete="current-password" required />
      </label>
      <button type="submit">Entrar como dueño</button>
    </form>`
    : `<p class=\"hint\">El acceso de administrador está desactivado: no hay PANEL_ADMIN_PASSWORD configurada.</p>`;
  const body = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex, nofollow" />
<title>FFHub — acceso</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%23ff7a2f'/%3E%3C/svg%3E" />
<style>
:root{color-scheme:dark}body{margin:0;background:#0d0f12;color:#e8eaed;font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:420px;margin:0 auto;padding:48px 20px}
h1{margin:0 0 4px;font-size:24px}
p{color:#98a1ac;margin:0 0 16px}
form{margin:0 0 20px;padding:16px;border:1px solid #262b33;border-radius:12px;background:#16191e}
label{display:block;margin-bottom:10px;font-size:13px;color:#98a1ac}
input{width:100%;margin-top:6px;padding:10px 12px;border-radius:8px;border:1px solid #262b33;background:#0d0f12;color:#e8eaed;font:inherit}
button{width:100%;padding:11px 14px;border:0;border-radius:8px;background:#e6753a;color:#14100d;font:inherit;font-weight:600}
.error{color:#ff9b7a}
.warn{color:#ff9b7a;font-size:13px}
.hint{font-size:13px}
</style>
</head>
<body>
<main>
<h1>FFHub</h1>
<p>Panel privado. Entra desde la app o con la contraseña de administrador.</p>
${error ? `<p class="error">${error}</p>` : ""}
${ready}
<form method="post" action="/api/session">
  <label>Token de sesión de la app
    <input type="text" name="token" autocomplete="off" spellcheck="false" placeholder="v1…" required />
  </label>
  <button type="submit">Entrar</button>
</form>
${admin}
</main>
</body>
</html>`;
  return harden(
    new Response(body, {
      status,
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
    }),
  );
}

function redirectTo(path, cookie) {
  return harden(new Response(null, { status: 303, headers: { location: path, "set-cookie": cookie } }), {
    "cache-control": "no-store",
  });
}

async function readFields(request) {
  const capped = await boundedBody(request, 4 * 1024);
  if (capped.tooLarge || !capped.body) return {};
  const text = new TextDecoder().decode(capped.body);
  const type = String(request.headers.get("content-type") || "").toLowerCase();
  if (type.includes("application/json")) {
    try {
      const parsed = JSON.parse(text);
      return parsed && typeof parsed === "object" ? parsed : {};
    } catch {
      return {};
    }
  }
  const fields = {};
  for (const [name, value] of new URLSearchParams(text)) fields[name] = value;
  return fields;
}

async function handleSession(request, env) {
  const method = request.method.toUpperCase();
  const secret = panelSecret(env);

  if (method === "GET") {
    const claims = await currentSession(request, env);
    if (!claims) return deny(401, "session_required");
    return json({
      active: true,
      role: claims.role,
      expires_at: new Date(claims.expiresAt * 1000).toISOString(),
    });
  }

  if (method === "DELETE") {
    return harden(new Response(null, { status: 204, headers: { "set-cookie": clearedSessionCookie() } }));
  }

  // POST: the login form and the app's one-shot link both land here.
  if (!secret) {
    return loginPage(env, { status: 503, error: "El panel no tiene PANEL_TOKEN_KEY configurada." });
  }
  const attempt = await checkLimit(
    env,
    request,
    "login",
    limitFrom(env, "LOGIN_PER_CLIENT_MINUTE", LOGIN_PER_CLIENT_MINUTE),
    60,
  );
  if (!attempt.ok) {
    const page = loginPage(env, { status: 429, error: "Demasiados intentos. Espera un minuto." });
    page.headers.set("retry-after", String(attempt.retryAfter));
    return page;
  }

  const fields = await readFields(request);
  const password = String(fields.admin || "");
  if (password) {
    if (!secretIsUsable(env.PANEL_ADMIN_PASSWORD, 12) || !constantTimeEqual(password, env.PANEL_ADMIN_PASSWORD)) {
      return loginPage(env, { status: 401, error: "Contraseña incorrecta." });
    }
    const session = await mintSession({
      secret,
      subject: "owner",
      role: "admin",
      ttlSeconds: ADMIN_SESSION_SECONDS,
    });
    return redirectTo("/", sessionCookie(session.token, ADMIN_SESSION_SECONDS));
  }

  const token = String(fields.token || "").trim();
  const claims = token ? await verifySession({ secret, token }) : null;
  if (!claims) {
    return loginPage(env, { status: 401, error: "Ese token no es válido o ya caducó. Ábrelo de nuevo desde la app." });
  }
  const ttl = Math.min(MAX_SESSION_SECONDS, Math.max(60, claims.expiresAt - Math.floor(Date.now() / 1000)));
  return redirectTo("/", sessionCookie(token, ttl));
}

function apiBase(env) {
  return env.FIRE_API_BASE || PROVIDER_BASE;
}

function cacheAvailable() {
  return typeof caches !== "undefined" && Boolean(caches.default);
}

// The Cache API only takes requests for this Worker's own origin; a synthetic
// hostname throws and would turn a cache miss into a 502.
function cacheRequest(origin, path) {
  return new Request(new URL(path, origin));
}

function catalogIndex(env) {
  if (!indexPromise) {
    indexPromise = loadIndex(env.ASSETS).catch((error) => {
      indexPromise = null;
      throw error;
    });
  }
  return indexPromise;
}

async function reuseKey({ avatarId, items, catalogVersion }) {
  const canonical = [...new Set(items.map((item) => String(item).trim()).filter(Boolean))].sort();
  const text = [
    `avatar=${avatarId}`,
    `items=${canonical.join(",")}`,
    `catalog=${catalogVersion}`,
    `exporter=${EXPORTER_VERSION}`,
  ].join("\n");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function providerError(error) {
  if (!(error instanceof ProviderFailure)) throw error;
  const status =
    {
      invalid_region: 400,
      profile_not_found: 404,
      image_unavailable: 404,
      provider_rate_limited: 429,
      provider_auth: 502,
      provider_bad_response: 502,
    }[error.code] ?? 502;
  const headers = {};
  if (error.code === "provider_rate_limited") {
    headers["retry-after"] = String(Math.ceil(error.retryAfter || 5));
  }
  // Same envelope as the FastAPI service: {detail: {error}}.
  return harden(Response.json({ detail: { error: error.code } }, { status }), headers);
}

function parseJson(bytes) {
  if (!bytes || bytes.byteLength === 0) return deny(411, "length_required");
  let value;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return deny(400, "invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return deny(400, "invalid_body");
  }
  return value;
}

async function handleProfile(payload, env) {
  const body = parseJson(payload);
  if (body instanceof Response) return body;

  const uid = String(body.uid ?? "").trim();
  if (!UID_PATTERN.test(uid)) return deny(400, "invalid_uid");
  const region = String(body.region ?? "").trim();
  try {
    providerRegion(region);
  } catch {
    return deny(400, "invalid_region");
  }
  if (!env.FREE_FIRE_API_KEY) return deny(503, "provider_not_configured");

  let profile;
  try {
    profile = await fetchProfile({
      apiKey: env.FREE_FIRE_API_KEY,
      apiBase: apiBase(env),
      uid,
      region,
    });
  } catch (error) {
    return providerError(error);
  }

  const index = await catalogIndex(env);
  const clothes = (profile.clothes ?? []).map((itemId) => {
    const piece = index.pieces[itemId];
    return {
      item_id: itemId,
      type: piece?.type ?? "unknown",
      label: piece?.label ?? "",
      in_catalog: Boolean(piece),
      thumbnail_url: `/api/thumbnail/${itemId}`,
    };
  });

  return json({
    uid: profile.uid,
    nickname: profile.nickname,
    region: profile.region,
    requested_region: region.toLowerCase(),
    avatar_id: profile.avatarId,
    avatar_in_catalog: Boolean(index.bodies[profile.avatarId]),
    clothes,
    clothes_state: profile.clothesState,
    catalog_version: index.version ?? "",
    catalog_problems: [],
  });
}

async function handleJob(payload, env) {
  const body = parseJson(payload);
  if (body instanceof Response) return body;

  const uid = String(body.uid ?? "").trim();
  if (!UID_PATTERN.test(uid)) return deny(400, "invalid_uid");
  const region = String(body.region ?? "").trim();
  try {
    providerRegion(region);
  } catch {
    return deny(400, "invalid_region");
  }

  const index = await catalogIndex(env);
  let avatarId = String(body.avatar_id ?? "").trim();
  let items = Array.isArray(body.items) ? body.items.map((item) => String(item).trim()) : null;

  if (avatarId && items) {
    // A rebuild names a body and items the catalog already knows, so these are
    // trusted config rather than provider input: only shape is checked, and an
    // unknown id comes back as `partial` instead of an error.
    if (items.some((item) => !item || item.length > 64)) return deny(400, "invalid_item_id");
  } else {
    if (!env.FREE_FIRE_API_KEY) return deny(503, "provider_not_configured");
    let profile;
    try {
      profile = await fetchProfile({
        apiKey: env.FREE_FIRE_API_KEY,
        apiBase: apiBase(env),
        uid,
        region,
      });
    } catch (error) {
      return providerError(error);
    }
    if (profile.clothesState !== "available") {
      return deny(409, `clothes_${profile.clothesState}`);
    }
    avatarId = profile.avatarId;
    items = profile.clothes;
  }

  if (!index.bodies[avatarId]) return deny(400, "avatar_not_in_catalog");

  let result;
  try {
    result = await assembleOutfit({ assets: env.ASSETS, index, avatarId, items });
  } catch (error) {
    if (error instanceof AssembleFailure) return deny(400, error.code);
    throw error;
  }

  const key = await reuseKey({ avatarId, items, catalogVersion: index.version || "1" });
  const outfitPath = `/outfits/${encodeURIComponent(avatarId)}/${encodeURIComponent(items.join(","))}.glb`;

  return json({
    job: {
      id: key,
      state: result.state,
      detail: result.detail,
      progress: 1,
      download_url: outfitPath,
      mounted: result.mounted,
      missing: result.missing,
    },
  });
}

async function handleThumbnail(itemId, env, origin) {
  if (!ITEM_PATTERN.test(itemId)) return deny(400, "invalid_item_id");
  if (!env.FREE_FIRE_API_KEY) return deny(503, "provider_not_configured");

  const request = cacheRequest(origin, `/__cache/thumbs/${itemId}`);
  if (cacheAvailable()) {
    try {
      const hit = await caches.default.match(request);
      if (hit) return harden(hit.clone());
    } catch {
      // Same rule as files: an unreadable cache is a miss.
    }
  }

  let image;
  try {
    image = await fetchImage({ apiKey: env.FREE_FIRE_API_KEY, apiBase: apiBase(env), itemId });
  } catch (error) {
    return providerError(error);
  }

  const response = new Response(image.bytes, {
    headers: { "content-type": image.contentType, "cache-control": "public, max-age=86400" },
  });
  if (cacheAvailable()) {
    try {
      await caches.default.put(request, response.clone());
    } catch {
      // Best effort.
    }
  }
  return harden(response);
}

/**
 * Rebuild from the URL. The outfit is fully described by the avatar and the
 * item ids, so an identical URL is always an identical file: no storage, no
 * stale cache, and a shared link keeps working.
 */
async function handleOutfit(pathname, env) {
  const rest = pathname.slice("/api/outfits/".length);
  const separator = rest.indexOf("/");
  if (separator < 0) return deny(404, "not_found");

  let avatarId;
  let itemList;
  try {
    avatarId = decodeURIComponent(rest.slice(0, separator));
    itemList = decodeURIComponent(rest.slice(separator + 1).replace(/\.glb$/, ""));
  } catch {
    return deny(400, "invalid_item_id");
  }

  const itemIds = itemList.split(",").filter(Boolean);
  if (!avatarId || avatarId.length > 64) return deny(400, "invalid_avatar_id");
  if (itemIds.length === 0 || itemIds.length > 32) return deny(400, "invalid_item_id");
  if (itemIds.some((item) => item.length > 64)) return deny(400, "invalid_item_id");

  const index = await catalogIndex(env);
  if (!index.bodies[avatarId]) return deny(404, "avatar_not_in_catalog");

  let result;
  try {
    result = await assembleOutfit({ assets: env.ASSETS, index, avatarId, items: itemIds });
  } catch (error) {
    if (error instanceof AssembleFailure) return deny(400, error.code);
    throw error;
  }

  const key = await reuseKey({ avatarId, items: itemIds, catalogVersion: index.version || "1" });
  return harden(
    new Response(result.bytes, {
      status: 200,
      headers: {
        "content-type": "model/gltf-binary",
        "content-disposition": `attachment; filename="${key}.glb"`,
        "cache-control": "public, max-age=86400",
      },
    }),
  );
}

/**
 * Read the body without trusting its size. A declared content-length is
 * checked; a chunked client sends none, so the stream is read up to the cap
 * instead of being forwarded unbounded.
 */
async function boundedBody(request, cap = MAX_BODY_BYTES) {
  const declared = Number(request.headers.get("content-length") ?? "");
  if (Number.isFinite(declared) && declared > cap) {
    return { tooLarge: true };
  }
  if (declared > 0) return { body: new Uint8Array(await request.arrayBuffer()) };

  const reader = request.body?.getReader();
  if (!reader) return { body: null };
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > cap) {
      await reader.cancel();
      return { tooLarge: true };
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { body };
}

function routeState(method, pathname) {
  for (const route of API_ROUTES) {
    if (!route.pattern.test(pathname)) continue;
    return route.method === method ? "allowed" : "wrong_method";
  }
  return "unknown";
}



export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();
    const path = url.pathname;

    // Public surfaces: the login screen and the session endpoint. Nothing else.
    if (path === "/login" && method === "GET") return loginPage(env);
    if (path === "/api/session") return await handleSession(request, env);

    const claims = await currentSession(request, env);
    if (!claims) {
      if (path.startsWith("/api/")) return deny(401, "session_required");
      // A bare link lands on the login screen instead of the catalog.
      return loginPage(env);
    }

    if (!path.startsWith("/api/")) {
      return harden(await env.ASSETS.fetch(request));
    }

    const state = routeState(method, path);
    if (state === "unknown") return deny(404, "not_found");
    if (state === "wrong_method") return deny(405, "method_not_allowed");

    let payload = null;
    if (method !== "GET") {
      if (request.headers.get("origin") !== url.origin) {
        return deny(403, "forbidden_origin");
      }
      const sized = await boundedBody(request);
      if (sized.tooLarge) return deny(413, "body_too_large");
      if (sized.body === null || sized.body.byteLength === 0) {
        return deny(411, "length_required");
      }
      payload = sized.body;
    }

    // Quotas. A lookup is the only thing here that spends the provider key, so
    // /api/jobs is capped per client and for the whole day; the rest only have
    // to stop a loop.
    if (path === "/api/jobs") {
      const perClient = await checkLimit(
        env,
        request,
        "jobs-client",
        limitFrom(env, "JOBS_PER_CLIENT_HOUR", JOBS_PER_CLIENT_HOUR),
        3600,
      );
      if (!perClient.ok) return tooMany(perClient);
      const global = await limitStore(env).consume({
        bucket: "jobs-day",
        limit: limitFrom(env, "JOBS_PER_DAY", JOBS_PER_DAY),
        windowSeconds: 86_400,
      });
      if (!global.ok) return tooMany(global);
    } else if (path === "/api/profile") {
      const result = await checkLimit(
        env,
        request,
        "profile-client",
        limitFrom(env, "PROFILE_PER_CLIENT_MINUTE", PROFILE_PER_CLIENT_MINUTE),
        60,
      );
      if (!result.ok) return tooMany(result);
    } else if (path.startsWith("/api/thumbnail/")) {
      const result = await checkLimit(
        env,
        request,
        "thumb-client",
        limitFrom(env, "THUMBNAIL_PER_CLIENT_MINUTE", THUMBNAIL_PER_CLIENT_MINUTE),
        60,
      );
      if (!result.ok) return tooMany(result);
    } else if (path.startsWith("/api/outfits/")) {
      const result = await checkLimit(
        env,
        request,
        "outfit-client",
        limitFrom(env, "OUTFIT_PER_CLIENT_MINUTE", THUMBNAIL_PER_CLIENT_MINUTE),
        60,
      );
      if (!result.ok) return tooMany(result);
    }

    try {
      if (path === "/api/profile") return await handleProfile(payload, env);
      if (path === "/api/jobs") return await handleJob(payload, env);
      if (path.startsWith("/api/outfits/")) return await handleOutfit(path, env);
      if (path.startsWith("/api/thumbnail/")) {
        return await handleThumbnail(path.slice("/api/thumbnail/".length), env, url.origin);
      }
    } catch (error) {
      if (error instanceof AssembleFailure) return deny(400, error.code);
      return deny(502, "internal_error");
    }

    return deny(404, "not_found");
  },
};
