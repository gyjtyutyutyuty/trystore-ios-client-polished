/**
 * TryStore patch feed worker.
 *
 * Serves patch manifests and package blobs, and exposes a button-driven
 * Telegram patch manager. Updates publish straight to KV, so the iOS client
 * picks them up on its next sync without a new IPA.
 *
 * Routes
 *   GET  /health
 *   GET  /api/patches/:project/manifest.json
 *   POST /api/patches/trystore/app-attest/challenge
 *   POST /api/patches/trystore/app-attest/register
 *   POST /api/patches/trystore/bundle-key (App Attest assertion, or licence-bound mode)
 *   GET  /patches/:project/:file
 *   POST /api/telegram/webhook
 *
 * Telegram routing
 *   Patch commands and `pm:` callbacks are handled here.
 *   Everything else is forwarded to the existing reseller/license worker, so
 *   the original bot panel keeps working unchanged.
 */

import { Buffer } from "node:buffer";
import { parseBuffer } from "bplist-parser";
import bplist from "bplist-creator";

const PROJECTS = ["trystore", "apple-music", "hyper-regedit"];
const PROJECT_META = {
  trystore: { label: "TryStore", emoji: "🛍️" },
  "apple-music": { label: "Apple Music", emoji: "🎵" },
  "hyper-regedit": { label: "HYperRegedit", emoji: "🧩" },
};
const SESSION_TTL_SECONDS = 900;
const MAX_UPLOAD_BYTES = 24 * 1024 * 1024;
const PATCH_EXTENSIONS = [".trystore", ".3105", ".tipa", ".apple"];
const VAULT_MANIFEST_KEY = "vault/trystore/manifest.json";
const VAULT_BLOB_PREFIX = "vault/trystore/";
const VAULT_ROUTE_PREFIX = "/api/patches/trystore/character-vault/";
const VAULT_BLOB_PATH = /^(?:rouk|sakura)\/[A-Za-z0-9._-]{1,80}\.tsc$/;
const MANIFEST_SCHEMA = 1;
const MAGIC = Buffer.from("3105PATCH\0", "latin1");
const RESELLER_FALLBACK = "https://jvztxnx-global-control.burgoajustin.workers.dev";
const LEGACY_ADMIN_IDS = ["5869209007"];
const PATCH_COMMANDS = new Set([
  "/patches",
  "/projects",
  "/upload",
  "/list",
  "/remove",
  "/cancel",
  "/keyversion",
  "/rotate",
]);

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
      "referrer-policy": "no-referrer",
      ...headers,
    },
  });

// Constant-time compare so a wrong webhook token cannot be recovered by timing,
// and an unset secret rejects everything instead of matching an empty header.
const secretMatches = (supplied, expected) => {
  if (!expected) return false;
  const left = String(supplied ?? "");
  if (left.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i += 1) {
    diff |= left.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
};

const bad = (message, status = 400) => json({ error: message }, status);

async function signManifest(env, bytes) {
  const raw = String(env.MANIFEST_SIGNING_KEY || "").trim();
  if (!raw) return null;
  try {
    const der = Uint8Array.from(atob(raw), (character) => character.charCodeAt(0));
    const key = await crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"]);
    const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, bytes);
    return b64url(signature);
  } catch {
    return null;
  }
}

async function signedJson(env, value, status = 200, headers = {}) {
  const body = JSON.stringify(value);
  const signature = await signManifest(env, new TextEncoder().encode(body));
  if (!signature) return bad("manifest_signing_unavailable", 503);
  return new Response(body, {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "x-trystore-signature": signature,
      ...headers,
    },
  });
}

const esc = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

const nowSeconds = () => Math.floor(Date.now() / 1000);

async function tg(env, method, body) {
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return response.json().catch(() => ({ ok: false }));
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// D1 returns a BLOB as an ArrayBuffer, but local bindings and older runtimes
// have handed back views or plain byte arrays. Normalize before the Response.
function bytesOf(value) {
  if (value instanceof ArrayBuffer) return value;
  if (ArrayBuffer.isView(value)) {
    return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
  }
  if (Array.isArray(value)) return new Uint8Array(value).buffer;
  return value;
}

const sanitizeFile = (name) => {
  const base = String(name || "").split(/[\\/]/).pop().trim();
  const lower = base.toLowerCase();
  if (!base || base.length > 120) return null;
  if (base.startsWith(".")) return null;
  if (!PATCH_EXTENSIONS.some((extension) => lower.endsWith(extension))) return null;
  if (!/^[A-Za-z0-9 ._()\-]+$/.test(base)) return null;
  return base;
};

const projectKey = (value) => {
  const slug = String(value || "").trim().toLowerCase();
  return PROJECTS.includes(slug) ? slug : null;
};

const projectLabel = (project) => {
  const meta = PROJECT_META[project] || { label: project, emoji: "📦" };
  return `${meta.emoji} ${meta.label}`;
};

function formatSize(bytes) {
  const value = Number(bytes) || 0;
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
}

function adminIds(env) {
  const configured = String(env.PATCH_ADMIN_IDS || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...configured, String(env.TELEGRAM_OWNER_ID || ""), ...LEGACY_ADMIN_IDS].filter(Boolean));
}

const isPatchAdmin = (env, fromId) => adminIds(env).has(String(fromId));

const SUPPORTED_PATCH_SCHEMAS = new Set([1, 2]);

// Entries without schema metadata predate the field. They stay visible so an
// older manifest keeps working, but anything explicitly known to be outside
// the client importer range is never handed to the app. A schema-9 visual
// package already lives inside the IPA; publishing it here aborts the sync.
function isFeedEntry(entry) {
  if (!entry || entry.hidden === true) return false;
  if (entry.isPasswordProtected === true) return false;
  if (Number.isInteger(entry.schemaVersion)) {
    return SUPPORTED_PATCH_SCHEMAS.has(entry.schemaVersion);
  }
  return true;
}

// A repaired package can be served from D1 while the KV write quota is
// exhausted. The manifest still lives in KV, so overlay the hash, size and URL
// for every file that has a D1 copy. The client verifies all three.
async function applyFeedOverrides(env, project, manifest) {
  if (!env.DB) return manifest;
  try {
    const rows = await env.DB.prepare(
      "SELECT name, sha256, size FROM feed_blobs WHERE project=?1",
    ).bind(project).all();
    const overrides = new Map((rows.results || []).map((row) => [String(row.name), row]));
    if (overrides.size === 0) return manifest;
    const base = String(env.PUBLIC_BASE_URL || "https://trystore-patch-feed.burgoajustin.workers.dev").replace(/\/+$/, "");
    for (const patch of manifest.patches) {
      const row = overrides.get(String(patch.file));
      if (!row) continue;
      patch.sha256 = String(row.sha256);
      patch.size = Number(row.size);
      patch.url = `${base}/patches/${project}/${encodeURIComponent(patch.file)}?v=${encodeURIComponent(String(row.sha256))}`;
    }
  } catch {
    // A D1 hiccup must not take the manifest away; KV still has the last copy.
  }
  return manifest;
}

async function readManifest(env, project) {
  const text = await env.PATCHES.get(`patches/${project}/manifest.json`);
  if (!text) return { schemaVersion: MANIFEST_SCHEMA, project, updatedAt: null, patches: [] };
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }
  if (!parsed || !Array.isArray(parsed.patches)) {
    return { schemaVersion: MANIFEST_SCHEMA, project, updatedAt: null, patches: [] };
  }
  parsed.patches = parsed.patches.filter(isFeedEntry);
  return applyFeedOverrides(env, project, parsed);
}

async function writeManifest(env, project, manifest) {
  manifest.schemaVersion = MANIFEST_SCHEMA;
  manifest.project = project;
  manifest.updatedAt = new Date().toISOString();
  await env.PATCHES.put(`patches/${project}/manifest.json`, JSON.stringify(manifest, null, 2));
}

/* ------------------------------------------------------------------ */
/* Bundle key versions                                                 */
/* ------------------------------------------------------------------ */

// Key material never lives in KV or D1. Each version maps to a Worker secret,
// so retiring a leaked key is: set the next secret, rotate, delete the old one.
const BUNDLE_KEY_VERSIONS = new Set(["1", "2"]);

