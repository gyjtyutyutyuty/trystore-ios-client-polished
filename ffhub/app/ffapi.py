from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any

import httpx

# The panel's region picker is not the provider's vocabulary: US, NA and LATAM
# all answer under `br`, so the region sent upstream is stored apart from the
# region the provider echoes back for the account.
PANEL_TO_PROVIDER_REGION = {
    "us": "br",
    "na": "br",
    "latam": "br",
    "br": "br",
    "sg": "sg",
    "id": "id",
    "th": "th",
    "vn": "vn",
    "my": "my",
}

USER_AGENT = "FreeFireAPILab/1.0"


class ProviderError(RuntimeError):
    code = "provider_error"


class ProviderAuthError(ProviderError):
    code = "provider_auth"


class ProviderRateLimited(ProviderError):
    code = "provider_rate_limited"

    def __init__(self, retry_after: float) -> None:
        super().__init__(f"provider rate limited, retry after {retry_after:.0f}s")
        self.retry_after = retry_after


class ProfileNotFound(ProviderError):
    code = "profile_not_found"


class ProviderBadResponse(ProviderError):
    code = "provider_bad_response"


class ImageUnavailable(ProviderError):
    code = "image_unavailable"


@dataclass(frozen=True)
class Profile:
    uid: str
    account_id: str
    nickname: str
    region: str
    avatar_id: str
    # None means the provider did not publish an equipment list at all, which is
    # a different answer from a player who is wearing nothing.
    clothes: tuple[str, ...] | None
    raw: dict[str, Any] = field(default_factory=dict, repr=False)

    @property
    def clothes_state(self) -> str:
        if self.clothes is None:
            return "unavailable"
        return "empty" if not self.clothes else "available"


def provider_region(panel_region: str) -> str:
    key = (panel_region or "").strip().lower()
    if key not in PANEL_TO_PROVIDER_REGION:
        raise ValueError(f"unsupported region: {panel_region!r}")
    return PANEL_TO_PROVIDER_REGION[key]


def _as_id(value: Any) -> str | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        text = value.strip()
        return text or None
    return None


def _normalize_clothes(payload: dict[str, Any]) -> tuple[str, ...] | None:
    if "clothes" not in payload or payload["clothes"] is None:
        return None
    raw = payload["clothes"]
    if not isinstance(raw, (list, tuple)):
        raise ProviderBadResponse("profileInfo.clothes is not a list")
    seen: dict[str, None] = {}
    for entry in raw:
        if isinstance(entry, dict):
            candidate = _as_id(entry.get("itemId") or entry.get("itemID") or entry.get("id"))
        else:
            candidate = _as_id(entry)
        if candidate is None:
            raise ProviderBadResponse("profileInfo.clothes contains an entry without an id")
        seen.setdefault(candidate, None)
    return tuple(seen)


def parse_profile(uid: str, payload: dict[str, Any]) -> Profile:
    if not isinstance(payload, dict):
        raise ProviderBadResponse("profile payload is not an object")
    basic = payload.get("basicInfo") or {}
    profile_info = payload.get("profileInfo") or {}
    if not isinstance(basic, dict) or not isinstance(profile_info, dict):
        raise ProviderBadResponse("basicInfo/profileInfo are not objects")

    # Deliberately lenient: some responses omit accountId entirely, and a
    # missing field is not evidence of a mismatched account.
    account_id = _as_id(basic.get("accountId")) or uid
    if account_id != uid:
        # A mismatch means the provider answered about someone else; serving it
        # would attach another player's outfit to the requested UID.
        raise ProviderBadResponse(f"accountId {account_id} does not match requested uid {uid}")

    nickname = basic.get("nickname")
    region = _as_id(basic.get("region")) or ""
    avatar_id = _as_id(profile_info.get("avatarId"))
    if avatar_id is None:
        raise ProviderBadResponse("profileInfo.avatarId is missing")

    return Profile(
        uid=uid,
        account_id=account_id,
        nickname=nickname if isinstance(nickname, str) else "",
        region=region,
        avatar_id=avatar_id,
        clothes=_normalize_clothes(profile_info),
        raw={
            "nickname": nickname if isinstance(nickname, str) else "",
            "region": region,
            "avatar_id": avatar_id,
        },
    )


class FireApiClient:
    def __init__(
        self,
        *,
        api_key: str,
        api_base: str,
        timeout: float = 20.0,
        attempts: int = 3,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._api_base = api_base.rstrip("/")
        self._attempts = max(1, attempts)
        self._client = httpx.AsyncClient(
            timeout=timeout,
            transport=transport,
            headers={
                "x-api-key": api_key,
                "User-Agent": USER_AGENT,
                "Accept": "application/json, image/*",
            },
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> "FireApiClient":
        return self

    async def __aexit__(self, *_exc: object) -> None:
        await self.aclose()

    async def _get(
        self,
        path: str,
        params: dict[str, str],
        *,
        accept: str,
        not_found: type[ProviderError],
    ) -> httpx.Response:
        delay = 0.5
        last: ProviderError | None = None
        for attempt in range(1, self._attempts + 1):
            try:
                response = await self._client.get(
                    f"{self._api_base}{path}", params=params, headers={"Accept": accept}
                )
            except httpx.HTTPError as exc:
                last = ProviderError(f"transport failure: {exc.__class__.__name__}")
                if attempt == self._attempts:
                    raise last from None
            else:
                if response.status_code == 401 or response.status_code == 403:
                    raise ProviderAuthError("provider rejected the API key")
                if response.status_code == 404:
                    # Which 404 this is depends on the endpoint: a missing image
                    # must not be reported as a missing player.
                    raise not_found(f"provider returned 404 for {path}")
                if response.status_code == 429:
                    retry_after = _retry_after_seconds(response)
                    if attempt == self._attempts:
                        raise ProviderRateLimited(retry_after) from None
                    await asyncio.sleep(retry_after)
                    continue
                if response.status_code >= 500:
                    last = ProviderError(f"provider returned {response.status_code}")
                    if attempt == self._attempts:
                        raise last from None
                elif response.status_code >= 400:
                    raise ProviderBadResponse(f"provider returned {response.status_code}")
                else:
                    return response
            await asyncio.sleep(delay)
            delay = min(delay * 2, 8.0)
        raise last or ProviderError("provider request failed")

    async def profile(self, uid: str, panel_region: str) -> Profile:
        response = await self._get(
            "/info",
            {"region": provider_region(panel_region), "uid": uid},
            accept="application/json",
            not_found=ProfileNotFound,
        )
        try:
            payload = response.json()
        except ValueError:
            raise ProviderBadResponse("provider returned non-JSON for /info") from None
        return parse_profile(uid, payload)

    async def image(self, item_id: str) -> tuple[bytes, str]:
        response = await self._get(
            "/image", {"itemID": item_id}, accept="image/*", not_found=ImageUnavailable
        )
        content_type = response.headers.get("content-type", "").split(";")[0].strip().lower()
        if content_type not in {"image/png", "image/jpeg"}:
            raise ImageUnavailable(f"provider sent {content_type or 'no content type'}")
        body = response.content
        if not body:
            raise ImageUnavailable("provider sent an empty image")
        return body, content_type


def _retry_after_seconds(response: httpx.Response) -> float:
    raw = response.headers.get("retry-after", "").strip()
    if raw:
        try:
            return max(0.0, min(float(raw), 300.0))
        except ValueError:
            pass
    return 5.0
