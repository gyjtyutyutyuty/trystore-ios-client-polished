"""Worker loop: claim, build, verify, publish.

Publishing is an atomic rename inside the data directory, so a panel polling
the download URL either sees the previous file or the finished one, never a
half-written GLB.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import sys
import time
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from pathlib import Path

from .assemble import AssemblyError, build_outfit
from .catalog import Catalog, load_catalog
from .config import Config, ConfigError
from .jobs import canonical_items
from .store import Job, Store
from .validate import verify_export


def publish(workdir: Path, glb: bytes, destination: Path, *, max_bytes: int) -> None:
    if len(glb) > max_bytes:
        raise AssemblyError(f"glb is {len(glb)} bytes, over the {max_bytes} byte limit")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = workdir / f"{destination.name}.tmp"
    staging.write_bytes(glb)
    if staging.stat().st_size != len(glb):
        raise AssemblyError("short write while publishing the glb")
    os.replace(staging, destination)


def process_job(job: Job, *, config: Config, store: Store, catalog: Catalog | None = None) -> Job:
    workdir = config.data_dir / "work" / job.id
    workdir.mkdir(parents=True, exist_ok=True)
    destination = config.data_dir / "files" / f"{job.reuse_key}.glb"
    try:
        store.set_progress(job.id, 10, "resolving catalog")
        active = catalog if catalog is not None else load_catalog(config.catalog_dir)
        if active.problems:
            # Catalog drift is a deploy problem; failing loudly here is better
            # than shipping an outfit with silently missing pieces.
            raise AssemblyError("catalog invalid: " + "; ".join(active.problems[:3]))

        store.set_progress(job.id, 35, "assembling outfit")
        result = build_outfit(
            avatar_id=job.avatar_id,
            items=list(canonical_items(job.items)),
            catalog=active,
        )

        store.set_progress(job.id, 80, "verifying export")
        staging = workdir / "outfit.glb"
        staging.write_bytes(result.glb)
        verify_state, detail = verify_export(staging, result.mounted)
        if verify_state == "error":
            raise AssemblyError(detail)
        # Assembly already knows about catalog gaps the file cannot show; a
        # published GLB missing a piece must never be reported as ready.
        state = "partial" if "partial" in (verify_state, result.status) else "ready"

        store.set_progress(job.id, 95, "publishing")
        publish(workdir, result.glb, destination, max_bytes=config.max_glb_bytes)
        final_detail = "; ".join(part for part in (result.detail, detail) if part)
        store.finish_job(job.id, state=state, glb_path=str(destination), detail=final_detail)
    except AssemblyError as exc:
        store.fail_job(job.id, str(exc))
    except Exception as exc:  # never leave a job claimed on an unexpected error
        store.fail_job(job.id, f"{exc.__class__.__name__}: {exc}")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    finished = store.get_job(job.id)
    assert finished is not None
    return finished


def run_forever(
    config: Config,
    store: Store,
    *,
    poll_seconds: float = 2.0,
    workers: int = 1,
) -> int:
    workers = max(1, int(workers))
    stopping = False

    def handle_signal(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    recovered = store.requeue_stale(stale_after=15 * 60)
    if recovered:
        print(f"worker: requeued {recovered} stale job(s)", flush=True)

    if workers == 1:
        while not stopping:
            job = store.claim_next()
            if job is None:
                time.sleep(poll_seconds)
                continue
            print(
                f"worker: job {job.id} start avatar={job.avatar_id} items={len(job.items)}",
                flush=True,
            )
            finished = process_job(job, config=config, store=store)
            print(f"worker: job {finished.id} {finished.state} {finished.detail}", flush=True)
        return 0

    # The export spends most of its time in Pillow's PNG encoder, which releases
    # the GIL. A bounded pool therefore turns queued outfits into parallel
    # builds; the default stays 1 so memory use does not jump unless asked. Each
    # job has its own work directory and claims are atomic, so the shares are
    # only the SQLite store and the read-only catalog.
    with ThreadPoolExecutor(max_workers=workers) as pool:
        in_flight: set[Future[Job]] = set()
        while not stopping:
            for future in [entry for entry in in_flight if entry.done()]:
                in_flight.discard(future)
                finished = future.result()
                print(
                    f"worker: job {finished.id} {finished.state} {finished.detail}",
                    flush=True,
                )

            while not stopping and len(in_flight) < workers:
                job = store.claim_next()
                if job is None:
                    break
                print(
                    f"worker: job {job.id} start avatar={job.avatar_id} items={len(job.items)}",
                    flush=True,
                )
                in_flight.add(pool.submit(process_job, job, config=config, store=store))

            if stopping:
                break
            if in_flight:
                wait(in_flight, timeout=poll_seconds, return_when=FIRST_COMPLETED)
            else:
                time.sleep(poll_seconds)

        # Let claimed jobs finish; process_job publishes atomically, so there is
        # nothing to roll back if the service is asked to stop mid-build.
        for future in in_flight:
            finished = future.result()
            print(f"worker: job {finished.id} {finished.state} {finished.detail}", flush=True)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ffhub-worker")
    parser.add_argument("--once", action="store_true", help="drain one job and exit")
    parser.add_argument("--poll", type=float, default=2.0)
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="concurrent exports (default 1; raise only with memory headroom)",
    )
    args = parser.parse_args(argv)

    try:
        config = Config.from_env()
    except ConfigError as exc:
        print(f"config: {exc}", file=sys.stderr)
        return 2
    config.ensure_dirs()
    store = Store(config.data_dir / "ffhub.sqlite3")

    if args.once:
        job = store.claim_next()
        if job is None:
            print("worker: nothing queued", flush=True)
            return 0
        finished = process_job(job, config=config, store=store)
        print(f"worker: {finished.state} {finished.detail}", flush=True)
        return 0 if finished.state in ("ready", "partial") else 1
    return run_forever(config, store, poll_seconds=args.poll, workers=args.workers)


if __name__ == "__main__":
    raise SystemExit(main())