function bundleKeySecret(env, version) {
  const name = String(version) === "2" ? "APP_BUNDLE_KEY_V2" : "APP_BUNDLE_KEY";
  const encoded = String(env[name] || "");
  if (!encoded) return null;
  let bytes;
  try {
    bytes = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
  return bytes.length === 32 ? { encoded, bytes } : null;
}

// D1 owns the served version so a rotation is a data change; the env var only
// seeds a deployment that has no row yet.
async function currentBundleKeyVersion(env, project) {
  const fallback = String(env.PATCH_BUNDLE_KEY_VERSION || "1");
  const seeded = BUNDLE_KEY_VERSIONS.has(fallback) ? fallback : "1";
  if (!env.DB) return seeded;
  try {
    const row = await env.DB.prepare(
      "SELECT key_version FROM feed_key_state WHERE project=?1",
    ).bind(project).first();
    const stored = String(row?.key_version ?? "");
    if (BUNDLE_KEY_VERSIONS.has(stored)) return stored;
  } catch {}
  return seeded;
}

async function setBundleKeyVersion(env, project, version) {
  if (!env.DB) return false;
  try {
    await env.DB.prepare(
      "INSERT INTO feed_key_state(project,key_version,rotated_at) VALUES(?1,?2,?3) " +
        "ON CONFLICT(project) DO UPDATE SET key_version=excluded.key_version, rotated_at=excluded.rotated_at",
    ).bind(project, String(version), nowSeconds()).run();
    return true;
  } catch {
    return false;
  }
}

// The AAD stays keyed on the package, not the key version, so a package wrapped
// under v1 keeps the AAD an already-shipped client computes.
function contentKeyAAD(envelope) {
  return new TextEncoder().encode(
    `3105PATCH/v${envelope.schemaVersion}/key/${envelope.packageID}`,
  );
}

async function sealContentKey(envelope, contentKey, keyBytes) {
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt"]);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: contentKeyAAD(envelope) },
    key,
    contentKey,
  );
  return Buffer.concat([Buffer.from(nonce), Buffer.from(sealed)]);
}

async function openContentKey(envelope, wrapped, keyBytes) {
  const raw = Buffer.from(wrapped);
  if (raw.length <= 12) throw new Error("bad_wrapped_key");
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
  const opened = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: raw.subarray(0, 12), additionalData: contentKeyAAD(envelope) },
    key,
    raw.subarray(12),
  );
  return new Uint8Array(opened);
}

async function wrapTrystorePackage(env, bytes, version = "1") {
  let envelope;
  try {
    envelope = parsePackage(bytes);
  } catch {
    return bytes;
  }
  if (envelope.isPasswordProtected) return bytes;
  if (envelope.wrappingScheme === "bundle") return bytes;
  const contentKey = envelope.publicContentKey;
  if (!contentKey) return bytes;

  const secret = bundleKeySecret(env, version);
  // Publishing in the clear because a rotation is half configured would hand
  // out the payload, so fail the upload instead of storing it unwrapped.
  if (!secret) throw new Error("bundle_key_unavailable");

  envelope.wrappedContentKey = await sealContentKey(envelope, contentKey, secret.bytes);
  envelope.wrappingScheme = "bundle";
  envelope.keyAADVersion = Number(envelope.schemaVersion);
  envelope.bundleKeyVersion = Number(version);
  delete envelope.publicContentKey;
  return Buffer.concat([MAGIC, bplist(envelope)]);
}

// Re-wraps every stored package of a project under `target`, then flips the
// served version. Each blob is rewritten before the pointer moves, so a device
// never receives a key that cannot open the package it is handed.
async function rotateProjectBundles(env, project, target) {
  const version = String(target);
  if (!BUNDLE_KEY_VERSIONS.has(version)) return { ok: false, error: "unsupported_key_version" };
  const targetSecret = bundleKeySecret(env, version);
  if (!targetSecret) return { ok: false, error: "key_unavailable" };

  const manifest = await readManifest(env, project);
  const base = String(env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
  const rotated = [];

  for (const patch of manifest.patches) {
    const objectKey = `patches/${project}/${patch.file}`;
    const stored = await env.PATCHES.get(objectKey, "arrayBuffer");
    if (!stored) continue;
    let envelope;
    try {
      envelope = parsePackage(stored);
    } catch {
      continue;
    }
    if (envelope.wrappingScheme !== "bundle" || !envelope.wrappedContentKey) continue;

    const declared = String(envelope.bundleKeyVersion ?? "");
    const fromVersion = BUNDLE_KEY_VERSIONS.has(declared)
      ? declared
      : version === "2"
        ? "1"
        : "2";
    if (fromVersion === version && String(patch.keyVersion ?? "") === version) continue;
    const fromSecret = bundleKeySecret(env, fromVersion);
    if (!fromSecret) return { ok: false, error: "key_unavailable", file: patch.file };

    let contentKey;
    try {
      contentKey = await openContentKey(envelope, envelope.wrappedContentKey, fromSecret.bytes);
    } catch {
      return { ok: false, error: "unwrap_failed", file: patch.file };
    }

    envelope.wrappedContentKey = await sealContentKey(envelope, contentKey, targetSecret.bytes);
    envelope.bundleKeyVersion = Number(version);
    const bytes = Buffer.concat([MAGIC, bplist(envelope)]);
    await env.PATCHES.put(objectKey, bytes);

    const digest = await sha256(bytes);
    patch.sha256 = digest;
    patch.size = bytes.byteLength;
    patch.keyVersion = Number(version);
    patch.url = `${base}/patches/${project}/${encodeURIComponent(patch.file)}?v=${digest}`;
    rotated.push(patch.file);
  }

  await writeManifest(env, project, manifest);
  if (!(await setBundleKeyVersion(env, project, version))) {
    return { ok: false, error: "state_unavailable", rotated };
  }
  return { ok: true, rotated };
}

async function publishPatch(env, project, file, rawBytes) {
  const keyVersion = project === "trystore"
    ? await currentBundleKeyVersion(env, project)
    : null;
  const bytes = project === "trystore"
    ? await wrapTrystorePackage(env, rawBytes, keyVersion)
    : rawBytes;
  const digest = await sha256(bytes);
  await env.PATCHES.put(`patches/${project}/${file}`, bytes);

  let schemaVersion = null;
  let isPasswordProtected = false;
  try {
    const envelope = parsePackage(bytes);
    schemaVersion = Number(envelope.schemaVersion);
    isPasswordProtected = envelope.isPasswordProtected === true;
  } catch {
    schemaVersion = null;
  }

  const manifest = await readManifest(env, project);
  const entry = {
    file,
    name: file.replace(/\.(trystore|3105|tipa|apple)$/i, ""),
    sha256: digest,
    size: bytes.byteLength,
    version: new Date().toISOString(),
    url: `${String(env.PUBLIC_BASE_URL || "").replace(/\/+$/, "")}/patches/${project}/${encodeURIComponent(file)}?v=${digest}`,
    schemaVersion,
    isPasswordProtected,
    ...(keyVersion ? { keyVersion: Number(keyVersion) } : {}),
  };
  const index = manifest.patches.findIndex((item) => item.file.toLowerCase() === file.toLowerCase());
  if (index >= 0) manifest.patches[index] = entry;
  else manifest.patches.push(entry);
  manifest.patches.sort((a, b) => a.name.localeCompare(b.name));
  await writeManifest(env, project, manifest);
  return entry;
}

async function removePatch(env, project, file) {
  const objectKey = `patches/${project}/${file}`;
  const backupKey = `backup/${project}/${new Date().toISOString().replaceAll(":", "-")}-${file}`;
  const bytes = await env.PATCHES.get(objectKey, "arrayBuffer");
  if (bytes) {
    await env.PATCHES.put(backupKey, bytes, { expirationTtl: 60 * 60 * 24 * 30 });
  }
  await env.PATCHES.delete(objectKey);
  const manifest = await readManifest(env, project);
  manifest.patches = manifest.patches.filter((item) => item.file.toLowerCase() !== file.toLowerCase());
  await writeManifest(env, project, manifest);
}

async function deleteSession(env, chatId) {
  await env.PATCHES.delete(`session:${chatId}`);
}

async function readSession(env, chatId) {
  const text = await env.PATCHES.get(`session:${chatId}`);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function writeSession(env, chatId, session) {
  await env.PATCHES.put(`session:${chatId}`, JSON.stringify(session), {
    expirationTtl: SESSION_TTL_SECONDS,
  });
}

/* ------------------------------------------------------------------ */
/* Patch package repacking                                             */
/* ------------------------------------------------------------------ */

function parsePackage(bytes) {
  const buffer = Buffer.from(bytes);
  if (buffer.length < 32 || !buffer.subarray(0, 10).equals(MAGIC)) {
    throw new Error("bad_magic");
  }
  const envelope = parseBuffer(buffer.subarray(10))[0];
  if (!envelope || typeof envelope !== "object" || !envelope.packageID) {
    throw new Error("bad_envelope");
  }
  return envelope;
}

async function decryptPayload(envelope) {
  if (envelope.isPasswordProtected || !envelope.publicContentKey) {
    throw new Error("password_protected");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    envelope.publicContentKey,
    "AES-GCM",
    false,
    ["decrypt", "encrypt"],
  );
  const aad = new TextEncoder().encode(
    `3105PATCH/v${envelope.schemaVersion}/payload/${envelope.packageID}`,
  );
  const iv = envelope.encryptedPayload.subarray(0, 12);
  const ciphertext = envelope.encryptedPayload.subarray(12);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, additionalData: aad },
    key,
    ciphertext,
  );
  const payload = parseBuffer(Buffer.from(plaintext))[0];
  if (!payload || !payload.project || !Array.isArray(payload.project.rules)) {
    throw new Error("bad_payload");
  }
  return { key, payload };
}

