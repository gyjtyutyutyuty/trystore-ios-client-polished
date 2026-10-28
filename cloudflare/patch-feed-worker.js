/**
 * TryStore patch feed worker.
 *
 * Serves signed-off patch manifests and package blobs from R2, and accepts
 * uploads from the Telegram bot so the in-app patch list can change without a
 * new IPA. One R2 bucket, one namespace per project.
 *
 * Routes
 *   GET  /health
 *   GET  /api/patches/:project/manifest.json
 *   GET  /patches/:project/:file
 *   POST /api/telegram/webhook            (secret token header required)
 *
 * R2 layout
 *   patches/:project/manifest.json
 *   patches/:project/:file
 *
 * Bot commands (owner only)
 *   /projects
 *   /upload <project>      then send the .TRYSTORE / .3105 / .tipa document
 *   /remove <project> <file>
 *   /list <project>
 */

const PROJECTS = ["trystore", "apple-music", "hyper-regedit"];
const SESSION_TTL_SECONDS = 900;
const MAX_UPLOAD_BYTES = 64 * 1024 * 1024;
const PATCH_EXTENSIONS = [".trystore", ".3105", ".tipa"];
const MANIFEST_SCHEMA = 1;

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });

const bad = (message, status = 400) => json({ error: message }, status);

async function tg(env, method, body) {
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return response.json().catch(() => ({ ok: false }));
}

const sha256 = async (buffer) => {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
};

const sanitizeFile = (name) => {
  const base = String(name || "").split(/[\\/]/).pop().trim();
  const lower = base.toLowerCase();
  if (!base || base.length > 120) return null;
  if (!PATCH_EXTENSIONS.some((extension) => lower.endsWith(extension))) return null;
  if (!/^[A-Za-z0-9 ._()\-]+$/.test(base)) return null;
  return base;
};

const projectKey = (value) => {
  const slug = String(value || "").trim().toLowerCase();
  return PROJECTS.includes(slug) ? slug : null;
};

async function readManifest(env, project) {
  const object = await env.PATCHES.get(`patches/${project}/manifest.json`);
  if (!object) {
    return { schemaVersion: MANIFEST_SCHEMA, project, updatedAt: null, patches: [] };
  }
  const parsed = await object.json().catch(() => null);
  if (!parsed || !Array.isArray(parsed.patches)) {
    return { schemaVersion: MANIFEST_SCHEMA, project, updatedAt: null, patches: [] };
  }
  return parsed;
}

async function writeManifest(env, project, manifest) {
  manifest.schemaVersion = MANIFEST_SCHEMA;
  manifest.project = project;
  manifest.updatedAt = new Date().toISOString();
  await env.PATCHES.put(`patches/${project}/manifest.json`, JSON.stringify(manifest, null, 2), {
    httpMetadata: { contentType: "application/json; charset=utf-8", cacheControl: "no-store" },
  });
}

async function publishPatch(env, project, file, bytes) {
  const digest = await sha256(bytes);
  const objectKey = `patches/${project}/${file}`;
  await env.PATCHES.put(objectKey, bytes, {
    httpMetadata: {
      contentType: "application/octet-stream",
      cacheControl: "public, max-age=31536000, immutable",
    },
    customMetadata: { sha256: digest, uploadedAt: new Date().toISOString() },
  });

  const manifest = await readManifest(env, project);
  const entry = {
    file,
    name: file.replace(/\.(trystore|3105|tipa)$/i, ""),
    sha256: digest,
    size: bytes.byteLength,
    version: new Date().toISOString(),
    url: `/patches/${project}/${encodeURIComponent(file)}`,
  };
  const index = manifest.patches.findIndex((item) => item.file.toLowerCase() === file.toLowerCase());
  if (index >= 0) manifest.patches[index] = entry;
  else manifest.patches.push(entry);
  manifest.patches.sort((a, b) => a.name.localeCompare(b.name));
  await writeManifest(env, project, manifest);
  return entry;
}

async function removePatch(env, project, file) {
  await env.PATCHES.delete(`patches/${project}/${file}`);
  const manifest = await readManifest(env, project);
  manifest.patches = manifest.patches.filter((item) => item.file.toLowerCase() !== file.toLowerCase());
  await writeManifest(env, project, manifest);
}

async function handleDocument(env, message, chatId) {
  const sessionKey = `session:${chatId}`;
  const session = await env.PATCHES.get(sessionKey);
  if (!session) {
    await tg(env, "sendMessage", {
      chat_id: chatId,
      text: "No active upload. Send /upload <project> first.",
    });
    return;
  }
  const { project, createdAt } = JSON.parse(session);
  if (Date.now() / 1000 - createdAt > SESSION_TTL_SECONDS) {
    await env.PATCHES.delete(sessionKey);
    await tg(env, "sendMessage", { chat_id: chatId, text: "Upload session expired. Send /upload again." });
    return;
  }

  const document = message.document;
  if (!document) return;
  if (document.file_size && document.file_size > MAX_UPLOAD_BYTES) {
    await tg(env, "sendMessage", { chat_id: chatId, text: "File too large (64 MB ceiling)." });
    return;
  }
  const file = sanitizeFile(document.file_name);
  if (!file) {
    await tg(env, "sendMessage", {
      chat_id: chatId,
      text: "Rejected. Allowed extensions: .TRYSTORE .3105 .tipa, safe characters only.",
    });
    return;
  }

  const lookup = await tg(env, "getFile", { file_id: document.file_id });
  if (!lookup.ok) {
    await tg(env, "sendMessage", { chat_id: chatId, text: "Telegram refused the file lookup." });
    return;
  }
  const fileResponse = await fetch(
    `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${lookup.result.file_path}`,
  );
  if (!fileResponse.ok) {
    await tg(env, "sendMessage", { chat_id: chatId, text: "Download from Telegram failed." });
    return;
  }
  const bytes = await fileResponse.arrayBuffer();
  const entry = await publishPatch(env, project, file, bytes);
  await env.PATCHES.delete(sessionKey);

  const base = env.PUBLIC_BASE_URL || "";
  await tg(env, "sendMessage", {
    chat_id: chatId,
    text: [
      `Published ${entry.file} → ${project}`,
      `sha256 ${entry.sha256}`,
      `size ${entry.size} B`,
      `manifest ${base}/api/patches/${project}/manifest.json`,
    ].join("\n"),
  });
}

