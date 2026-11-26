from __future__ import annotations

import pytest

from app.ffapi import (
    ProviderBadResponse,
    ProfileNotFound,
    ProviderRateLimited,
    parse_profile,
    provider_region,
)


def test_panel_regions_collapse_to_provider_codes() -> None:
    for panel in ("us", "US", "na", "latam", "br"):
        assert provider_region(panel) == "br"
    assert provider_region("sg") == "sg"
    assert provider_region(" ID ") == "id"


def test_unknown_region_is_rejected() -> None:
    with pytest.raises(ValueError):
        provider_region("xx")


def test_profile_parses_ids_and_region() -> None:
    profile = parse_profile(
        "11807385",
        {
            "basicInfo": {"accountId": "11807385", "nickname": "Cᴀʀʟᴏs", "region": "US"},
            "profileInfo": {
                "avatarId": 102000015,
                "clothes": [211000087, {"itemId": "203000196"}, "204000103"],
            },
        },
    )
    assert profile.avatar_id == "102000015"
    assert profile.region == "US"
    assert profile.clothes == ("211000087", "203000196", "204000103")
    assert profile.clothes_state == "available"


def test_missing_clothes_differs_from_empty() -> None:
    payload = {"basicInfo": {"accountId": "1"}, "profileInfo": {"avatarId": "2"}}
    missing = parse_profile("1", payload)
    empty = parse_profile("1", {**payload, "profileInfo": {"avatarId": "2", "clothes": []}})
    assert missing.clothes is None and missing.clothes_state == "unavailable"
    assert empty.clothes == () and empty.clothes_state == "empty"


def test_account_mismatch_is_refused() -> None:
    with pytest.raises(ProviderBadResponse):
        parse_profile(
            "11807385",
            {"basicInfo": {"accountId": "99999999"}, "profileInfo": {"avatarId": "1"}},
        )


def test_missing_avatar_is_refused() -> None:
    with pytest.raises(ProviderBadResponse):
        parse_profile("11807385", {"basicInfo": {"accountId": "11807385"}, "profileInfo": {}})


def test_clothes_entry_without_id_is_refused() -> None:
    with pytest.raises(ProviderBadResponse):
        parse_profile(
            "11807385",
            {
                "basicInfo": {"accountId": "11807385"},
                "profileInfo": {"avatarId": "1", "clothes": [{"name": "hat"}]},
            },
        )


def test_rate_limit_carries_retry_after() -> None:
    error = ProviderRateLimited(12.0)
    assert error.retry_after == 12.0
    assert isinstance(error, Exception)


def test_not_found_is_distinct() -> None:
    assert ProfileNotFound.code == "profile_not_found"
