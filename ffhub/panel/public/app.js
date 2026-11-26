const $ = (id) => document.getElementById(id);

let current = null;
let pollTimer = null;

const STATUS_TEXT = {
  queued: "En cola",
  generating: "Generando",
  ready: "Listo",
  partial: "Parcial",
  error: "Error",
};

async function api(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    ...options,
    headers: { "content-type": "application/json", ...(options.headers || {}) },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const code = payload?.detail?.error || payload?.error || `http_${response.status}`;
    // The panel is private now: no session means the login screen, not an error
    // the visitor cannot act on.
    if (response.status === 401 && code === "session_required") {
      location.assign("/login");
    }
    const error = new Error(code);
    error.code = code;
    error.status = response.status;
    throw error;
  }
  return payload;
}

function describe(error) {
  switch (error.code) {
    case "invalid_uid":
      return "UID inválido: de 5 a 15 dígitos.";
    case "invalid_region":
      return "Región no soportada.";
    case "profile_not_found":
      return "No existe un perfil con ese UID en esa región.";
    case "clothes_unavailable":
      return "El proveedor no publicó el equipamiento de esta cuenta.";
    case "clothes_empty":
      return "La cuenta no lleva prendas equipadas.";
    case "avatar_not_in_catalog":
      return "El cuerpo de ese avatar todavía no está en el catálogo 3D.";
    case "provider_rate_limited":
      return "El proveedor está limitando las consultas. Intenta en un momento.";
    case "provider_auth":
      return "La clave del proveedor fue rechazada.";
    case "provider_not_configured":
      return "El panel está publicado, pero todavía no tiene la clave del proveedor.";
    case "rate_limited":
      return "Demasiadas consultas seguidas. Espera un minuto.";
    default:
      return `No se pudo completar (${error.code}).`;
  }
}

function reset() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  $("player").hidden = true;
  $("viewer-wrap").hidden = true;
  $("download").hidden = true;
  $("job-status").textContent = "";
  $("clothes").replaceChildren();
}

function renderClothes(items) {
  const list = $("clothes");
  list.replaceChildren();
  for (const item of items) {
    const li = document.createElement("li");
    const figure = document.createElement("figure");
    const img = document.createElement("img");
    img.loading = "lazy";
    img.alt = `Prenda ${item.item_id}`;
    img.src = item.thumbnail_url;
    img.addEventListener("error", () => {
      img.replaceWith(Object.assign(document.createElement("div"), {
        className: "missing",
        textContent: item.item_id,
      }));
    });
    const caption = document.createElement("figcaption");
    // Un enlazado a medias deja el tipo en "unknown": mejor el id solo que
    // enseñar una palabra en inglés que además no informa de nada.
    caption.textContent = item.label ? `${item.label} · ${item.item_id}` : item.item_id;
    figure.append(img, caption);
    li.append(figure);
    list.append(li);
  }
}

async function lookup(event) {
  event?.preventDefault();
  reset();
  const uid = $("uid").value.trim();
  const region = $("region").value;
  $("status").textContent = "Consultando…";
  try {
    const profile = await api("/profile", {
      method: "POST",
      body: JSON.stringify({ uid, region }),
    });
    current = profile;
    $("nickname").textContent = profile.nickname || uid;
    $("meta").textContent = [
      `UID ${profile.uid}`,
      `región ${profile.region || "—"}`,
      `avatar ${profile.avatar_id}`,
      profile.clothes_state === "available" ? `${profile.clothes.length} prendas` : profile.clothes_state,
    ].join(" · ");
    renderClothes(profile.clothes);
    $("player").hidden = false;
    $("status").textContent = "";
    $("generate").disabled =
      profile.clothes_state !== "available" || !profile.avatar_in_catalog;
    if (profile.clothes_state !== "available") {
      $("job-status").textContent =
        profile.clothes_state === "empty"
          ? "La cuenta no lleva prendas equipadas."
          : "El proveedor no publicó el equipamiento de esta cuenta.";
    } else if (!profile.avatar_in_catalog) {
      $("job-status").textContent = "El cuerpo de ese avatar no está en el catálogo 3D.";
    }
  } catch (error) {
    $("status").textContent = describe(error);
  }
}

function poll(jobId) {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(async () => {
    try {
      const { job } = await api(`/jobs/${jobId}`);
      $("job-status").textContent = `${STATUS_TEXT[job.state] || job.state}${
        job.detail ? ` — ${job.detail}` : ""
      }`;
      if (job.state === "ready" || job.state === "partial") {
        clearInterval(pollTimer);
        pollTimer = null;
        const link = $("download");
        link.href = `/api${job.download_url}`;
        link.hidden = false;
        $("viewer").src = link.href;
        $("viewer-wrap").hidden = false;
      } else if (job.state === "error") {
        clearInterval(pollTimer);
        pollTimer = null;
      }
    } catch (error) {
      clearInterval(pollTimer);
      pollTimer = null;
      $("job-status").textContent = describe(error);
    }
  }, 2000);
}