async function telegramWebhook(request, env) {
  if (request.headers.get("X-Telegram-Bot-Api-Secret-Token") !== env.TELEGRAM_WEBHOOK_SECRET) {
    return bad("unauthorized", 401);
  }
  const update = await request.json().catch(() => null);
  if (!update) return bad("invalid_update");

  const message = update.message;
  const callback = update.callback_query;
  const fromId = String(callback ? callback.from.id : message?.from?.id || "");
  const chatId = String(callback ? callback.message.chat.id : message?.chat?.id || "");
  if (callback) await tg(env, "answerCallbackQuery", { callback_query_id: callback.id, text: "OK" });

  const owner = String(env.TELEGRAM_OWNER_ID || "");
  if (!owner || fromId !== owner) {
    if (message) await tg(env, "sendMessage", { chat_id: chatId, text: "Not authorized." });
    return json({ ok: true });
  }

  if (message?.document) {
    await handleDocument(env, message, chatId);
    return json({ ok: true });
  }

  const text = String(message?.text || "").trim();
  if (!text.startsWith("/")) return json({ ok: true });
  const [command, ...args] = text.split(/\s+/);

  switch (command) {
    case "/start":
    case "/projects": {
      const lines = [];
      for (const project of PROJECTS) {
        const manifest = await readManifest(env, project);
        lines.push(`${project}: ${manifest.patches.length} patch(es)`);
      }
      await tg(env, "sendMessage", {
        chat_id: chatId,
        text: ["Projects:", ...lines, "", "Upload: /upload <project>, then send the file."].join("\n"),
      });
      break;
    }
    case "/upload": {
      const project = projectKey(args[0]);
      if (!project) {
        await tg(env, "sendMessage", { chat_id: chatId, text: `Project must be one of: ${PROJECTS.join(", ")}` });
        break;
      }
      await env.PATCHES.put(
        `session:${chatId}`,
        JSON.stringify({ project, createdAt: Math.floor(Date.now() / 1000) }),
        { expirationTtl: SESSION_TTL_SECONDS },
      );
      await tg(env, "sendMessage", {
        chat_id: chatId,
        text: `Send the .TRYSTORE file for ${project}. Same-name files replace the previous build.`,
      });
      break;
    }
    case "/list": {
      const project = projectKey(args[0]);
      if (!project) {
        await tg(env, "sendMessage", { chat_id: chatId, text: "Usage: /list <project>" });
        break;
      }
      const manifest = await readManifest(env, project);
      await tg(env, "sendMessage", {
        chat_id: chatId,
        text: manifest.patches.length
          ? manifest.patches.map((p) => `${p.name}  ${p.size}B  ${p.file}`).join("\n")
          : "Empty.",
      });
      break;
    }
    case "/remove": {
      const project = projectKey(args[0]);
      const file = sanitizeFile(args.slice(1).join(" "));
      if (!project || !file) {
        await tg(env, "sendMessage", { chat_id: chatId, text: "Usage: /remove <project> <file>" });
        break;
      }
      await removePatch(env, project, file);
      await tg(env, "sendMessage", { chat_id: chatId, text: `Removed ${file} from ${project}.` });
      break;
    }
    default:
      await tg(env, "sendMessage", { chat_id: chatId, text: "Unknown command. /projects /upload /list /remove" });
  }
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") return json({ status: "ok", service: "trystore-patch-feed" });

    if (path === "/api/telegram/webhook" && request.method === "POST") {
      return telegramWebhook(request, env);
    }

    const manifestMatch = path.match(/^\/api\/patches\/([a-z0-9-]+)\/manifest\.json$/);
    if (manifestMatch && request.method === "GET") {
      const project = projectKey(manifestMatch[1]);
      if (!project) return bad("unknown_project", 404);
      const manifest = await readManifest(env, project);
      return json(manifest, 200, { "cache-control": "public, max-age=60" });
    }

    const blobMatch = path.match(/^\/patches\/([a-z0-9-]+)\/(.+)$/);
    if (blobMatch && request.method === "GET") {
      const project = projectKey(blobMatch[1]);
      if (!project) return bad("unknown_project", 404);
      const file = decodeURIComponent(blobMatch[2]);
      if (sanitizeFile(file) !== file) return bad("invalid_file", 400);
      const object = await env.PATCHES.get(`patches/${project}/${file}`);
      if (!object) return bad("not_found", 404);
      return new Response(object.body, {
        headers: {
          "content-type": "application/octet-stream",
          "content-length": String(object.size),
          "cache-control": "public, max-age=31536000, immutable",
          etag: object.httpEtag,
        },
      });
    }

    return bad("not_found", 404);
  },
};
