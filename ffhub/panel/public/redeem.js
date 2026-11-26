// The app opens the panel as `/#t=<token>`. A fragment never reaches the
// Worker, so an anonymous visit lands on the login screen; this script reads
// the fragment there, exchanges it for the HttpOnly cookie and reloads the
// panel. Without it the handoff dead-ends on a form the user cannot fill.
//
// The fragment is removed before the request so the token does not stay in the
// address bar or in history.

const status = document.getElementById("redeem-status");

function message(text) {
  if (status) status.textContent = text;
}

async function redeem() {
  if (!location.hash.startsWith("#t=")) return;

  let token = "";
  try {
    token = decodeURIComponent(location.hash.slice(3));
  } catch {
    token = "";
  }
  history.replaceState(null, "", location.pathname + location.search);

  if (!token) {
    message("Ese enlace no trae ningún token. Ábrelo de nuevo desde la app.");
    return;
  }

  message("Abriendo el panel…");

  try {
    const response = await fetch("/api/session", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }).toString(),
      redirect: "manual",
    });
    // A same-origin 303 is normally surfaced as an opaque redirect (status 0)
    // and still stores the cookie; a 200 here would be the login page again.
    // Older engines expose the 3xx directly, so accept that too.
    if (
      response.ok ||
      response.type === "opaqueredirect" ||
      (response.status >= 300 && response.status < 400)
    ) {
      location.replace("/");
      return;
    }
    message("Ese enlace ya no vale. Ábrelo de nuevo desde la app.");
  } catch {
    message("No se pudo abrir la sesión. Inténtalo de nuevo desde la app.");
  }
}

redeem();
