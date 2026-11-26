#!/usr/bin/env python3
"""One real GLB, end to end: UID -> profile -> job -> worker -> printed path.

Uses the real provider client and the real assembler, then builds the job
in-process so no server or worker has to be running.

    export FREE_FIRE_API_KEY=...      # /etc/ffhub/env, never in the repo
    export FFHUB_TOKEN=local
    .venv/bin/python scripts/e2e.py --uid 11807385 --region us

Rebuild from ids you already know without touching the provider:

    .venv/bin/python scripts/e2e.py --uid 11807385 \\
        --avatar-id 102000015 --items 211000087,211000303,214000053,203000196,204000103,205000070
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.catalog import load_catalog  # noqa: E402
from app.config import Config, ConfigError  # noqa: E402
from app.ffapi import FireApiClient, ProviderError, provider_region  # noqa: E402
from app.jobs import enqueue  # noqa: E402
from app.store import Store  # noqa: E402
from app.worker import process_job  # noqa: E402

EXIT_OK = 0
EXIT_CONFIG = 2
EXIT_CATALOG = 3
EXIT_PROVIDER = 4
EXIT_BUILD = 5


def say(step: str, message: str) -> None:
    print(f"{step:<10} {message}", flush=True)


def needs(uid: str, avatar_id: str, missing: list[str], catalog_dir: Path) -> None:
    print()
    print("missing from the catalog — create these before retrying:")
    body_dir = catalog_dir / "body" / avatar_id
    if not (body_dir / "manifest.json").is_file():
        print(f"  {body_dir}/manifest.json  (+ mesh.glb)")
        print(f"    {{\"avatar_id\": \"{avatar_id}\", \"mesh\": \"mesh.glb\", \"catalog_version\": \"1\"}}")
    for item_id in sorted(missing):
        print(f"  {catalog_dir}/<type>/{item_id}/manifest.json  (+ mesh.glb)")
        print(f"    {{\"item_id\": \"{item_id}\", \"type\": \"torso\", \"mesh\": \"mesh.glb\"}}")
    print()
    print(f"avatar from the provider: {avatar_id}   uid: {uid}")


def parse_items(raw: str | None) -> list[str] | None:
    if raw is None:
        return None
    items = [chunk.strip() for chunk in raw.split(",") if chunk.strip()]
    return items or None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="e2e", description=__doc__.splitlines()[0])
    parser.add_argument("--uid", required=True, help="5-15 digit player uid")
    parser.add_argument("--region", default="us", help="us|br|na|latam|sg|id|th|vn|my")
    parser.add_argument("--avatar-id", help="skip /info and use this body")
    parser.add_argument("--items", help="skip /info and use these comma-separated item ids")
    parser.add_argument("--catalog", help="catalog directory (default: $FFHUB_CATALOG_DIR)")
    parser.add_argument("--data", help="data directory (default: $FFHUB_DATA_DIR)")
    parser.add_argument("--json", action="store_true", help="print one json line at the end")
    args = parser.parse_args(argv)

    try:
        config = Config.from_env()
    except ConfigError as exc:
        say("config", f"FAILED — {exc}")
        return EXIT_CONFIG
    if args.catalog:
        config = Config(**{**config.__dict__, "catalog_dir": Path(args.catalog).resolve()})
    if args.data:
        config = Config(**{**config.__dict__, "data_dir": Path(args.data).resolve()})
    config.ensure_dirs()

    say("1/5 config", f"data={config.data_dir} catalog={config.catalog_dir}")
    try:
        say("1/5 config", f"provider region {provider_region(args.region)}")
    except ValueError:
        say("1/5 config", f"FAILED — unsupported region {args.region!r}")
        return EXIT_CONFIG

    items = parse_items(args.items)
    avatar_id = args.avatar_id
    nickname = ""
    provider_region_returned = ""

    if avatar_id and items:
        say("2/5 profile", "skipped — avatar and items given on the command line")
    else:
        async def fetch():
            async with FireApiClient(api_key=config.api_key, api_base=config.api_base) as client:
                return await client.profile(args.uid, args.region)

        try:
            profile = asyncio.run(fetch())
        except ProviderError as exc:
            say("2/5 profile", f"FAILED — {exc.code}: {exc}")
            return EXIT_PROVIDER
        nickname = profile.nickname
        provider_region_returned = profile.region
        avatar_id = profile.avatar_id
        items = list(profile.clothes or ())
        say(
            "2/5 profile",
            f"{nickname or '(sin nombre)'} region={provider_region_returned} "
            f"avatar={avatar_id} clothes={profile.clothes_state} ({len(items)})",
        )
        if profile.clothes_state != "available":
            say("2/5 profile", f"FAILED — equipment is {profile.clothes_state}; nothing to assemble")
            return EXIT_PROVIDER

    assert avatar_id is not None
    items = list(items or ())
    catalog = load_catalog(config.catalog_dir)
    if catalog.problems:
        say("3/5 catalog", f"FAILED — {catalog.problems[0]}")
        for problem in catalog.problems[1:4]:
            say("3/5 catalog", f"  {problem}")
        return EXIT_CATALOG
    body_ok = catalog.body(avatar_id) is not None
    resolved, missing = catalog.ordered_pieces(items)
    say(
        "3/5 catalog",
        f"version={catalog.version or '(unset)'} body={avatar_id} "
        f"{'ok' if body_ok else 'MISSING'} pieces={len(resolved)}/{len(items)} "
        f"missing={len(missing)}",
    )
    if not body_ok or missing:
        needs(args.uid, avatar_id, missing, config.catalog_dir)
        return EXIT_CATALOG

    store = Store(config.data_dir / "ffhub.sqlite3")
    job, created = enqueue(
        store,
        uid=args.uid,
        region=args.region,
        avatar_id=avatar_id,
        items=items,
        catalog_version=catalog.version or config.catalog_version,
        exporter_version=config.exporter_version,
    )
    say(
        "4/5 job",
        f"{job.id} reuse={job.reuse_key[:12]}… {'created' if created else 'reused'} items={len(job.items)}",
    )

    claimed = store.claim_next()
    if claimed is None:
        say("5/5 build", "FAILED — nothing claimable (another worker holds the queue?)")
        return EXIT_BUILD
    finished = process_job(claimed, config=config, store=store)
    if finished.state == "error":
        say("5/5 build", f"FAILED — {finished.error}")
        return EXIT_BUILD

    path = Path(finished.glb_path)
    size = path.stat().st_size if path.is_file() else 0
    say(
        "5/5 build",
        f"{finished.state} {finished.detail or 'ok'} -> {path} ({size / 1024 / 1024:.1f} MB)",
    )
    if args.json:
        import json

        print(
            json.dumps(
                {
                    "uid": args.uid,
                    "nickname": nickname,
                    "region": provider_region_returned or args.region,
                    "avatar_id": avatar_id,
                    "items": items,
                    "job_id": finished.id,
                    "state": finished.state,
                    "file": str(path),
                    "bytes": size,
                    "detail": finished.detail,
                }
            )
        )
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
