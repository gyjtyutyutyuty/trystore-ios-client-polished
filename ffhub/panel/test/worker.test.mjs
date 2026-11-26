// Run with: node --test panel/test/worker.test.mjs
//
// The provider is stubbed at globalThis.fetch, so these never touch the
// network. The catalog is a two-entry index with body-free GLBs: enough to
// exercise the routing, the merge and the file cache.

import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import worker from "../worker.js";
import { buildGlb, parseGlb } from "../lib/glb.js";
import { mintSession, SESSION_COOKIE } from "../lib/session.js";

const ORIGIN = "https://panel.example";
const realFetch = globalThis.fetch;

// The panel is private, so every request in this file carries a session unless
// the test is specifically about the gate (`omitSession`).
const PANEL_KEY = "test-panel-key-0123456789abcdef0123456789";
const ADMIN_PASSWORD = "admin-password-123456";
const SESSION = await mintSession({
  secret: PANEL_KEY,
  subject: "test-device",
  role: "user",
  ttlSeconds: 900,
});
const COOKIE = `${SESSION_COOKIE}=${SESSION.token}`;
const fetchWithSession = worker.fetch.bind(worker);
worker.fetch = (request, environment = {}) => {
  const headers = new Headers(request.headers);
  if (!headers.has("cookie") && !environment.omitSession) headers.set("cookie", COOKIE);
  return fetchWithSession(new Request(request, { headers }), environment);
};

afterEach(() => {
  globalThis.fetch = realFetch;
  delete globalThis.caches;
});

function tinyGlb() {
  const doc = {
    asset: { version: "2.0" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0 }],
    meshes: [{ name: "piece", primitives: [{ attributes: {} }] }],
    buffers: [{ byteLength: 0 }],
  };
  return buildGlb(doc, new Uint8Array(0));
}

const BODY = tinyGlb();
const BOOTS = tinyGlb();

const INDEX = {
  version: "test-1",
  bodies: { "102000015": "catalog/body/102000015/mesh.glb" },
  pieces: {
    "205000070": { type: "feet", mesh: "catalog/feet/205000070/mesh.glb", label: "botas" },
  },
};

function assets() {
  return {
    fetch: async (request) => {
      const path = new URL(request.url).pathname.replace(/^\//, "");
      if (path === "catalog/index.json") {
        return Response.json(INDEX);
      }
      if (path === INDEX.bodies["102000015"]) {
        return new Response(BODY, { headers: { "content-type": "model/gltf-binary" } });
      }
      if (path === INDEX.pieces["205000070"].mesh) {
        return new Response(BOOTS, { headers: { "content-type": "model/gltf-binary" } });
      }
      if (path === "" || path === "index.html") {
        return new Response("<!doctype html>", { headers: { "content-type": "text/html" } });
      }
      return new Response("missing", { status: 404 });
    },
  };
}

function env(overrides = {}) {
  return {
    FREE_FIRE_API_KEY: "provider-key",
    PANEL_TOKEN_KEY: PANEL_KEY,
    PANEL_ADMIN_PASSWORD: ADMIN_PASSWORD,
    ASSETS: assets(),
    ...overrides,
  };
}

function post(path, body = { uid: "11807385", region: "us" }, headers = {}) {
  return new Request(`${ORIGIN}${path}`, {
    method: "POST",
    body: JSON.stringify(body),
    headers: { origin: ORIGIN, "content-type": "application/json", ...headers },
  });
}

function profileResponse(payload, status = 200) {
  globalThis.fetch = async () => Response.json(payload, { status });
}

test("static assets carry the security headers", async () => {
  const response = await worker.fetch(new Request(`${ORIGIN}/`), env());

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "<!doctype html>");
  assert.match(response.headers.get("content-security-policy"), /frame-ancestors 'none'/);
  // GLB textures reach the viewer as blob URLs; without this the model is white.
  assert.match(response.headers.get("content-security-policy"), /connect-src 'self' blob:/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
});

test("a route outside the allowlist is a 404", async () => {
  const response = await worker.fetch(post("/api/admin"), env());

  assert.equal(response.status, 404);
  assert.equal((await response.json()).error, "not_found");
});

test("the wrong method on a known route is a 405", async () => {
  const response = await worker.fetch(new Request(`${ORIGIN}/api/profile`), env());

  assert.equal(response.status, 405);
  assert.equal((await response.json()).error, "method_not_allowed");
});

test("a mutation from another origin is refused", async () => {
  const response = await worker.fetch(
    post("/api/profile", undefined, { origin: "https://evil.example" }),
    env(),
  );

  assert.equal(response.status, 403);
  assert.equal((await response.json()).error, "forbidden_origin");
});

test("a mutation without a body is refused", async () => {
  const request = new Request(`${ORIGIN}/api/profile`, {
    method: "POST",
    headers: { origin: ORIGIN, "content-type": "application/json" },
  });

  const response = await worker.fetch(request, env());

  assert.equal(response.status, 411);
  assert.equal((await response.json()).error, "length_required");
});

test("an oversized body is refused", async () => {
  const response = await worker.fetch(
    post("/api/profile", { uid: "1".repeat(9000), region: "us" }),
    env(),
  );

  assert.equal(response.status, 413);
  assert.equal((await response.json()).error, "body_too_large");
});

test("a bad uid never reaches the provider", async () => {
  globalThis.fetch = async () => {
    throw new Error("should not be called");
  };

  const response = await worker.fetch(post("/api/profile", { uid: "abc", region: "us" }), env());

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "invalid_uid");
});