/**
 * Rewrites a freshly uploaded package so it takes over an existing slot:
 * same envelope packageID, same project id and name as the target. The client
 * dedupes by packageID, so this is what turns an upload into a real in-place
 * replacement instead of a second patch next to the old one.
 */
const TRYSTORE_SLOT_IDENTITIES = {
  "HEAD": ["HEAD"],
  "NECK": ["NECK"],
  "HSPESSCOSO": ["HS PESSCOSO"],
  "HS SLA PECHO": ["HS SLA PECHO"],
  "EXCLUSIVO AZUL": ["EXCLUSIVO AZUL", "HOLOGRAMA ARMAS"],
  "TryStore": ["TryStore", "Balas Magicas"],
  "HOLOGRAMAEXCLUSIVO": ["HOLOGRAMA EXCLUSIVO"],
  "HOLOGRAMAEXCLUSIVO(4)": ["HOLOGRAMA EXCLUSIVO", "HOLOGRAMA EXCLUSIVO VERDE"],
  "HOLOGRAMAEXCLUSIVO(5)": ["HOLOGRAMA EXCLUSIVO", "HOLOGRAMA EXCLUSIVO ROSADO"],
  "Cuello y Drag": ["Drag con Cuello", "Cuello y Drag"],
  "Pecho3105": ["Pecho3105", "Aimbot Pecho"],
  "CUELLO3105": ["CUELLO3105", "Aimbot Pecho"],
};

function normalizeIdentity(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function tryStoreSlotIdentities(file) {
  const stem = String(file || "").replace(/\.(trystore|3105|tipa|apple)$/i, "");
  const key = normalizeIdentity(stem);
  for (const [slot, names] of Object.entries(TRYSTORE_SLOT_IDENTITIES)) {
    if (normalizeIdentity(slot) === key) return names.map(normalizeIdentity);
  }
  return null;
}

// A repack renames the uploaded project to the target slot. That is how an
// Antena payload once ended up in an aim slot. Reject a source package whose
// own project name does not belong to the target module.
async function validateTrystoreUpload(project, targetFile, bytes) {
  if (project !== "trystore") return;
  const allowed = tryStoreSlotIdentities(targetFile);
  if (!allowed) return;
  const envelope = parsePackage(bytes);
  if (envelope.isPasswordProtected) throw new Error("password_protected");
  const { payload } = await decryptPayload(envelope);
  const actual = normalizeIdentity(payload.project?.name);
  if (!allowed.includes(actual)) {
    throw new Error(`source_identity_mismatch:${payload.project?.name || "unknown"}`);
  }
}

async function repackForTarget(sourceBytes, targetBytes) {
  const source = parsePackage(sourceBytes);
  const target = parsePackage(targetBytes);
  if (source.isPasswordProtected || target.isPasswordProtected) {
    throw new Error("password_protected");
  }
  const { key, payload } = await decryptPayload(source);
  const { payload: targetPayload } = await decryptPayload(target);
  const targetID = String(target.packageID);
  const targetName = String(targetPayload.project.name || "").trim();
  if (!targetID || !targetName) throw new Error("bad_target");

  payload.project.name = targetName;
  payload.project.id = targetID;
  payload.project.updatedAt = new Date();

  const plaintext = bplist(payload);
  const aad = new TextEncoder().encode(
    `3105PATCH/v${source.schemaVersion}/payload/${targetID}`,
  );
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: aad },
    key,
    plaintext,
  );

  source.packageID = targetID;
  source.encryptedPayload = Buffer.concat([Buffer.from(nonce), Buffer.from(sealed)]);
  source.keyFingerprint = Buffer.from(await crypto.subtle.digest("SHA-256", source.publicContentKey));

  const result = Buffer.concat([MAGIC, bplist(source)]);
  const check = parsePackage(result);
  const { payload: checkPayload } = await decryptPayload(check);
  if (String(checkPayload.project.id) !== targetID || String(checkPayload.project.name) !== targetName) {
    throw new Error("repack_verify_failed");
  }
  return result;
}

/* ------------------------------------------------------------------ */
/* Telegram rendering                                                  */
/* ------------------------------------------------------------------ */

async function sendMessage(env, chatId, text, keyboard) {
  return tg(env, "sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    reply_markup: keyboard ? { inline_keyboard: keyboard } : undefined,
  });
}

async function editMessage(env, chatId, messageId, text, keyboard) {
  const result = await tg(env, "editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    reply_markup: keyboard ? { inline_keyboard: keyboard } : undefined,
  });
  if (!result.ok) return sendMessage(env, chatId, text, keyboard);
  return result;
}

function homeKeyboard(manifests) {
  const rows = PROJECTS.map((project) => {
    const count = manifests[project]?.patches.length || 0;
    return [
      {
        text: `${projectLabel(project)} · ${count} patch${count === 1 ? "" : "es"}`,
        callback_data: `pm:proj:${project}`,
      },
    ];
  });
  rows.push([{ text: "➕ Add file", callback_data: "pm:addpick" }]);
  rows.push([{ text: "🔄 Refresh", callback_data: "pm:home" }]);
  return rows;
}

async function homeText(env) {
  const manifests = {};
  for (const project of PROJECTS) manifests[project] = await readManifest(env, project);
  const lines = ["🛠️ <b>Patch Manager</b>", "", "Choose a project. Uploads publish instantly; the app syncs on launch."];
  for (const project of PROJECTS) {
    const manifest = manifests[project];
    const latest = manifest.patches
      .map((patch) => patch.version || "")
      .sort()
      .pop();
    lines.push(
      `${projectLabel(project)} — <b>${manifest.patches.length}</b> patch${manifest.patches.length === 1 ? "" : "es"}${latest ? ` · ${formatDate(latest)}` : ""}`,
    );
  }
  return { text: lines.join("\n"), keyboard: homeKeyboard(manifests) };
}

function projectKeyboard(project, manifest) {
  const rows = manifest.patches.map((patch, index) => [
    {
      text: `🧩 ${patch.name} · ${formatSize(patch.size)}`,
      callback_data: `pm:p:${project}:${index}`,
    },
  ]);
  rows.push([{ text: "➕ Add file", callback_data: `pm:add:${project}` }]);
  rows.push([
    { text: "⬅️ Projects", callback_data: "pm:home" },
    { text: "🔄 Refresh", callback_data: `pm:proj:${project}` },
  ]);
  return rows;
}

async function projectText(env, project) {
  const manifest = await readManifest(env, project);
  const lines = [
    `${projectLabel(project)} — <b>${manifest.patches.length}</b> patch${manifest.patches.length === 1 ? "" : "es"}`,
    manifest.updatedAt ? `Updated ${formatDate(manifest.updatedAt)}` : "No uploads yet.",
    "",
    manifest.patches.length
      ? "Tap a patch to replace or delete it."
      : "Tap Add file to publish the first patch.",
  ];
  return { text: lines.join("\n"), keyboard: projectKeyboard(project, manifest) };
}