async function generate() {
  if (!current) return;
  $("generate").disabled = true;
  $("job-status").textContent = "En cola…";
  try {
    const { job } = await api("/jobs", {
      method: "POST",
      body: JSON.stringify({
        uid: current.uid,
        region: $("region").value,
        avatar_id: current.avatar_id,
        // Send back the ids the player is looking at, so the GLB matches the card.
        items: current.clothes.map((item) => item.item_id),
      }),
    });
    $("job-status").textContent = STATUS_TEXT[job.state] || job.state;
    if (job.state === "ready" || job.state === "partial") {
      const link = $("download");
      link.href = `/api${job.download_url}`;
      link.hidden = false;
      $("viewer").src = link.href;
      $("viewer-wrap").hidden = false;
    } else {
      poll(job.id);
    }
  } catch (error) {
    $("job-status").textContent = describe(error);
  } finally {
    $("generate").disabled = false;
  }
}

/// What the session says about this browser. The admin gets one extra control:
/// every session opened with an app token can be revoked from here, and that
/// revocation happens in D1, so it reaches every isolate at once.
async function refreshSession() {
  let session;
  try {
    const response = await fetch("/api/session", { headers: { accept: "application/json" } });
    if (response.status === 401) {
      location.assign("/login");
      return;
    }
    if (!response.ok) return;
    session = await response.json();
  } catch {
    return;
  }

  $("session-role").textContent = session.role === "admin" ? "Administrador" : "Sesión de la app";
  if (session.role !== "admin") return;

  $("admin").hidden = false;
  const count = Number(session.active_sessions || 0);
  $("admin-meta").textContent =
    count === 0
      ? "No hay sesiones de la app abiertas."
      : `${count} ${count === 1 ? "sesión abierta" : "sesiones abiertas"} con token de la app.`;
}

async function logout() {
  $("logout").disabled = true;
  try {
    const response = await fetch("/api/session", { method: "DELETE" });
    if (response.ok) {
      location.assign("/login?out=1");
      return;
    }
  } catch {
    // Fall through: a failed logout must say so, not pretend it worked.
  }
  $("logout").disabled = false;
  $("status").textContent = "No se pudo cerrar la sesión. Inténtalo de nuevo.";
}

async function revokeSessions() {
  if (
    !window.confirm(
      "¿Cerrar todas las sesiones abiertas con token de la app? Los clientes tendrán que abrir el panel de nuevo desde la app.",
    )
  ) {
    return;
  }
  $("revoke").disabled = true;
  $("admin-status").textContent = "Revocando…";
  try {
    const response = await fetch("/api/session/revoke", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      $("admin-status").textContent =
        payload.error === "admin_required"
          ? "Sólo la sesión de administrador puede revocar."
          : "No se pudo revocar. Inténtalo de nuevo.";
      return;
    }
    const count = Number(payload.revoked || 0);
    $("admin-status").textContent =
      count === 0
        ? "No había sesiones abiertas."
        : `Se cerraron ${count} ${count === 1 ? "sesión" : "sesiones"}.`;
    await refreshSession();
  } catch {
    $("admin-status").textContent = "No se pudo revocar. Inténtalo de nuevo.";
  } finally {
    $("revoke").disabled = false;
  }
}

/// The app opens this page as `/#t=<token>`. The fragment never leaves the
/// browser, so it is not in any log; it is exchanged here for an HttpOnly
/// cookie and removed from the address bar so it cannot be copied or shared.
async function redeemTokenFromHash() {
  if (!location.hash.startsWith("#t=")) return false;
  const token = decodeURIComponent(location.hash.slice(3));
  history.replaceState(null, "", location.pathname + location.search);
  if (!token) return false;
  const response = await fetch("/api/session", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token }).toString(),
    redirect: "manual",
  });
  return response.ok || response.status === 0 || response.type === "opaqueredirect";
}

(async () => {
  try {
    await redeemTokenFromHash();
  } catch {
    // A broken token is just a failed login: the form is one click away.
    location.assign("/login");
    return;
  }
  await refreshSession();
})();

$("lookup").addEventListener("submit", lookup);
$("generate").addEventListener("click", generate);
$("logout").addEventListener("click", logout);
$("revoke").addEventListener("click", revokeSessions);
