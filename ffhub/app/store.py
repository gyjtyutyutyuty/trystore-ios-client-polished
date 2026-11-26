"""SQLite persistence: jobs, states and the thumbnail cache.

One file, WAL mode, a connection per operation. At this scale (one worker, a
handful of panel calls per second) that beats a connection pool and survives a
process restart mid-job, which is the point of the queue.
"""

from __future__ import annotations

import json
import sqlite3
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

STATES = ("queued", "generating", "ready", "partial", "error")
TERMINAL_STATES = ("ready", "partial", "error")

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id            TEXT PRIMARY KEY,
    reuse_key     TEXT NOT NULL,
    uid           TEXT NOT NULL,
    region        TEXT NOT NULL,
    avatar_id     TEXT NOT NULL,
    items         TEXT NOT NULL,
    state         TEXT NOT NULL,
    progress      INTEGER NOT NULL DEFAULT 0,
    detail        TEXT NOT NULL DEFAULT '',
    glb_path      TEXT NOT NULL DEFAULT '',
    error         TEXT NOT NULL DEFAULT '',
    attempts      INTEGER NOT NULL DEFAULT 0,
    created_at    REAL NOT NULL,
    updated_at    REAL NOT NULL,
    claimed_at    REAL
);
CREATE INDEX IF NOT EXISTS jobs_state ON jobs(state, created_at);
CREATE INDEX IF NOT EXISTS jobs_reuse ON jobs(reuse_key, created_at DESC);

