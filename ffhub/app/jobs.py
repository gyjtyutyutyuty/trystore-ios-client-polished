"""Reuse keys and enqueue rules.

Two players wearing the same items on the same body must not build twice, and a
job already running for that combination must be shared rather than duplicated.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

from .store import Job, Store


def canonical_items(items: list[str] | tuple[str, ...]) -> tuple[str, ...]:
    cleaned = {str(item).strip() for item in items if str(item).strip()}
    # Sorted so the same outfit always hashes the same way regardless of the
    # order the provider returned the pieces in.
    return tuple(sorted(cleaned))


def reuse_key(
    *,
    avatar_id: str,
    items: list[str] | tuple[str, ...],
    catalog_version: str,
    exporter_version: str,
) -> str:
    parts = [
        f"avatar={avatar_id}",
        "items=" + ",".join(canonical_items(items)),
        f"catalog={catalog_version}",
        f"exporter={exporter_version}",
    ]
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


def enqueue(
    store: Store,
    *,
    uid: str,
    region: str,
    avatar_id: str,
    items: list[str] | tuple[str, ...],
    catalog_version: str,
    exporter_version: str,
) -> tuple[Job, bool]:
    """Return (job, created). created is False when an equivalent job exists."""
    canonical = canonical_items(items)
    key = reuse_key(
        avatar_id=avatar_id,
        items=canonical,
        catalog_version=catalog_version,
        exporter_version=exporter_version,
    )
    existing = store.latest_for_reuse(key)
    if existing is not None:
        if existing.state in ("queued", "generating"):
            return existing, False
        if existing.glb_path and Path(existing.glb_path).is_file():
            return existing, False
        # A terminal job without a published file failed; retry it in place
        # rather than serving a dead receipt.
    return (
        store.create_job(
            reuse_key=key,
            uid=uid,
            region=region,
            avatar_id=avatar_id,
            items=canonical,
        ),
        True,
    )