function patchKeyboard(env, project, index, entry) {
  const base = String(env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
  const downloadURL = entry.url.startsWith("http") ? entry.url : `${base}${entry.url}`;
  const rows = [[
    { text: "🔁 Replace", callback_data: `pm:r:${project}:${index}` },
    { text: "🗑 Delete", callback_data: `pm:d:${project}:${index}` },
  ]];
  if (project !== "trystore") rows.push([{ text: "⬇️ Download", url: downloadURL }]);
  rows.push([{ text: "⬅️ Back", callback_data: `pm:back:${project}` }]);
  return rows;
}

async function patchText(project, entry, index) {
  return [
    `🧩 <b>${esc(entry.name)}</b>`,
    `Project: ${projectLabel(project)}`,
    `File: <code>${esc(entry.file)}</code>`,
    `Size: ${formatSize(entry.size)}`,
    `Updated: ${formatDate(entry.version)}`,
    `SHA-256: <code>${esc(entry.sha256)}</code>`,
    "",
    "Replace keeps this filename and package slot, so the app swaps it in place.",
    "",
    `#${index + 1}`,
  ].join("\n");
}

/* ------------------------------------------------------------------ */
/* Telegram command handling                                           */
/* ------------------------------------------------------------------ */

async function showHome(env, chatId, messageId) {
  const view = await homeText(env);
  if (messageId) return editMessage(env, chatId, messageId, view.text, view.keyboard);
  return sendMessage(env, chatId, view.text, view.keyboard);
}

async function showProject(env, chatId, project, messageId) {
  const view = await projectText(env, project);
  if (messageId) return editMessage(env, chatId, messageId, view.text, view.keyboard);
  return sendMessage(env, chatId, view.text, view.keyboard);
}

async function showPatch(env, chatId, project, index, messageId) {
  const manifest = await readManifest(env, project);
  const entry = manifest.patches[index];
  if (!entry) {
    await sendMessage(env, chatId, "That patch list changed. Refreshing.");
    return showProject(env, chatId, project);
  }
  const text = await patchText(project, entry, index);
  const keyboard = patchKeyboard(env, project, index, entry);
  if (messageId) return editMessage(env, chatId, messageId, text, keyboard);
  return sendMessage(env, chatId, text, keyboard);
}

async function promptAdd(env, chatId, project, messageId) {
  await writeSession(env, chatId, {
    action: "add",
    project,
    createdAt: nowSeconds(),
  });
  const text = [
    `➕ <b>Add file — ${esc(projectLabel(project))}</b>`,
    "",
    "Send the patch as a document.",
    "If the filename already exists it is replaced in place.",
    "",
    "Allowed: .TRYSTORE .3105 .tipa .APPLE",
    "Send /cancel to stop.",
  ].join("\n");
  const keyboard = [[{ text: "⬅️ Cancel", callback_data: `pm:back:${project}` }]];
  if (messageId) return editMessage(env, chatId, messageId, text, keyboard);
  return sendMessage(env, chatId, text, keyboard);
}

async function promptReplace(env, chatId, project, index, messageId) {
  const manifest = await readManifest(env, project);
  const entry = manifest.patches[index];
  if (!entry) {
    await sendMessage(env, chatId, "That patch list changed. Refreshing.");
    return showProject(env, chatId, project);
  }
  await writeSession(env, chatId, {
    action: "replace",
    project,
    file: entry.file,
    createdAt: nowSeconds(),
  });
  const text = [
    `🔁 <b>Replace ${esc(entry.name)}</b>`,
    "",
    `Send the new package for <code>${esc(entry.file)}</code>.`,
    "It keeps this filename and package slot, so the app swaps it in place.",
    "",
    "Send /cancel to stop.",
  ].join("\n");
  const keyboard = [[{ text: "⬅️ Cancel", callback_data: `pm:back:${project}` }]];
  if (messageId) return editMessage(env, chatId, messageId, text, keyboard);
  return sendMessage(env, chatId, text, keyboard);
}

async function confirmDelete(env, chatId, project, index, messageId) {
  const manifest = await readManifest(env, project);
  const entry = manifest.patches[index];
  if (!entry) {
    await sendMessage(env, chatId, "That patch list changed. Refreshing.");
    return showProject(env, chatId, project);
  }
  const text = [
    `🗑 <b>Delete ${esc(entry.name)}?</b>`,
    "",
    `This removes <code>${esc(entry.file)}</code> from the feed. A backup is kept for 30 days.`,
  ].join("\n");
  const keyboard = [
    [
      { text: "✅ Delete", callback_data: `pm:dc:${project}:${index}` },
      { text: "⬅️ Cancel", callback_data: `pm:p:${project}:${index}` },
    ],
  ];
  if (messageId) return editMessage(env, chatId, messageId, text, keyboard);
  return sendMessage(env, chatId, text, keyboard);
}

async function handleDocument(env, message, chatId) {
  const session = await readSession(env, chatId);
  if (!session) {
    await sendMessage(env, chatId, "No active upload. Use /patches to choose a patch or add a file.");
    return;
  }
  if (nowSeconds() - Number(session.createdAt || 0) > SESSION_TTL_SECONDS) {
    await deleteSession(env, chatId);
    await sendMessage(env, chatId, "Upload session expired. Use /patches again.");
    return;
  }

  const document = message.document;
  if (!document) return;
  if (document.file_size && document.file_size > MAX_UPLOAD_BYTES) {
    await sendMessage(env, chatId, "File too large. Ceiling is 24 MB (KV value limit).");
    return;
  }
  const uploadedFile = sanitizeFile(document.file_name);
  if (!uploadedFile) {
    await sendMessage(env, chatId, "Rejected. Allowed: .TRYSTORE .3105 .tipa .APPLE with safe characters.");
    return;
  }

  const lookup = await tg(env, "getFile", { file_id: document.file_id });
  if (!lookup.ok) {
    await sendMessage(env, chatId, "Telegram refused the file lookup.");
    return;
  }
  const fileResponse = await fetch(
    `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${lookup.result.file_path}`,
  );
  if (!fileResponse.ok) {
    await sendMessage(env, chatId, "Download from Telegram failed.");
    return;
  }
  let bytes = Buffer.from(await fileResponse.arrayBuffer());

  const project = session.project;
  const targetFile = session.action === "replace" ? session.file : uploadedFile;
  try {
    await validateTrystoreUpload(project, targetFile, bytes);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "identity_check_failed";
    await sendMessage(
      env,
      chatId,
      [
        "Rejected: the package does not belong to that slot.",
        `<code>${esc(reason)}</code>`,
        "",
        "Build the package with the same project name as the file you are replacing.",
      ].join("\n"),
    );
    return;
  }
  const existing = await env.PATCHES.get(`patches/${project}/${targetFile}`, "arrayBuffer");
  let replaced = false;
  if (existing) {
    try {
      bytes = await repackForTarget(bytes, existing);
      replaced = true;
    } catch (error) {
      const reason = error instanceof Error ? error.message : "repack_failed";
      await sendMessage(
        env,
        chatId,
        [
          "Could not prepare the replacement.",
          `<code>${esc(reason)}</code>`,
          "",
          "The file must be an unencrypted .TRYSTORE package and the existing slot must be readable.",
          "Send another file or /cancel.",
        ].join("\n"),
      );
      return;
    }
  } else if (session.action === "replace") {
    await deleteSession(env, chatId);
    await sendMessage(env, chatId, "That target no longer exists. Refreshing the project.");
    return showProject(env, chatId, project);
  }

  const entry = await publishPatch(env, project, targetFile, bytes);
  await deleteSession(env, chatId);

  const lines = [
    replaced ? `✅ Replaced <b>${esc(entry.name)}</b> in ${esc(projectLabel(project))}.` : `✅ Published <b>${esc(entry.name)}</b> to ${esc(projectLabel(project))}.`,
    "",
    `File: <code>${esc(entry.file)}</code>`,
    `Size: ${formatSize(entry.size)}`,
    `SHA-256: <code>${esc(entry.sha256)}</code>`,
    "",
    "The app picks it up on its next sync.",
  ];
  if (Number.isInteger(entry.schemaVersion) && !SUPPORTED_PATCH_SCHEMAS.has(entry.schemaVersion)) {
    lines.push(
      "",
      `Not published: schema ${entry.schemaVersion} is outside the client's 1-2 range. Stored in KV only.`,
    );
  }
  await sendMessage(env, chatId, lines.join("\n"), [
    [{ text: "📦 Open project", callback_data: `pm:back:${project}` }],
    [{ text: "🏠 Patch Manager", callback_data: "pm:home" }],
  ]);
}

async function handleCommand(env, message, chatId, command, args) {
  switch (command) {
    case "/patches":
    case "/projects":
      return showHome(env, chatId);
    case "/list":
    case "/remove": {
      const project = projectKey(args[0]);
      if (project) return showProject(env, chatId, project);
      return showHome(env, chatId);
    }
    case "/upload": {
      const project = projectKey(args[0]);
      if (project) return promptAdd(env, chatId, project);
      return showHome(env, chatId);
    }
    case "/cancel": {
      await deleteSession(env, chatId);
      return sendMessage(env, chatId, "Cancelled.", [[{ text: "🏠 Patch Manager", callback_data: "pm:home" }]]);
    }
    case "/keyversion": {
      const project = projectKey(args[0]) || "trystore";
      const version = await currentBundleKeyVersion(env, project);
      const secret = bundleKeySecret(env, version);
      return sendMessage(
        env,
        chatId,
        `🔑 <b>${esc(project)}</b>\nServing key version <b>${esc(version)}</b> ${secret ? "(configured)" : "(secret missing)"}`,
        [[{ text: "🏠 Patch Manager", callback_data: "pm:home" }]],
      );
    }
    case "/rotate": {
      const project = projectKey(args[0]);
      const target = String(args[1] || "");
      if (!project || !BUNDLE_KEY_VERSIONS.has(target)) {
        return sendMessage(env, chatId, "Usage: /rotate &lt;project&gt; &lt;1|2&gt;");
      }
      const result = await rotateProjectBundles(env, project, target);
      return sendMessage(
        env,
        chatId,
        result.ok
          ? `✅ ${esc(project)} now serves key v${esc(target)}\nRewrapped: ${result.rotated.length}`
          : `❌ ${esc(project)}: ${esc(result.error)}${result.file ? ` (${esc(result.file)})` : ""}`,
      );
    }
    default:
      return false;
  }
}

async function handleCallback(env, callback) {
  const data = String(callback.data || "");
  const chatId = String(callback.message?.chat?.id || "");
  const messageId = callback.message?.message_id;
  const answer = (text) => tg(env, "answerCallbackQuery", { callback_query_id: callback.id, text });
  if (!chatId) return;

  if (data === "pm:home") {
    await answer("Patch Manager");
    return showHome(env, chatId, messageId);
  }
  if (data === "pm:addpick") {
    await answer("Choose a project");
    const manifests = {};
    for (const project of PROJECTS) manifests[project] = await readManifest(env, project);
    const rows = PROJECTS.map((project) => [
      {
        text: `${projectLabel(project)} · ${manifests[project].patches.length}`,
        callback_data: `pm:add:${project}`,
      },
    ]);
    rows.push([{ text: "⬅️ Back", callback_data: "pm:home" }]);
    return editMessage(env, chatId, messageId, "➕ <b>Add file</b>\nChoose the project:", rows);
  }
  if (data.startsWith("pm:proj:") || data.startsWith("pm:back:")) {
    const project = projectKey(data.split(":")[2]);
    if (!project) return;
    await answer(projectLabel(project));
    return showProject(env, chatId, project, messageId);
  }
  if (data.startsWith("pm:p:") || data.startsWith("pm:r:") || data.startsWith("pm:d:") || data.startsWith("pm:dc:")) {
    const parts = data.split(":");
    const action = parts[1];
    const project = projectKey(parts[2]);
    const index = Number(parts[3]);
    if (!project || !Number.isInteger(index) || index < 0) return;
    await answer("OK");
    if (action === "p") return showPatch(env, chatId, project, index, messageId);
    if (action === "r") return promptReplace(env, chatId, project, index, messageId);
    if (action === "d") return confirmDelete(env, chatId, project, index, messageId);
    if (action === "dc") {
      const manifest = await readManifest(env, project);
      const entry = manifest.patches[index];
      if (!entry) {
        await sendMessage(env, chatId, "That patch list changed. Refreshing.");
        return showProject(env, chatId, project);
      }
      await removePatch(env, project, entry.file);
      await deleteSession(env, chatId);
      await sendMessage(env, chatId, `🗑 Removed <b>${esc(entry.name)}</b> from ${esc(projectLabel(project))}.`);
      return showProject(env, chatId, project, messageId);
    }
  }
  if (data.startsWith("pm:add:")) {
    const project = projectKey(data.split(":")[2]);
    if (!project) return;
    await answer("Add file");
    return promptAdd(env, chatId, project, messageId);
  }
}

/* ------------------------------------------------------------------ */
/* Reseller forwarding                                                 */
/* ------------------------------------------------------------------ */

async function forwardUpdate(env, rawBody) {
  const headers = new Headers();
  headers.set("content-type", "application/json");
  const secret = env.TELEGRAM_WEBHOOK_SECRET;
  if (secret) headers.set("X-Telegram-Bot-Api-Secret-Token", secret);
  const init = { method: "POST", headers, body: rawBody };
  if (env.RESELLER) {
    return env.RESELLER.fetch("https://reseller.internal/api/telegram/webhook", init);
  }
  const origin = String(env.RESELLER_ORIGIN || RESELLER_FALLBACK).replace(/\/+$/, "");
  return fetch(`${origin}/api/telegram/webhook`, init);
}

async function sendPatchHint(env, chatId) {
  return sendMessage(
    env,
    chatId,
    "🛠️ <b>Patch Manager</b>\nPublish and replace patches without rebuilding the app.",
    [[{ text: "📦 Open patches", callback_data: "pm:home" }]],
  );
}

async function telegramWebhook(request, env) {
  if (!secretMatches(request.headers.get("X-Telegram-Bot-Api-Secret-Token"), env.TELEGRAM_WEBHOOK_SECRET)) {
    return bad("unauthorized", 401);
  }
  const rawBody = await request.text();
  let update;
  try {
    update = JSON.parse(rawBody);
  } catch {
    return bad("invalid_update");
  }

  const message = update.message;
  const callback = update.callback_query;
  const fromId = String(callback ? callback.from.id : message?.from?.id || "");
  const chatId = String(callback ? callback.message?.chat?.id : message?.chat?.id || "");
  if (!fromId || !chatId) return json({ ok: true });

  if (!isPatchAdmin(env, fromId)) {
    return forwardUpdate(env, rawBody);
  }

  if (callback) {
    if (String(callback.data || "").startsWith("pm:")) {
      await handleCallback(env, callback);
      return json({ ok: true });
    }
    return forwardUpdate(env, rawBody);
  }

  const text = String(message?.text || "").trim();
  const command = text.startsWith("/") ? text.split(/\s+/)[0].toLowerCase() : "";
  const args = text.startsWith("/") ? text.split(/\s+/).slice(1) : [];

  if (command === "/start") {
    const response = await forwardUpdate(env, rawBody);
    await sendPatchHint(env, chatId);
    return response;
  }

  if (message?.document) {
    const session = await readSession(env, chatId);
    if (session) {
      await handleDocument(env, message, chatId);
    } else {
      await sendMessage(env, chatId, "Use /patches to choose a patch or add a file.");
    }
    return json({ ok: true });
  }

  if (PATCH_COMMANDS.has(command)) {
    await handleCommand(env, message, chatId, command, args);
    return json({ ok: true });
  }

  return forwardUpdate(env, rawBody);
}

const DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// One package is dozens of blob requests. Validating each one would burn the
// licence worker's budget mid-download, so a positive check is cached for two
// minutes. Denials are never cached: a revoked key must stop immediately.
const GRANTED = Object.freeze({ allowed: true, reason: "active" });

const FEED_TOKEN_TTL = 600;
const FEED_KEY_TTL = 86_400;

function b64url(bytes) {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromB64url(value) {
  const normalized = String(value || "").replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function feedTokenMaterial(env) {
  const secret = String(env.FEED_TOKEN_SECRET || "");
  if (secret.length < 32) return null;
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function mintFeedToken(env, project, device, keyVersion, mode) {
  const key = await feedTokenMaterial(env);
  if (!key) return null;
  const issuedAt = nowSeconds();
  const payload = JSON.stringify({
    v: 1,
    project,
    device,
    keyVersion: String(keyVersion),
    // "attest" when an App Attest assertion released the key, "licence" when
    // the device proved only a live licence. Vault strict mode reads this.
    mode: mode === "attest" ? "attest" : "licence",
    iat: issuedAt,
    exp: issuedAt + FEED_TOKEN_TTL,
  });
  const body = b64url(new TextEncoder().encode(payload));
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return { token: `${body}.${b64url(signature)}`, expiresAt: issuedAt + FEED_TOKEN_TTL };
}

async function verifyFeedToken(env, token, project, device) {
  const [body, signature] = String(token || "").split(".");
  if (!body || !signature) return null;
  const key = await feedTokenMaterial(env);
  if (!key) return null;
  const raw = fromB64url(signature);
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    raw,
    new TextEncoder().encode(body),
  );
  if (!valid) return null;
  try {
    const claims = JSON.parse(new TextDecoder().decode(fromB64url(body)));
    if (claims.v !== 1
        || claims.project !== project
        || claims.device !== device
        || Number(claims.exp) <= nowSeconds()) {
      return null;
    }
    return claims;
  } catch {
    return null;
  }
}

// Stable, non-reversible subject for a licence+device pair. The feed never
// persists or logs the key itself.
async function licenceSubject(project, key, device) {
  return sha256(new TextEncoder().encode(`${project}|${key}|${device}`));
}

function denial(reason) {
  return { allowed: false, reason };
}

async function readCachedLicence(env, cacheKey) {
  if (!env.DB) return false;
  try {
    const row = await env.DB.prepare(
      "SELECT expires_at FROM feed_auth_cache WHERE subject=?1",
    ).bind(cacheKey).first();
    return Number(row?.expires_at || 0) > nowSeconds();
  } catch {
    return false;
  }
}

async function writeCachedLicence(env, cacheKey, ttlSeconds = 120) {
  if (!env.DB) return;
  try {
    await env.DB.prepare(
      "INSERT INTO feed_auth_cache(subject,expires_at) VALUES(?1,?2) " +
      "ON CONFLICT(subject) DO UPDATE SET expires_at=excluded.expires_at",
    ).bind(cacheKey, nowSeconds() + Math.max(1, Math.floor(ttlSeconds))).run();
  } catch {}
}

// A boolean here turned "the licence service did not answer" into "licence
// invalid", which reached the app as an unauthorized sync no retry could clear.
// The reason travels back so the client and the operator can tell them apart.
async function tryStoreLicenseState(request, env, project) {
  const match = (request.headers.get("authorization") || "")
    .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
  const deviceID = request.headers.get("x-trystore-device-id") || "";
  if (!match || !DEVICE_ID_PATTERN.test(deviceID)) {
    return denial("credentials_missing");
  }

  // Service binding only: a Worker cannot reliably fetch another Worker on the
  // same workers.dev zone, so an origin fallback would fail anyway and hide a
  // missing binding behind a generic denial.
  if (!env.RESELLER || typeof env.RESELLER.fetch !== "function") {
    return denial("license_service_unbound");
  }

  const cacheKey = await licenceSubject(project, match[1], deviceID);
  if (await readCachedLicence(env, cacheKey)) return GRANTED;

  // The licence Worker rate-limits by caller address. Without this header the
  // service binding counts every feed request as "unknown", so one busy client
  // exhausts the 30/min bucket for every other licence check.
  const headers = { "content-type": "application/json" };
  const callerIP = request.headers.get("cf-connecting-ip") || "";
  if (callerIP) headers["cf-connecting-ip"] = callerIP;
  const payload = JSON.stringify({
    key: match[1],
    deviceId: deviceID,
    projectId: project,
    appVersion: "1.1.1",
  });

  let result;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await env.RESELLER.fetch(
        new Request("https://reseller.internal/api/v1/keys/validate", {
          method: "POST",
          headers,
          body: payload,
        }),
      );
      // A rate-limited or cold licence service is transient. Turning it into a
      // 401 made the client erase a perfectly good cached bundle key, which is
      // exactly how the downloaded character vault ended up unreadable.
      if (response.status === 429 || response.status >= 500) {
        if (attempt === 0) continue;
        return denial(
          response.status === 429 ? "license_rate_limited" : `license_http_${response.status}`,
        );
      }
      if (!response.ok) return denial(`license_http_${response.status}`);
      result = await response.json().catch(() => null);
      break;
    } catch {
      if (attempt === 0) continue;
      return denial("license_service_unreachable");
    }
  }

  if (!result) return denial("license_service_unreachable");
  const active = result.valid === true
    && String(result.outcome || "").toLowerCase() === "active"
    && (!result.expiresAt || Date.parse(result.expiresAt) > Date.now());
  if (!active) {
    return denial(`license_${String(result.outcome || "invalid").toLowerCase()}`);
  }
  await writeCachedLicence(env, cacheKey);
  return GRANTED;
}
// 401 means the licence was rejected; 503 means the service is down and a retry
// is reasonable. Both used to be 401, which is why a cold Worker start looked
// exactly like a revoked key on the device.
function licenceFailure(state) {
  const transient = state.reason === "license_service_unreachable"
    || state.reason === "license_service_unbound"
    || state.reason === "license_rate_limited"
    || /^license_http_(429|5\d\d)$/.test(state.reason);
  return json(
    { valid: false, outcome: state.reason, error: state.reason },
    transient ? 503 : 401,
    { "cache-control": "no-store", vary: "authorization, x-trystore-device-id" },
  );
}

// Licensed projects never serve key material or packages without a live key.
// Public projects (hyper-regedit) keep their open feed.
const LICENSED_PATCH_PROJECTS = new Set(["trystore", "apple-music"]);

async function requireTryStoreLicense(request, env, project) {
  if (!LICENSED_PATCH_PROJECTS.has(project)) {
    return { allowed: true, reason: "public_project", mode: "public" };
  }
  const token = request.headers.get("x-trystore-feed-token") || "";
  const device = request.headers.get("x-trystore-device-id") || "";
  if (token) {
    const claims = await verifyFeedToken(env, token, project, device);
    if (claims) {
      return {
        allowed: true,
        reason: "feed_token",
        mode: claims.mode === "attest" ? "attest" : "licence",
      };
    }
  }
  const state = await tryStoreLicenseState(request, env, project);
  return state.allowed ? { ...state, mode: "licence" } : state;
}

// Vault strict mode. Flipped with REQUIRE_VAULT_ATTESTATION="1" once installed
// devices have registered with App Attest; sideloaded devices keep working
// while the flag is off. The marker is written when an attested bundle-key
// release succeeds, so a short-lived feed token is not the only proof.
async function vaultAttestationAllowed(request, env, project) {
  if (String(env.REQUIRE_VAULT_ATTESTATION || "") !== "1") return true;
  const match = (request.headers.get("authorization") || "")
    .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
  const device = request.headers.get("x-trystore-device-id") || "";
  if (!match || !DEVICE_ID_PATTERN.test(device)) return false;
  return readCachedLicence(
    env,
    "attest|" + await licenceSubject(project, match[1], device),
  );
}

// One licence is meant to serve one device, not a scraper pulling the vault on
// repeat. The per-IP bucket still applies; this one is keyed by a hash of the
// licence+device so rotating addresses does not reset the budget.
async function withinLicenceFetchBudget(env, bucket, request, project, limit) {
  const match = (request.headers.get("authorization") || "")
    .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
  const device = request.headers.get("x-trystore-device-id") || "";
  if (!match || !DEVICE_ID_PATTERN.test(device) || !Number.isFinite(limit) || limit <= 0) {
    return true;
  }
  const subject = await licenceSubject("fetch|" + bucket, match[1], device);
  return allowFeed(env, "licence-" + bucket, subject, limit, 3_600);
}

async function deviceSubject(project, key, device) {
  return licenceSubject("device|" + project, key, device);
}

async function issueDeviceChallenge(env, subject) {
  if (!env.DB) return null;
  const challenge = b64url(crypto.getRandomValues(new Uint8Array(32)));
  try {
    await env.DB.prepare(
      "INSERT INTO feed_device_keys(subject,public_key,challenge,challenge_expires_at,created_at) " +
      "VALUES(?1,NULL,?2,?3,?4) ON CONFLICT(subject) DO UPDATE SET " +
      "challenge=excluded.challenge, challenge_expires_at=excluded.challenge_expires_at",
    ).bind(subject, challenge, nowSeconds() + 180, nowSeconds()).run();
    return challenge;
  } catch {
    return null;
  }
}

// A request with no proof headers passes only while the strict flag is off; a
// request that carries them is always verified, so a new client never trades
// the hardware binding away by accident.
async function verifyDeviceProof(env, request, project) {
  const required = String(env.REQUIRE_DEVICE_SIGNATURE || "") === "1";
  const keyMatch = (request.headers.get("authorization") || "")
    .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
  const device = String(request.headers.get("x-trystore-device-id") || "");
  const publicKey = String(request.headers.get("x-trystore-device-public-key") || "").trim();
  const signature = String(request.headers.get("x-trystore-device-signature") || "").trim();
  const challenge = String(request.headers.get("x-trystore-challenge") || "").trim();
  if (!publicKey && !signature && !challenge) {
    return required
      ? { ok: false, reason: "device_signature_required" }
      : { ok: true, skipped: true };
  }
  if (!keyMatch || !DEVICE_ID_PATTERN.test(device) || !publicKey || !signature || !challenge) {
    return { ok: false, reason: "device_signature_invalid" };
  }
  if (!env.DB) return { ok: false, reason: "device_signature_unavailable" };
  let pub;
  try {
    pub = fromB64url(publicKey);
  } catch {
    return { ok: false, reason: "device_signature_invalid" };
  }
  if (pub.length !== 65 || pub[0] !== 4) {
    return { ok: false, reason: "device_signature_invalid" };
  }
  const subject = await deviceSubject(project, keyMatch[1], device);
  let row = null;
  try {
    row = await env.DB.prepare(
      "SELECT public_key, challenge, challenge_expires_at FROM feed_device_keys WHERE subject=?1",
    ).bind(subject).first();
  } catch {
    return { ok: false, reason: "device_signature_unavailable" };
  }
  if (!row || !row.challenge || row.challenge !== challenge
      || Number(row.challenge_expires_at || 0) <= nowSeconds()) {
    return { ok: false, reason: "device_challenge_expired" };
  }
  if (row.public_key && row.public_key !== publicKey) {
    return { ok: false, reason: "device_key_mismatch" };
  }
  const message = new TextEncoder().encode(
    `TryStore device v1\n${challenge}\n${project}\n${device}`,
  );
  let valid = false;
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      pub,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      fromB64url(signature),
      message,
    );
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: "device_signature_invalid" };
  try {
    await env.DB.prepare(
      "UPDATE feed_device_keys SET public_key=?1, challenge=NULL, challenge_expires_at=0 WHERE subject=?2",
    ).bind(publicKey, subject).run();
  } catch {}
  return { ok: true };
}
const TRY_STORE_DEVICE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function proxyAppAttest(request, env, endpoint) {
  if (request.method !== "POST") return bad("method_not_allowed", 405);
  if (!env.RESELLER || typeof env.RESELLER.fetch !== "function" || String(env.APP_ATTEST_INTERNAL_TOKEN || "").length < 32) {
    return bad("attestation_unavailable", 503);
  }
  const contentType = String(request.headers.get("content-type") || "").toLowerCase();
  const contentLength = Number(request.headers.get("content-length") || 0);
  if (!contentType.startsWith("application/json") || contentLength > 16 * 1024) return bad("invalid_request", 400);
  let input;
  try {
    const raw = await request.text();
    if (!raw || raw.length > 16 * 1024) return bad("invalid_request", 400);
    input = JSON.parse(raw);
  } catch {
    return bad("invalid_request", 400);
  }
  const authorization = String(request.headers.get("authorization") || "");
  const match = authorization.match(/^Bearer\s+([^\s]{1,256})$/i);
  const deviceId = String(request.headers.get("x-trystore-device-id") || "");
  if (!match || !TRY_STORE_DEVICE_ID.test(deviceId)) return bad("license_required", 401);
  let fields;
  if (endpoint.endsWith("/challenge")) {
    fields = { keyId: String(input.keyId || "") };
  } else if (endpoint.endsWith("/register")) {
    fields = { challengeID: input.challengeID, challenge: input.challenge, keyId: input.keyId, attestation: input.attestation };
  } else {
    fields = { challengeID: input.challengeID, challenge: input.challenge, keyId: input.keyId, assertion: input.assertion };
  }
  const payload = JSON.stringify({ key: match[1], deviceId, projectId: "trystore", ...fields });
  try {
    const result = await env.RESELLER.fetch(new Request(`https://reseller.internal${endpoint}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-app-attest-internal-token": String(env.APP_ATTEST_INTERNAL_TOKEN),
        ...(request.headers.get("cf-connecting-ip")
          ? { "cf-connecting-ip": request.headers.get("cf-connecting-ip") }
          : {}),
      },
      body: payload,
    }));
    return new Response(await result.text(), {
      status: result.status,
      headers: {
        "content-type": result.headers.get("content-type") || "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    });
  } catch {
    return bad("attestation_unavailable", 503);
  }
}
/* ------------------------------------------------------------------ */
/* HTTP routes                                                         */
/* ------------------------------------------------------------------ */

async function allowFeed(env, bucket, ip, limit, windowSeconds) {
  if (!env.DB) return true;
  const window = Math.floor(Date.now() / 1000 / windowSeconds);
  try {
    await env.DB.prepare(
      "INSERT INTO feed_rate_limits(bucket,subject,window_start,count) VALUES(?1,?2,?3,1) " +
      "ON CONFLICT(bucket,subject,window_start) DO UPDATE SET count=count+1",
    ).bind(bucket, ip, window).run();
    const row = await env.DB.prepare(
      "SELECT count FROM feed_rate_limits WHERE bucket=?1 AND subject=?2 AND window_start=?3",
    ).bind(bucket, ip, window).first();
    return Number(row?.count || 1) <= limit;
  } catch {
    // Rate-limit counters are best-effort. If D1 is unavailable, continue to the
    // mandatory license and device authorization checks below.
    return true;
  }
}
const feedIP = (request) => String(request.headers.get("cf-connecting-ip") || "unknown");

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") {
      return json({ status: "ok", service: "trystore-patch-feed" });
    }

    // The archive step uses this fingerprint to reject a pre-sealed vault that
    // no longer matches the key the feed serves. It is a hash of a 32-byte
    // random secret, not the key itself.
    if (path === "/api/patches/trystore/bundle-key/fingerprint" && request.method === "GET") {
      const version = await currentBundleKeyVersion(env, "trystore");
      const secret = bundleKeySecret(env, version);
      if (!secret) return bad("key_unavailable", 503);
      return json(
        { version, fingerprint: await sha256(secret.bytes) },
        200,
        { "cache-control": "no-store" },
      );
    }

    // Device proof challenge. Only a live licence can ask for one, and the
    // signed answer is what the licence-bound bundle-key release verifies.
    if (path === "/api/patches/trystore/device-challenge" && request.method === "GET") {
      if (!(await allowFeed(env, "device-challenge", feedIP(request), 30, 60))) {
        return bad("rate_limited", 429);
      }
      const licence = await requireTryStoreLicense(request, env, "trystore");
      if (!licence.allowed) return licenceFailure(licence);
      const keyMatch = (request.headers.get("authorization") || "")
        .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
      const device = String(request.headers.get("x-trystore-device-id") || "");
      if (!keyMatch || !DEVICE_ID_PATTERN.test(device)) {
        return bad("credentials_missing", 401);
      }
      const challenge = await issueDeviceChallenge(
        env,
        await deviceSubject("trystore", keyMatch[1], device),
      );
      if (!challenge) return bad("device_challenge_unavailable", 503);
      return json({ challenge }, 200, {
        "cache-control": "no-store",
        vary: "authorization, x-trystore-device-id",
      });
    }

    // The character vault is no longer inside the IPA. Its sealed blobs live
    // in KV and are served only to a licensed device; the manifest is signed
    // like every other feed document. The version route is public because the
    // archive step uses it to confirm the published vault matches the feed key.
    if (path === "/api/patches/trystore/character-vault/version" && request.method === "GET") {
      if (!(await allowFeed(env, "vault-version", feedIP(request), 120, 60))) {
        return bad("rate_limited", 429);
      }
      const raw = await env.PATCHES.get(VAULT_MANIFEST_KEY);
      if (!raw) return bad("vault_unavailable", 404);
      try {
        const value = JSON.parse(raw);
        return json(
          {
            version: String(value?.version || ""),
            keyFingerprint: String(value?.keyFingerprint || ""),
            files: Array.isArray(value?.files) ? value.files.length : 0,
          },
          200,
          { "cache-control": "no-store" },
        );
      } catch {
        return bad("vault_unavailable", 503);
      }
    }

    if (path === "/api/patches/trystore/character-vault/manifest.json" && request.method === "GET") {
      if (!(await allowFeed(env, "vault-manifest", feedIP(request), 60, 60))) {
        return bad("rate_limited", 429);
      }
      const licence = await requireTryStoreLicense(request, env, "trystore");
      if (!licence.allowed) return licenceFailure(licence);
      if (!(await vaultAttestationAllowed(request, env, "trystore"))) {
        return bad("attestation_required", 403);
      }
      if (!(await withinLicenceFetchBudget(
        env,
        "vault-manifest",
        request,
        "trystore",
        Number(env.VAULT_MANIFEST_LIMIT_PER_HOUR || 24),
      ))) {
        return json({ error: "fetch_quota_exceeded" }, 429, { "retry-after": "600" });
      }
      const raw = await env.PATCHES.get(VAULT_MANIFEST_KEY);
      if (!raw) return bad("vault_unavailable", 404);
      let value;
      try {
        value = JSON.parse(raw);
      } catch {
        return bad("vault_unavailable", 503);
      }
      if (!value || typeof value !== "object"
          || !Array.isArray(value.files) || value.files.length === 0 || value.files.length > 64
          || typeof value.version !== "string" || !/^[A-Za-z0-9._-]{1,64}$/.test(value.version)) {
        return bad("vault_unavailable", 503);
      }
      return signedJson(env, value, 200, { "cache-control": "no-store" });
    }

    if (path.startsWith(VAULT_ROUTE_PREFIX) && request.method === "GET") {
      let relative;
      try {
        relative = decodeURIComponent(path.slice(VAULT_ROUTE_PREFIX.length));
      } catch {
        return bad("not_found", 404);
      }
      if (!VAULT_BLOB_PATH.test(relative)) return bad("not_found", 404);
      if (!(await allowFeed(env, "vault-blob", feedIP(request), 240, 60))) {
        return bad("rate_limited", 429);
      }
      const licence = await requireTryStoreLicense(request, env, "trystore");
      if (!licence.allowed) return licenceFailure(licence);
      if (!(await vaultAttestationAllowed(request, env, "trystore"))) {
        return bad("attestation_required", 403);
      }
      if (!(await withinLicenceFetchBudget(
        env,
        "vault-blob",
        request,
        "trystore",
        Number(env.VAULT_FETCH_LIMIT_PER_HOUR || 64),
      ))) {
        return json({ error: "fetch_quota_exceeded" }, 429, { "retry-after": "600" });
      }
      const bytes = await env.PATCHES.get(VAULT_BLOB_PREFIX + relative, "arrayBuffer");
      if (!bytes) return bad("not_found", 404);
      return new Response(bytes, {
        status: 200,
        headers: {
          "content-type": "application/octet-stream",
          "content-length": String(bytes.byteLength),
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
        },
      });
    }

    if (path === "/api/telegram/webhook" && request.method === "POST") {
      return telegramWebhook(request, env);
    }

    if (path === "/api/patches/trystore/app-attest/challenge") {
      return proxyAppAttest(request, env, "/api/v1/app-attest/challenge");
    }
    if (path === "/api/patches/trystore/app-attest/register") {
      return proxyAppAttest(request, env, "/api/v1/app-attest/register");
    }

    const manifestMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/manifest\.json$/);
    if (manifestMatch && request.method === "GET") {
      const project = projectKey(manifestMatch[1]);
      if (!project) return bad("unknown_project", 404);
      if (!(await allowFeed(env, "manifest", feedIP(request), 120, 60))) return bad("rate_limited", 429);
      const licence = await requireTryStoreLicense(request, env, project);
      if (!licence.allowed) return licenceFailure(licence);
      const manifest = await readManifest(env, project);
      return signedJson(env, manifest, 200, { "cache-control": "no-store" });
    }

    // App Attest is mandatory before TryStore's wrapped content key is released.
    const bundleKeyMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/bundle-key$/);
    if (bundleKeyMatch && request.method === "GET") {
      const project = projectKey(bundleKeyMatch[1]);
      if (!project) return bad("unknown_project", 404);
      if (project === "trystore") return bad("attestation_required", 405);
      if (!(await allowFeed(env, "bundle-key", feedIP(request), 10, 60))) return bad("rate_limited", 429);
      const licence = await requireTryStoreLicense(request, env, project);
      if (!licence.allowed) return licenceFailure(licence);
      // Fail closed on a version whose secret is missing: falling back to the
      // previous key would keep a retired key usable after a rotation.
      const version = await currentBundleKeyVersion(env, project);
      const secret = bundleKeySecret(env, version);
      if (!secret) return bad("key_unavailable", 503);
      return json({ valid: true, key: secret.encoded, keyVersion: version }, 200, {
        "cache-control": "no-store",
        vary: "authorization, x-trystore-device-id",
      });
    }
    if (bundleKeyMatch && request.method === "POST") {
      const project = projectKey(bundleKeyMatch[1]);
      if (!project) return bad("unknown_project", 404);
      if (project !== "trystore") return bad("method_not_allowed", 405);
      // App Attest is the preferred proof, but a build signed outside the App
      // Store cannot always produce an assertion (missing entitlement, a
      // development profile, or a re-signed bundle). The explicit mode header
      // selects a release bound to the live licence and device instead. It is
      // rate limited, and a licence that is expired, revoked, or used from a
      // different device still gets nothing.
      const attestationMode = String(request.headers.get("x-trystore-attestation-mode") || "").toLowerCase();
      let keyMode = "licence";
      if (attestationMode === "licence") {
        if (!(await allowFeed(env, "bundle-key-licence", feedIP(request), 10, 60))) {
          return bad("rate_limited", 429);
        }
        const licence = await requireTryStoreLicense(request, env, project);
        if (!licence.allowed) return licenceFailure(licence);
        const proof = await verifyDeviceProof(env, request, project);
        if (!proof.ok) {
          return json({ valid: false, outcome: proof.reason, error: proof.reason }, 401, {
            "cache-control": "no-store",
            vary: "authorization, x-trystore-device-id",
          });
        }
      } else {
        const authorization = await proxyAppAttest(
          request,
          env,
          "/api/v1/app-attest/authorize-bundle-key",
        );
        if (!authorization.ok) return authorization;
        let authorizationResult;
        try {
          authorizationResult = await authorization.json();
        } catch {
          return bad("attestation_unavailable", 503);
        }
        if (authorizationResult.valid !== true) return bad("attestation_required", 401);
        keyMode = "attest";
      }
      const version = await currentBundleKeyVersion(env, project);
      const secret = bundleKeySecret(env, version);
      if (!secret) return bad("key_unavailable", 503);
      const device = String(request.headers.get("x-trystore-device-id") || "");
      if (keyMode === "attest") {
        // Remember the attestation for a month: the vault strict-mode check
        // must hold after the 10-minute feed token expires.
        const keyMatch = (request.headers.get("authorization") || "")
          .match(/^Bearer\s+([A-Za-z0-9._-]{8,256})$/i);
        if (keyMatch && DEVICE_ID_PATTERN.test(device)) {
          await writeCachedLicence(
            env,
            "attest|" + await licenceSubject(project, keyMatch[1], device),
            30 * 86_400,
          );
        }
      }
      const minted = await mintFeedToken(env, project, device, version, keyMode);
      const expiresAt = new Date((nowSeconds() + FEED_KEY_TTL) * 1000).toISOString();
      return json({
        valid: true,
        key: secret.encoded,
        keyVersion: version,
        expiresAt,
        ...(minted
          ? { feedToken: minted.token, tokenExpiresAt: new Date(minted.expiresAt * 1000).toISOString() }
          : {}),
      }, 200, {
        "cache-control": "no-store",
        vary: "authorization, x-trystore-device-id",
      });
    }

    // Client sync report. The app posts one small JSON document per sync so the
    // operator can see what the device actually received without a debug build.
    const reportMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/report$/);
    if (reportMatch && request.method === "POST") {
      const project = projectKey(reportMatch[1]);
      if (!project) return bad("unknown_project", 404);
      if (!(await allowFeed(env, "report", feedIP(request), 10, 60))) return bad("rate_limited", 429);
      const licence = await requireTryStoreLicense(request, env, project);
      if (!licence.allowed) return licenceFailure(licence);
      const body = await request.text();
      if (!body || body.length > 32768) return bad("invalid_report", 400);
      // Stored verbatim for the operator view, so it must at least be JSON.
      try {
        JSON.parse(body);
      } catch {
        return bad("invalid_report", 400);
      }
      const stamp = new Date().toISOString();
      // One key per project. A timestamped copy turned a free licence into a
      // KV write amplifier: the daily write quota is 1,000 and the old route
      // wrote two values per report.
      await env.PATCHES.put(`reports/${project}/latest.json`, body, {
        expirationTtl: 60 * 60 * 24 * 7,
      });
      return json({ ok: true, at: stamp });
    }

    const blobMatch = path.match(/^\/patches\/([a-z0-9-]+)\/(.+)$/);
    if (blobMatch && request.method === "GET") {
      const project = projectKey(blobMatch[1]);
      if (!project) return bad("unknown_project", 404);
      if (!(await allowFeed(env, "blob", feedIP(request), 120, 60))) return bad("rate_limited", 429);
      const licence = await requireTryStoreLicense(request, env, project);
      if (!licence.allowed) return licenceFailure(licence);
      if (LICENSED_PATCH_PROJECTS.has(project)
          && !(await withinLicenceFetchBudget(
            env,
            "patch-blob",
            request,
            project,
            Number(env.PATCH_FETCH_LIMIT_PER_HOUR || 160),
          ))) {
        return json({ error: "fetch_quota_exceeded" }, 429, { "retry-after": "600" });
      }
      const file = decodeURIComponent(blobMatch[2]);
      if (sanitizeFile(file) !== file) return bad("invalid_file", 400);
      let blob = null;
      if (env.DB) {
        try {
          const row = await env.DB.prepare(
            "SELECT bytes FROM feed_blobs WHERE project=?1 AND name=?2",
          ).bind(project, file).first();
          if (row?.bytes != null) blob = bytesOf(row.bytes);
        } catch {}
      }
      if (!blob) {
        blob = await env.PATCHES.get(`patches/${project}/${file}`, "arrayBuffer");
      }
      if (!blob) return bad("not_found", 404);
      const licensed = LICENSED_PATCH_PROJECTS.has(project);
      return new Response(blob, {
        headers: {
          "content-type": "application/octet-stream",
          "content-length": String(blob.byteLength),
          "cache-control": licensed ? "no-store" : "public, max-age=31536000, immutable",
          ...(licensed ? { vary: "authorization, x-trystore-device-id" } : {}),
        },
      });
    }

    return bad("not_found", 404);
  },
};

export { repackForTarget, parsePackage, decryptPayload };
