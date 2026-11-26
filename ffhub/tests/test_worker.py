from __future__ import annotations

from pathlib import Path

from app.jobs import enqueue
from app.store import Store
from app.worker import process_job, publish, run_forever

from conftest import make_config


def queued_job(tmp_path: Path, catalog_root: Path, items: list[str]):
    config = make_config(tmp_path, catalog_root)
    store = Store(config.data_dir / "ffhub.sqlite3")
    job, _created = enqueue(
        store,
        uid="11807385",
        region="br",
        avatar_id="102000015",
        items=items,
        catalog_version="test-1",
        exporter_version="test",
    )
    return config, store, job


def test_worker_publishes_a_ready_glb(tmp_path: Path, catalog_root: Path) -> None:
    config, store, job = queued_job(tmp_path, catalog_root, ["203000196", "205000070"])
    claimed = store.claim_next()
    assert claimed is not None

    finished = process_job(claimed, config=config, store=store)
    assert finished.state == "ready"
    published = Path(finished.glb_path)
    assert published.is_file()
    assert published.name == f"{job.reuse_key}.glb"
    assert published.stat().st_size > 0
    assert finished.download_url == f"/files/{job.reuse_key}.glb"
    assert not (config.data_dir / "work" / job.id).exists()


def test_worker_marks_unknown_items_partial(tmp_path: Path, catalog_root: Path) -> None:
    config, store, _job = queued_job(tmp_path, catalog_root, ["203000196", "999999999"])
    claimed = store.claim_next()
    assert claimed is not None

    finished = process_job(claimed, config=config, store=store)
    assert finished.state == "partial"
    assert "999999999" in finished.detail


def test_worker_fails_when_the_catalog_is_broken(tmp_path: Path, catalog_root: Path) -> None:
    config, store, _job = queued_job(tmp_path, catalog_root, ["203000196"])
    broken = config.catalog_dir / "torso" / "203000196" / "manifest.json"
    broken.write_text('{"item_id": "203000196", "type": "torso", "mesh": "gone.glb"}', encoding="utf-8")
    claimed = store.claim_next()
    assert claimed is not None

    finished = process_job(claimed, config=config, store=store)
    assert finished.state == "error"
    assert "catalog invalid" in finished.error


def test_publish_refuses_oversized_files(tmp_path: Path) -> None:
    destination = tmp_path / "files" / ("a" * 64 + ".glb")
    try:
        publish(tmp_path / "work", b"x" * 32, destination, max_bytes=16)
    except Exception as exc:
        assert "over the" in str(exc)
    else:
        raise AssertionError("publish should refuse an oversized glb")
    assert not destination.exists()


def test_run_forever_drains_and_stops(tmp_path: Path, catalog_root: Path, monkeypatch) -> None:
    config, store, _job = queued_job(tmp_path, catalog_root, ["203000196"])
    calls = {"n": 0}

    def fake_sleep(_seconds: float) -> None:
        calls["n"] += 1
        if calls["n"] > 1:
            raise KeyboardInterrupt

    monkeypatch.setattr("app.worker.time.sleep", fake_sleep)
    try:
        run_forever(config, store, poll_seconds=0)
    except KeyboardInterrupt:
        pass
    rows = store.stats()["jobs"]
    assert rows.get("ready") == 1