CREATE TABLE IF NOT EXISTS thumbnails (
    item_id       TEXT PRIMARY KEY,
    content_type  TEXT NOT NULL,
    body          BLOB NOT NULL,
    fetched_at    REAL NOT NULL
);
"""


@dataclass(frozen=True)
class Job:
    id: str
    reuse_key: str
    uid: str
    region: str
    avatar_id: str
    items: tuple[str, ...]
    state: str
    progress: int
    detail: str
    glb_path: str
    error: str
    attempts: int
    created_at: float
    updated_at: float
    claimed_at: float | None

    @property
    def download_url(self) -> str:
        return f"/files/{self.reuse_key}.glb" if self.state in ("ready", "partial") else ""


def _row_to_job(row: sqlite3.Row) -> Job:
    return Job(
        id=row["id"],
        reuse_key=row["reuse_key"],
        uid=row["uid"],
        region=row["region"],
        avatar_id=row["avatar_id"],
        items=tuple(json.loads(row["items"])),
        state=row["state"],
        progress=int(row["progress"]),
        detail=row["detail"],
        glb_path=row["glb_path"],
        error=row["error"],
        attempts=int(row["attempts"]),
        created_at=float(row["created_at"]),
        updated_at=float(row["updated_at"]),
        claimed_at=float(row["claimed_at"]) if row["claimed_at"] is not None else None,
    )


class Store:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.executescript(SCHEMA)

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        # sqlite3's own context manager commits but never closes, which leaks a
        # descriptor per call under a polling panel. Close explicitly.
        db = sqlite3.connect(self.path, timeout=30.0, isolation_level=None)
        try:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=NORMAL")
            db.execute("PRAGMA busy_timeout=10000")
            yield db
        finally:
            db.close()

    # -- jobs -------------------------------------------------------------

    def create_job(
        self,
        *,
        reuse_key: str,
        uid: str,
        region: str,
        avatar_id: str,
        items: tuple[str, ...],
    ) -> Job:
        now = time.time()
        job_id = str(uuid.uuid4())
        with self._connect() as db:
            db.execute(
                "INSERT INTO jobs (id, reuse_key, uid, region, avatar_id, items, state,"
                " progress, detail, glb_path, error, attempts, created_at, updated_at, claimed_at)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)",
                (
                    job_id,
                    reuse_key,
                    uid,
                    region,
                    avatar_id,
                    json.dumps(list(items)),
                    "queued",
                    0,
                    "",
                    "",
                    "",
                    0,
                    now,
                    now,
                ),
            )
        job = self.get_job(job_id)
        if job is None:
            raise RuntimeError(f"job {job_id} vanished right after insert")
        return job

    def get_job(self, job_id: str) -> Job | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return _row_to_job(row) if row is not None else None

    def latest_for_reuse(self, reuse_key: str) -> Job | None:
        with self._connect() as db:
            row = db.execute(
                "SELECT * FROM jobs WHERE reuse_key = ? ORDER BY created_at DESC LIMIT 1",
                (reuse_key,),
            ).fetchone()
        return _row_to_job(row) if row is not None else None

    def claim_next(self) -> Job | None:
        """Atomically move the oldest queued job to generating."""
        now = time.time()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT id FROM jobs WHERE state = 'queued' ORDER BY created_at LIMIT 1"
            ).fetchone()
            if row is None:
                db.execute("COMMIT")
                return None
            db.execute(
                "UPDATE jobs SET state = 'generating', claimed_at = ?, updated_at = ?,"
                " attempts = attempts + 1 WHERE id = ? AND state = 'queued'",
                (now, now, row["id"]),
            )
            db.execute("COMMIT")
        return self.get_job(row["id"])

    def set_progress(self, job_id: str, progress: int, detail: str = "") -> None:
        with self._connect() as db:
            db.execute(
                "UPDATE jobs SET progress = ?, detail = ?, updated_at = ? WHERE id = ?",
                (max(0, min(100, progress)), detail, time.time(), job_id),
            )

    def finish_job(self, job_id: str, *, state: str, glb_path: str, detail: str = "") -> None:
        if state not in ("ready", "partial", "error"):
            raise ValueError(f"finish_job state must be terminal, got {state!r}")
        with self._connect() as db:
            db.execute(
                "UPDATE jobs SET state = ?, glb_path = ?, detail = ?, progress = 100,"
                " updated_at = ? WHERE id = ?",
                (state, glb_path, detail, time.time(), job_id),
            )

    def fail_job(self, job_id: str, error: str) -> None:
        with self._connect() as db:
            db.execute(
                "UPDATE jobs SET state = 'error', error = ?, progress = 100, updated_at = ?"
                " WHERE id = ?",
                (error[:500], time.time(), job_id),
            )

    def requeue_stale(self, stale_after: float) -> int:
        """A worker killed mid-build leaves a claimed job behind; put it back."""
        cutoff = time.time() - max(30.0, stale_after)
        with self._connect() as db:
            cursor = db.execute(
                "UPDATE jobs SET state = 'queued', claimed_at = NULL, updated_at = ?"
                " WHERE state = 'generating' AND (claimed_at IS NULL OR claimed_at < ?)",
                (time.time(), cutoff),
            )
            return cursor.rowcount

    # -- thumbnails -------------------------------------------------------

    def thumbnail(self, item_id: str) -> tuple[bytes, str, float] | None:
        with self._connect() as db:
            row = db.execute(
                "SELECT content_type, body, fetched_at FROM thumbnails WHERE item_id = ?",
                (item_id,),
            ).fetchone()
        if row is None:
            return None
        return bytes(row["body"]), row["content_type"], float(row["fetched_at"])

    def put_thumbnail(self, item_id: str, body: bytes, content_type: str) -> None:
        with self._connect() as db:
            db.execute(
                "INSERT INTO thumbnails (item_id, content_type, body, fetched_at) VALUES (?,?,?,?)"
                " ON CONFLICT(item_id) DO UPDATE SET content_type = excluded.content_type,"
                " body = excluded.body, fetched_at = excluded.fetched_at",
                (item_id, content_type, body, time.time()),
            )

    # -- helpers ----------------------------------------------------------

    def stats(self) -> dict[str, Any]:
        with self._connect() as db:
            rows = db.execute("SELECT state, COUNT(*) AS n FROM jobs GROUP BY state").fetchall()
            thumbs = db.execute("SELECT COUNT(*) AS n FROM thumbnails").fetchone()["n"]
        return {"jobs": {row["state"]: row["n"] for row in rows}, "thumbnails": thumbs}