test("a panel without the provider key says so", async () => {
  const response = await worker.fetch(post("/api/profile"), env({ FREE_FIRE_API_KEY: "" }));

  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "provider_not_configured");
});

test("the profile is answered in the shape the panel reads", async () => {
  profileResponse({
    basicInfo: { accountId: "11807385", nickname: "Carlos", region: "US" },
    profileInfo: { avatarId: "102000015", clothes: [205000070, 999999999] },
  });

  const response = await worker.fetch(post("/api/profile"), env());
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.nickname, "Carlos");
  assert.equal(body.avatar_id, "102000015");
  assert.equal(body.avatar_in_catalog, true);
  assert.equal(body.clothes_state, "available");
  assert.deepEqual(
    body.clothes.map((item) => item.item_id),
    ["205000070", "999999999"],
  );
  assert.equal(body.clothes[0].type, "feet");
  assert.equal(body.clothes[0].in_catalog, true);
  assert.equal(body.clothes[1].in_catalog, false);
  assert.equal(body.clothes[0].thumbnail_url, "/api/thumbnail/205000070");
});

test("a missing player keeps its own error", async () => {
  profileResponse({ detail: { error: "not found" } }, 404);

  const response = await worker.fetch(post("/api/profile"), env());

  assert.equal(response.status, 404);
  assert.equal((await response.json()).detail.error, "profile_not_found");
});

test("a job merges the outfit and serves the file back", async () => {
  const response = await worker.fetch(
    post("/api/jobs", {
      uid: "11807385",
      region: "us",
      avatar_id: "102000015",
      items: ["205000070"],
    }),
    env(),
  );

  assert.equal(response.status, 200);
  const { job } = await response.json();
  assert.equal(job.state, "ready");
  assert.deepEqual(job.mounted, ["205000070"]);
  assert.match(job.download_url, /^\/outfits\/[^/]+\/[^/]+\.glb$/);

  const file = await worker.fetch(new Request(`${ORIGIN}/api${job.download_url}`), env());
  assert.equal(file.status, 200);
  assert.equal(file.headers.get("content-type"), "model/gltf-binary");
  const merged = new Uint8Array(await file.arrayBuffer());
  assert.equal(parseGlb(merged).json.meshes.length, 2);
});

test("an item the catalog does not ship makes the job partial, not broken", async () => {
  const response = await worker.fetch(
    post("/api/jobs", {
      uid: "11807385",
      region: "us",
      avatar_id: "102000015",
      items: ["205000070", "999999999"],
    }),
    env(),
  );

  assert.equal(response.status, 200);
  const { job } = await response.json();
  assert.equal(job.state, "partial");
  assert.deepEqual(job.missing, ["999999999"]);
});

test("an avatar with no body is refused before assembling", async () => {
  const response = await worker.fetch(
    post("/api/jobs", {
      uid: "11807385",
      region: "us",
      avatar_id: "111111111",
      items: ["205000070"],
    }),
    env(),
  );

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "avatar_not_in_catalog");
});

test("the download URL rebuilds the same outfit without any storage", async () => {
  const first = await worker.fetch(
    new Request(`${ORIGIN}/api/outfits/102000015/205000070.glb`),
    env(),
  );
  const second = await worker.fetch(
    new Request(`${ORIGIN}/api/outfits/102000015/205000070.glb`),
    env(),
  );

  assert.equal(first.status, 200);
  const a = new Uint8Array(await first.arrayBuffer());
  const b = new Uint8Array(await second.arrayBuffer());
  assert.deepEqual([...a], [...b]);
  assert.equal(parseGlb(a).json.meshes.length, 2);
});

test("an outfit URL for a body the catalog does not ship is a 404", async () => {
  const response = await worker.fetch(
    new Request(`${ORIGIN}/api/outfits/111111111/205000070.glb`),
    env(),
  );

  assert.equal(response.status, 404);
  assert.equal((await response.json()).error, "avatar_not_in_catalog");
});

