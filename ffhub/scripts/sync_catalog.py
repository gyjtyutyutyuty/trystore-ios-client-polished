#!/usr/bin/env python3
"""Publish the catalog to the panel: copy every mesh and write its index.

The Worker cannot read the repository, so the catalog it serves has to live in
the panel's assets. This copies the validated catalog (after `bind_profile.py`,
if you ran it) to `panel/public/catalog/` and writes the `index.json` the Worker
loads, so there is one source of truth and no second set of manifests to keep
in step.

    .venv/bin/python scripts/sync_catalog.py

`panel/public/catalog/` is git-ignored: it is build output, regenerated before
each deploy. Exit codes: 0 ok, 2 catalog is invalid, 3 catalog is empty.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.catalog import load_catalog  # noqa: E402

EXIT_OK = 0
EXIT_INVALID = 2
EXIT_EMPTY = 3


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    catalog_dir = root / "catalog"
    target = root / "panel" / "public" / "catalog"

    catalog = load_catalog(catalog_dir)
    if catalog.problems:
        print(f"catalog is invalid: {catalog.problems[0]}", file=sys.stderr)
        for problem in catalog.problems[1:4]:
            print(f"  {problem}", file=sys.stderr)
        return EXIT_INVALID
    if not catalog.bodies:
        print("catalog has no bodies; run scripts/import_bundle.py first", file=sys.stderr)
        return EXIT_EMPTY

    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)

    bodies: dict[str, str] = {}
    for avatar_id, body in sorted(catalog.bodies.items()):
        relative = Path("catalog") / body.mesh.relative_to(catalog_dir)
        destination = root / "panel" / "public" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(body.mesh, destination)
        bodies[avatar_id] = relative.as_posix()

    pieces: dict[str, dict[str, str]] = {}
    for item_id, piece in sorted(catalog.pieces.items()):
        relative = Path("catalog") / piece.mesh.relative_to(catalog_dir)
        destination = root / "panel" / "public" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(piece.mesh, destination)
        pieces[item_id] = {
            "type": piece.type,
            "mesh": relative.as_posix(),
            "label": piece.label,
        }

    index = {
        "version": catalog.version,
        "bodies": bodies,
        "pieces": pieces,
    }
    (target / "index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    total = sum(path.stat().st_size for path in target.rglob("*") if path.is_file())
    print(
        f"{len(bodies)} body(s), {len(pieces)} piece(s), version={catalog.version or '(unset)'} "
        f"-> {target.relative_to(root)} ({total / 1024:.0f} KB)"
    )
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
