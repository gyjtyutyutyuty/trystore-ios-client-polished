// Free Fire API Hub client, Workers flavour.
//
// Same contract as app/ffapi.py: US/NA/LATAM are answered by `br`, the account
// id must match the requested uid, and an absent clothes list is not the same
// thing as an empty one.

export const PROVIDER_BASE = "https://developers.freefirecommunity.com/api/v1";

const REGIONS = {
  us: "br",
  na: "br",
  latam: "br",
  br: "br",
  sg: "sg",
  id: "id",
  th: "th",
  vn: "vn",
  my: "my",
};

const ITEM_ID_KEYS = ["itemId", "itemID", "id"];

export class ProviderFailure extends Error {
  constructor(code, message, retryAfter = 0) {
    super(message);
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

export function providerRegion(region) {
  const key = String(region ?? "").trim().toLowerCase();
  if (!Object.hasOwn(REGIONS, key)) {
    throw new ProviderFailure("invalid_region", `unsupported region: ${region}`);
  }
  return REGIONS[key];
}

function asId(value) {
  if (typeof value === "boolean") return null;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "string") {
    const text = value.trim();
    return text || null;
  }
  return null;
}

function normalizeClothes(info) {
  if (!Object.hasOwn(info, "clothes") || info.clothes === null) return null;
  const raw = info.clothes;
  if (!Array.isArray(raw)) {
    throw new ProviderFailure("provider_bad_response", "profileInfo.clothes is not a list");
  }
  const seen = new Set();
  for (const entry of raw) {
    let candidate = null;
    if (entry && typeof entry === "object") {
      for (const key of ITEM_ID_KEYS) {
        candidate = asId(entry[key]);
        if (candidate) break;
      }
    } else {
      candidate = asId(entry);
    }
    if (!candidate) {
      throw new ProviderFailure(
        "provider_bad_response",
        "profileInfo.clothes contains an entry without an id",
      );
    }
    seen.add(candidate);
  }
  return [...seen];
}

export function parseProfile(uid, payload) {
  if (!payload || typeof payload !== "object") {
    throw new ProviderFailure("provider_bad_response", "profile payload is not an object");
  }
  const basic = payload.basicInfo ?? {};
  const info = payload.profileInfo ?? {};
  if (typeof basic !== "object" || typeof info !== "object") {
    throw new ProviderFailure("provider_bad_response", "basicInfo/profileInfo are not objects");
  }

  const accountId = asId(basic.accountId) ?? String(uid);
  if (accountId !== String(uid)) {
    throw new ProviderFailure(
      "provider_bad_response",
      `accountId ${accountId} does not match requested uid ${uid}`,
    );
  }

  const avatarId = asId(info.avatarId);
  if (!avatarId) {
    throw new ProviderFailure("provider_bad_response", "profileInfo.avatarId is missing");
  }

  const clothes = normalizeClothes(info);
  return {
    uid: String(uid),
    nickname: typeof basic.nickname === "string" ? basic.nickname : "",
    region: asId(basic.region) ?? "",
    avatarId,
    clothes,
    clothesState: clothes === null ? "unavailable" : clothes.length ? "available" : "empty",
  };
}

function headersFor(apiKey, accept) {
  return { "x-api-key": apiKey, accept, "user-agent": "FFHub-Panel/1.0" };
}

export async function fetchProfile({ apiKey, apiBase, uid, region, fetchImpl = fetch, timeoutMs = 20000 }) {
  const url = new URL(`${apiBase}/info`);
  url.searchParams.set("region", providerRegion(region));
  url.searchParams.set("uid", uid);

  const response = await fetchImpl(url, {
    headers: headersFor(apiKey, "application/json"),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (response.status === 401 || response.status === 403) {
    throw new ProviderFailure("provider_auth", "provider rejected the API key");
  }
  if (response.status === 404) {
    throw new ProviderFailure("profile_not_found", "provider returned 404 for /info");
  }
  if (response.status === 429) {
    const retry = Number(response.headers.get("retry-after") ?? "5");
    throw new ProviderFailure(
      "provider_rate_limited",
      "provider rate limited",
      Number.isFinite(retry) ? Math.min(Math.max(retry, 0), 300) : 5,
    );
  }
  if (!response.ok) {
    throw new ProviderFailure("provider_bad_response", `provider returned ${response.status}`);
  }

  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new ProviderFailure("provider_bad_response", "provider returned non-JSON for /info");
  }
  return parseProfile(uid, payload);
}

export async function fetchImage({ apiKey, apiBase, itemId, fetchImpl = fetch, timeoutMs = 20000 }) {
  const url = new URL(`${apiBase}/image`);
  url.searchParams.set("itemID", itemId);

  const response = await fetchImpl(url, {
    headers: headersFor(apiKey, "image/*"),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (response.status === 404) {
    throw new ProviderFailure("image_unavailable", "provider returned 404 for /image");
  }
  if (response.status === 401 || response.status === 403) {
    throw new ProviderFailure("provider_auth", "provider rejected the API key");
  }
  if (!response.ok) {
    throw new ProviderFailure("provider_bad_response", `provider returned ${response.status}`);
  }

  const contentType = (response.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
  if (contentType !== "image/png" && contentType !== "image/jpeg") {
    throw new ProviderFailure("image_unavailable", `provider sent ${contentType || "no content type"}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0) {
    throw new ProviderFailure("image_unavailable", "provider sent an empty image");
  }
  return { bytes, contentType };
}
