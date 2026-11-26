export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/api/")) {
      if (!env.BACKEND_URL || !env.HUB_TOKEN) {
        return Response.json({ error: "backend_not_configured" }, { status: 500 });
      }
      const target = new URL(url.pathname.slice(4) + url.search, env.BACKEND_URL);
      const headers = new Headers(request.headers);
      headers.set("authorization", `Bearer ${env.HUB_TOKEN}`);
      headers.delete("host");
      headers.delete("cf-connecting-ip");

      const isBodyless = request.method === "GET" || request.method === "HEAD";
      const upstream = await fetch(target, {
        method: request.method,
        headers,
        body: isBodyless ? undefined : request.body,
        redirect: "manual",
      });

      const out = new Headers(upstream.headers);
      out.delete("set-cookie");
      out.delete("access-control-allow-origin");
      return new Response(upstream.body, { status: upstream.status, headers: out });
    }

    return env.ASSETS.fetch(request);
  },
};
