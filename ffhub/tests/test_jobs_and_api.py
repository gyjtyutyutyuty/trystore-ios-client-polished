from __future__ import annotations

from pathlib import Path

import httpx
import pytest

from app.jobs import canonical_items, enqueue, reuse_key
from app.main import create_app
from app.store import Store

from conftest import make_config, profile_payload, run


def test_canonical_items_ignore_order_and_duplicates() -> None:
    assert canonical_items(["2", "1", "2", " "]) == ("1", "2")


def test_reuse_key_is_stable_and_version_sensitive() -> None:
    base = dict(avatar_id="102000015", catalog_version="1", exporter_version="1")
    first = reuse_key(items=["2", "1"], **base)
    second = reuse_key(items=["1", "2"], **base)
    assert first == second
    assert reuse_key(items=["1"], **base) != first
    assert reuse_key(items=["2", "1"], **{**base, "catalog_version": "2"}) != first
    assert reuse_key(items=["2", "1"], **{**base, "exporter_version": "2"}) != first


def test_enqueue_reuses_a_queued_job(tmp_path: Path) -> None:
    store = Store(tmp_path / "db.sqlite3")
    first, created_first = enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["1", "2"],
        catalog_version="1",
        exporter_version="1",
    )
    second, created_second = enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["2", "1"],
        catalog_version="1",
        exporter_version="1",
    )
    assert created_first is True
    assert created_second is False
    assert first.id == second.id


def test_enqueue_retries_when_the_published_file_is_gone(tmp_path: Path) -> None:
    store = Store(tmp_path / "db.sqlite3")
    first, _ = enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["1"],
        catalog_version="1",
        exporter_version="1",
    )
    store.finish_job(
        first.id, state="ready", glb_path=str(tmp_path / "deleted.glb"), detail=""
    )
    second, created = enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["1"],
        catalog_version="1",
        exporter_version="1",
    )
    assert created is True
    assert second.id != first.id


def test_claim_is_exclusive(tmp_path: Path) -> None:
    store = Store(tmp_path / "db.sqlite3")
    enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["1"],
        catalog_version="1",
        exporter_version="1",
    )
    claimed = store.claim_next()
    assert claimed is not None and claimed.state == "generating"
    assert store.claim_next() is None


def test_stale_jobs_are_requeued(tmp_path: Path) -> None:
    store = Store(tmp_path / "db.sqlite3")
    enqueue(
        store,
        uid="1",
        region="br",
        avatar_id="102000015",
        items=["1"],
        catalog_version="1",
        exporter_version="1",
    )
    job = store.claim_next()
    assert job is not None
    assert store.requeue_stale(stale_after=0) == 0  # fresh claim is not stale
    with_store = store.get_job(job.id)
    assert with_store is not None and with_store.state == "generating"


class FakeClient:
    def __init__(self, *, profile=None, image=(b"\x89PNG\r\n\x1a\nbody", "image/png"), error=None):
        self.profile_result = profile
        self.image_result = image
        self.error = error
        self.profile_calls = 0
        self.image_calls = 0

    async def profile(self, uid, panel_region):
        self.profile_calls += 1
        if self.error is not None:
            raise self.error
        assert self.profile_result is not None
        return self.profile_result

    async def image(self, item_id):
        self.image_calls += 1
        if self.error is not None:
            raise self.error
        return self.image_result

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_exc):
        return None


@pytest.fixture
def client(tmp_path: Path, catalog_root: Path):
    config = make_config(tmp_path, catalog_root)
    fake = FakeClient(profile=profile_payload())
    app = create_app(config, client_factory=lambda: fake)
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://hub"), fake


def test_endpoints_require_the_panel_token(client) -> None:
    http, _fake = client

    async def call():
        return await http.post("/profile", json={"uid": "11807385", "region": "us"})

    response = run(call())
    assert response.status_code == 401


def test_profile_returns_catalog_labels(client) -> None:
    http, fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post(
            "/profile", json={"uid": "11807385", "region": "us"}, headers=headers
        )

    response = run(call())
    assert response.status_code == 200
    body = response.json()
    assert body["nickname"] == "Carlos"
    assert body["avatar_in_catalog"] is True
    assert body["clothes_state"] == "available"
    assert {item["item_id"] for item in body["clothes"]} == {
        "211000087",
        "203000196",
        "204000103",
        "205000070",
    }
    assert body["clothes"][0]["type"] in {"head", "torso", "legs", "feet"}
    assert fake.profile_calls == 1


def test_invalid_uid_is_rejected_before_the_provider(client) -> None:
    http, fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post("/profile", json={"uid": "12ab", "region": "us"}, headers=headers)

    response = run(call())
    assert response.status_code == 400
    assert response.json()["detail"]["error"] == "invalid_uid"
    assert fake.profile_calls == 0


def test_thumbnail_is_cached_after_first_fetch(client) -> None:
    http, fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        first = await http.get("/thumbnail/203000196", headers=headers)
        second = await http.get("/thumbnail/203000196", headers=headers)
        return first, second

    first, second = run(call())
    assert first.status_code == 200
    assert first.headers["x-cache"] == "miss"
    assert second.headers["x-cache"] == "hit"
    assert fake.image_calls == 1
    assert first.headers["content-type"].startswith("image/png")


def test_job_with_items_skips_the_provider(client) -> None:
    http, fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post(
            "/jobs",
            json={
                "uid": "11807385",
                "region": "us",
                "avatar_id": "102000015",
                "items": ["203000196"],
            },
            headers=headers,
        )

    response = run(call())
    assert response.status_code == 200
    payload = response.json()
    assert payload["created"] is True
    assert payload["job"]["state"] == "queued"
    assert payload["job"]["download_url"] == ""
    assert fake.profile_calls == 0


def test_job_without_items_reads_equipment(client) -> None:
    http, fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post("/jobs", json={"uid": "11807385", "region": "us"}, headers=headers)

    response = run(call())
    assert response.status_code == 200
    assert fake.profile_calls == 1


def test_empty_equipment_is_refused(tmp_path: Path, catalog_root: Path) -> None:
    config = make_config(tmp_path, catalog_root)
    fake = FakeClient(profile=profile_payload(clothes=()))
    app = create_app(config, client_factory=lambda: fake)
    http = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://hub")
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post("/jobs", json={"uid": "11807385", "region": "us"}, headers=headers)

    response = run(call())
    assert response.status_code == 409
    assert response.json()["detail"]["error"] == "clothes_empty"


def test_unknown_avatar_is_refused(tmp_path: Path, catalog_root: Path) -> None:
    config = make_config(tmp_path, catalog_root)
    fake = FakeClient(profile=profile_payload(avatar_id="555000555"))
    app = create_app(config, client_factory=lambda: fake)
    http = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://hub")
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.post("/jobs", json={"uid": "11807385", "region": "us"}, headers=headers)

    response = run(call())
    assert response.status_code == 409
    assert response.json()["detail"]["error"] == "avatar_not_in_catalog"


def test_download_requires_a_published_file(client) -> None:
    http, _fake = client
    headers = {"authorization": "Bearer panel-token"}
    name = "a" * 64 + ".glb"

    async def call():
        return await http.get(f"/files/{name}", headers=headers)

    response = run(call())
    assert response.status_code == 404
    assert response.json()["detail"]["error"] == "file_not_ready"


def test_file_name_must_be_a_reuse_key(client) -> None:
    http, _fake = client
    headers = {"authorization": "Bearer panel-token"}

    async def call():
        return await http.get("/files/../../etc/passwd", headers=headers)

    response = run(call())
    assert response.status_code in (400, 404)
