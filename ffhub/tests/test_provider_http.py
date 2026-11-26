from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.ffapi import (
    FireApiClient,
    ImageUnavailable,
    ProfileNotFound,
    ProviderAuthError,
    ProviderRateLimited,
    ProviderBadResponse,
)


def make_client(handler, attempts: int = 1) -> FireApiClient:
    return FireApiClient(
        api_key="test-key-not-real",
        api_base="https://provider.invalid/api/v1",
        attempts=attempts,
        transport=httpx.MockTransport(handler),
    )


def run_profile(handler, attempts: int = 1):
    async def go():
        async with make_client(handler, attempts) as client:
            return await client.profile("11807385", "us")

    return asyncio.run(go())


def run_image(handler, attempts: int = 1):
    async def go():
        async with make_client(handler, attempts) as client:
            return await client.image("203000196")

    return asyncio.run(go())


def test_info_404_is_a_missing_profile() -> None:
    with pytest.raises(ProfileNotFound):
        run_profile(lambda request: httpx.Response(404))


def test_image_404_is_a_missing_image_not_a_missing_player() -> None:
    with pytest.raises(ImageUnavailable):
        run_image(lambda request: httpx.Response(404))


def test_rejected_key_names_the_cause() -> None:
    with pytest.raises(ProviderAuthError):
        run_profile(lambda request: httpx.Response(401))


def test_rate_limit_honours_retry_after() -> None:
    handler = lambda request: httpx.Response(429, headers={"retry-after": "7"})  # noqa: E731
    with pytest.raises(ProviderRateLimited) as caught:
        run_profile(handler)
    assert caught.value.retry_after == 7.0


def test_retry_after_is_clamped() -> None:
    handler = lambda request: httpx.Response(429, headers={"retry-after": "99999"})  # noqa: E731
    with pytest.raises(ProviderRateLimited) as caught:
        run_profile(handler)
    assert caught.value.retry_after == 300.0


def test_region_is_translated_on_the_wire() -> None:
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["params"] = dict(request.url.params)
        seen["key"] = request.headers.get("x-api-key")
        return httpx.Response(
            200,
            json={
                "basicInfo": {"accountId": "11807385", "nickname": "Carlos", "region": "US"},
                "profileInfo": {"avatarId": "102000015", "clothes": ["203000196"]},
            },
        )

    profile = run_profile(handler)
    assert seen["params"] == {"region": "br", "uid": "11807385"}
    assert seen["key"] == "test-key-not-real"
    assert profile.region == "US"
    assert profile.avatar_id == "102000015"


def test_image_content_type_is_enforced() -> None:
    handler = lambda request: httpx.Response(  # noqa: E731
        200, content=b"<html>", headers={"content-type": "text/html"}
    )
    with pytest.raises(ImageUnavailable):
        run_image(handler)


def test_image_accepts_png_and_keeps_its_type() -> None:
    handler = lambda request: httpx.Response(  # noqa: E731
        200, content=b"\x89PNG\r\n\x1a\n", headers={"content-type": "image/png; charset=binary"}
    )
    body, content_type = run_image(handler)
    assert content_type == "image/png"
    assert body.startswith(b"\x89PNG")


def test_non_json_info_is_refused() -> None:
    handler = lambda request: httpx.Response(  # noqa: E731
        200, content=b"not json", headers={"content-type": "application/json"}
    )
    with pytest.raises(ProviderBadResponse):
        run_profile(handler)


def test_json_round_trip_of_a_minimal_profile() -> None:
    payload = {
        "basicInfo": {"accountId": "11807385", "nickname": "N", "region": "BR"},
        "profileInfo": {"avatarId": "102000015", "clothes": []},
    }
    handler = lambda request: httpx.Response(  # noqa: E731
        200, content=json.dumps(payload).encode(), headers={"content-type": "application/json"}
    )
    profile = run_profile(handler)
    assert profile.clothes == ()
    assert profile.clothes_state == "empty"
