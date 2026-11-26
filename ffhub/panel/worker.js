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
const RATE_LIMIT = { max: 60, windowMs: 60_000 };

const SECURITY_HEADERS = {
  "content-security-policy": [
    "default-src 'self'",
    "script-src 'self' https://unpkg.com",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "connect-src 'self'",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join("; "),
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=()",
};

// Per-isolate only: a speed bump against a loop, not a quota. The real limit
// belongs in a Cloudflare WAF rate-limiting rule on /api/jobs.
const buckets = new Map();

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
async function boundedBody(request) {
  const declared = Number(request.headers.get("content-length") ?? "");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
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
    if (total > MAX_BODY_BYTES) {
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

function rateLimited(ip) {
  if (!ip) return false;
  const now = Date.now();
  const bucket = buckets.get(ip);
  if (!bucket || now - bucket.start >= RATE_LIMIT.windowMs) {
    buckets.set(ip, { start: now, count: 1 });
    return false;
  }
  bucket.count += 1;
  if (buckets.size > 10_000) buckets.clear();
  return bucket.count > RATE_LIMIT.max;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();

    if (!url.pathname.startsWith("/api/")) {
      return harden(await env.ASSETS.fetch(request));
    }

    const state = routeState(method, url.pathname);
    if (state === "unknown") return deny(404, "not_found");
    if (state === "wrong_method") return deny(405, "method_not_allowed");

    if (rateLimited(request.headers.get("cf-connecting-ip"))) {
      return deny(429, "rate_limited", { "retry-after": "60" });
    }

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

    try {
      if (url.pathname === "/api/profile") return await handleProfile(payload, env);
      if (url.pathname === "/api/jobs") return await handleJob(payload, env);
      if (url.pathname.startsWith("/api/outfits/")) return await handleOutfit(url.pathname, env);
      if (url.pathname.startsWith("/api/thumbnail/")) {
        return await handleThumbnail(url.pathname.slice("/api/thumbnail/".length), env, url.origin);
      }
    } catch (error) {
      if (error instanceof AssembleFailure) return deny(400, error.code);
      return deny(502, "internal_error");
    }

    return deny(404, "not_found");
  },
};
