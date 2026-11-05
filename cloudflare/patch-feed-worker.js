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
const MANIFEST_SCHEMA = 1;
const MAGIC = Buffer.from("3105PATCH\0", "latin1");
const RESELLER_FALLBACK = "https://jvztxnx-global-control.burgoajustin.workers.dev";
const LEGACY_ADMIN_IDS = ["5869209007"];
const PATCH_COMMANDS = new Set(["/patches", "/projects", "/upload", "/list", "/remove", "/cancel"]);

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });

const bad = (message, status = 400) => json({ error: message }, status);

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
  return parsed;
}

async function writeManifest(env, project, manifest) {
  manifest.schemaVersion = MANIFEST_SCHEMA;
  manifest.project = project;
  manifest.updatedAt = new Date().toISOString();
  await env.PATCHES.put(`patches/${project}/manifest.json`, JSON.stringify(manifest, null, 2));
}

async function publishPatch(env, project, file, bytes) {
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
  return [
    [
      { text: "🔁 Replace", callback_data: `pm:r:${project}:${index}` },
      { text: "🗑 Delete", callback_data: `pm:d:${project}:${index}` },
    ],
    [{ text: "⬇️ Download", url: downloadURL }],
    [{ text: "⬅️ Back", callback_data: `pm:back:${project}` }],
  ];
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
  if (request.headers.get("X-Telegram-Bot-Api-Secret-Token") !== env.TELEGRAM_WEBHOOK_SECRET) {
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

/* ------------------------------------------------------------------ */
/* HTTP routes                                                         */
/* ------------------------------------------------------------------ */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") {
      return json({ status: "ok", service: "trystore-patch-feed" });
    }

    if (path === "/api/telegram/webhook" && request.method === "POST") {
      return telegramWebhook(request, env);
    }

    const manifestMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/manifest\.json$/);
    if (manifestMatch && request.method === "GET") {
      const project = projectKey(manifestMatch[1]);
      if (!project) return bad("unknown_project", 404);
      const manifest = await readManifest(env, project);
      return json(manifest, 200, { "cache-control": "no-store" });
    }

    // Client sync report. The app posts one small JSON document per sync so the
    // operator can see what the device actually received without a debug build.
    const reportMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/report$/);
    if (reportMatch && request.method === "POST") {
      const project = projectKey(reportMatch[1]);
      if (!project) return bad("unknown_project", 404);
      const body = await request.text();
      if (!body || body.length > 32768) return bad("invalid_report", 400);
      const stamp = new Date().toISOString();
      await env.PATCHES.put(`reports/${project}/latest.json`, body, {
        expirationTtl: 60 * 60 * 24 * 7,
      });
      await env.PATCHES.put(`reports/${project}/${stamp}.json`, body, {
        expirationTtl: 60 * 60 * 24 * 7,
      });
      return json({ ok: true, at: stamp });
    }

    const blobMatch = path.match(/^\/patches\/([a-z0-9-]+)\/(.+)$/);
    if (blobMatch && request.method === "GET") {
      const project = projectKey(blobMatch[1]);
      if (!project) return bad("unknown_project", 404);
      const file = decodeURIComponent(blobMatch[2]);
      if (sanitizeFile(file) !== file) return bad("invalid_file", 400);
      const blob = await env.PATCHES.get(`patches/${project}/${file}`, "arrayBuffer");
      if (!blob) return bad("not_found", 404);
      return new Response(blob, {
        headers: {
          "content-type": "application/octet-stream",
          "content-length": String(blob.byteLength),
          "cache-control": "public, max-age=31536000, immutable",
        },
      });
    }

    return bad("not_found", 404);
  },
};

export { repackForTarget, parsePackage, decryptPayload };