test("a cache that throws never turns a thumbnail into a 502", async () => {
  // Cloudflare's Cache API rejects a URL on another origin; on a managed
  // deployment writes can also be refused. Either way it is a miss.
  const seen = [];
  globalThis.caches = {
    default: {
      match: async (request) => {
        seen.push(new URL(request.url).origin);
        throw new Error("cache on foreign origin");
      },
      put: async (request) => {
        seen.push(new URL(request.url).origin);
        throw new Error("cache on foreign origin");
      },
    },
  };
  globalThis.fetch = async () =>
    new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "image/png" } });

  const response = await worker.fetch(new Request(`${ORIGIN}/api/thumbnail/205000070`), env());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/png");
  assert.deepEqual([...new Set(seen)], [ORIGIN]);
});

test("a thumbnail is proxied with its real content type", async () => {
  globalThis.fetch = async () =>
    new Response(new Uint8Array([137, 80, 78, 71]), {
      headers: { "content-type": "image/png" },
    });

  const response = await worker.fetch(new Request(`${ORIGIN}/api/thumbnail/205000070`), env());

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/png");
  assert.equal(response.headers.get("cache-control"), "public, max-age=86400");
});

// --- the gate ---------------------------------------------------------------

test("an anonymous visit gets the login screen, not the panel", async () => {
  const response = await worker.fetch(new Request(`${ORIGIN}/`), { ...env(), omitSession: true });

  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Panel privado/);
  assert.doesNotMatch(html, /Escribe un UID/);
});

test("an anonymous API call is refused before the provider is touched", async () => {
  globalThis.fetch = async () => {
    throw new Error("should not be called");
  };

  const response = await worker.fetch(post("/api/profile"), { ...env(), omitSession: true });

  assert.equal(response.status, 401);
  assert.equal((await response.json()).error, "session_required");
});

test("a forged cookie is refused", async () => {
  const request = new Request(`${ORIGIN}/api/profile`, {
    method: "POST",
    headers: {
      origin: ORIGIN,
      "content-type": "application/json",
      cookie: `ffhub_session=${SESSION.token.slice(0, -6)}AAAAAA`,
    },
    body: JSON.stringify({ uid: "11807385", region: "us" }),
  });

  const response = await worker.fetch(request, env());

  assert.equal(response.status, 401);
});

test("without a signing key nothing is served, and the page says why", async () => {
  const response = await worker.fetch(new Request(`${ORIGIN}/login`), env({ PANEL_TOKEN_KEY: "" }));

  assert.equal(response.status, 200);
  assert.match(await response.text(), /PANEL_TOKEN_KEY/);
});

test("the admin password buys an HttpOnly session", async () => {
  const response = await worker.fetch(
    new Request(`${ORIGIN}/api/session`, {
      method: "POST",
      headers: { origin: ORIGIN, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ admin: ADMIN_PASSWORD }).toString(),
    }),
    { ...env(), omitSession: true },
  );

  assert.equal(response.status, 303);
  const cookie = response.headers.get("set-cookie");
  assert.match(cookie, /ffhub_session=v1\./);
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /Secure/);
  assert.match(cookie, /SameSite=Lax/);
});

test("a wrong admin password is refused without a cookie", async () => {
  const response = await worker.fetch(
    new Request(`${ORIGIN}/api/session`, {
      method: "POST",
      headers: { origin: ORIGIN, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ admin: "not-the-password" }).toString(),
    }),
    { ...env(), omitSession: true },
  );

  assert.equal(response.status, 401);
  assert.equal(response.headers.get("set-cookie"), null);
});

test("a live session reports its role", async () => {
  const response = await worker.fetch(new Request(`${ORIGIN}/api/session`), env());
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.active, true);
  assert.equal(body.role, "user");
});

test("repeated password guesses are throttled", async () => {
  // One environment, so the limiter keeps counting between attempts: that is
  // what a real isolate does.
  const throttled = { ...env(), omitSession: true, LOGIN_PER_CLIENT_MINUTE: 2 };
  const attempt = () =>
    worker.fetch(
      new Request(`${ORIGIN}/api/session`, {
        method: "POST",
        headers: { origin: ORIGIN, "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ admin: "wrong" }).toString(),
      }),
      throttled,
    );

  assert.equal((await attempt()).status, 401);
  assert.equal((await attempt()).status, 401);
  assert.equal((await attempt()).status, 429);
});

test("the hourly job quota is enforced, with retry-after", async () => {
  const limited = env({ JOBS_PER_CLIENT_HOUR: 2 });
  const job = () =>
    worker.fetch(
      post("/api/jobs", {
        uid: "11807385",
        region: "us",
        avatar_id: "102000015",
        items: ["205000070"],
      }),
      limited,
    );

  assert.equal((await job()).status, 200);
  assert.equal((await job()).status, 200);
  const blocked = await job();
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).error, "rate_limited");
  assert.match(blocked.headers.get("retry-after"), /^[0-9]+$/);
});
