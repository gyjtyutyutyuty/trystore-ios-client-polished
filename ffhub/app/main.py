"""HTTP surface for the panel.

Authentication is a single bearer token held by the Sites Worker, so the browser
never sees it. Provider failures are mapped to their own status codes instead of
collapsing into a 500: a panel that can tell "rate limited" from "bad uid" can
tell the player what to do.
"""

from __future__ import annotations

import re
import secrets
from pathlib import Path
from typing import Any, Callable, Protocol

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel

from .catalog import Catalog, load_catalog
from .config import Config
from .ffapi import (
    ImageUnavailable,
    Profile,
    ProfileNotFound,
    ProviderAuthError,
    ProviderBadResponse,
    ProviderError,
    ProviderRateLimited,
    provider_region,
)
from .jobs import enqueue
from .store import Job, Store

UID_PATTERN = re.compile(r"^[0-9]{5,15}$")
ITEM_PATTERN = re.compile(r"^[0-9]{4,20}$")
AVATAR_PATTERN = re.compile(r"^[0-9]{6,20}$")
FILE_NAME_PATTERN = re.compile(r"^[a-f0-9]{64}\.glb$")


class ProviderClient(Protocol):
    async def profile(self, uid: str, panel_region: str) -> Profile: ...
    async def image(self, item_id: str) -> tuple[bytes, str]: ...
    async def __aenter__(self) -> "ProviderClient": ...
    async def __aexit__(self, *_exc: object) -> None: ...


class ProfileRequest(BaseModel):
    uid: str
    region: str = "us"


class JobRequest(BaseModel):
    uid: str
    region: str = "us"
    avatar_id: str | None = None
    items: list[str] | None = None


def job_payload(job: Job) -> dict[str, Any]:
    return {
        "id": job.id,
        "state": job.state,
        "progress": job.progress,
        "detail": job.detail,
        "error": job.error,
        "reuse_key": job.reuse_key,
        "download_url": job.download_url,
    }


def create_app(config: Config, client_factory: Callable[[], ProviderClient] | None = None) -> FastAPI:
    if client_factory is None:
        from .ffapi import FireApiClient

        client_factory = lambda: FireApiClient(  # noqa: E731 - one-line construction
            api_key=config.api_key,
            api_base=config.api_base,
            timeout=config.request_timeout,
            attempts=config.provider_attempts,
        )

    config.ensure_dirs()
    app = FastAPI(title="FFHub", version=config.exporter_version, docs_url=None, redoc_url=None)
    app.state.config = config
    app.state.store = Store(config.data_dir / "ffhub.sqlite3")
    app.state.client_factory = client_factory
    app.state.catalog_cache = {"mtime": 0.0, "catalog": load_catalog(config.catalog_dir)}

    def current_catalog(request: Request) -> Catalog:
        cache = request.app.state.catalog_cache
        manifests = sorted(config.catalog_dir.rglob("manifest.json"))
        mtime = max((path.stat().st_mtime for path in manifests), default=0.0)
        if mtime != cache["mtime"]:
            cache["catalog"] = load_catalog(config.catalog_dir)
            cache["mtime"] = mtime
        return cache["catalog"]

    def require_token(request: Request) -> None:
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        expected = request.app.state.config.bearer_token
        if scheme.lower() != "bearer" or not token or not secrets.compare_digest(
            token.strip(), expected
        ):
            raise HTTPException(status_code=401, detail={"error": "unauthorized"})

    def validate_uid(uid: str) -> str:
        value = (uid or "").strip()
        if not UID_PATTERN.fullmatch(value):
            raise HTTPException(status_code=400, detail={"error": "invalid_uid"})
        return value

    def validate_region(region: str) -> str:
        try:
            provider_region(region)
        except ValueError:
            raise HTTPException(status_code=400, detail={"error": "invalid_region"}) from None
        return region.strip().lower()

    def provider_http_error(exc: ProviderError) -> HTTPException:
        if isinstance(exc, ProfileNotFound):
            return HTTPException(status_code=404, detail={"error": "profile_not_found"})
        if isinstance(exc, ProviderAuthError):
            return HTTPException(status_code=502, detail={"error": "provider_auth"})
        if isinstance(exc, ProviderRateLimited):
            return HTTPException(
                status_code=429,
                detail={"error": "provider_rate_limited", "retry_after": exc.retry_after},
                headers={"Retry-After": str(int(exc.retry_after))},
            )
        if isinstance(exc, (ImageUnavailable, ProviderBadResponse)):
            return HTTPException(status_code=502, detail={"error": "provider_bad_response"})
        return HTTPException(status_code=502, detail={"error": "provider_error"})

    @app.get("/healthz")
    def healthz(request: Request) -> dict[str, Any]:
        return {"ok": True, "stats": request.app.state.store.stats()}

    @app.post("/profile", dependencies=[Depends(require_token)])
    async def profile(payload: ProfileRequest, request: Request) -> dict[str, Any]:
        uid = validate_uid(payload.uid)
        region = validate_region(payload.region)
        catalog = current_catalog(request)

        try:
            async with request.app.state.client_factory() as client:
                result: Profile = await client.profile(uid, region)
        except ProviderError as exc:
            raise provider_http_error(exc) from None

        clothes = []
        for item_id in result.clothes or ():
            piece = catalog.piece(item_id)
            clothes.append(
                {
                    "item_id": item_id,
                    "type": piece.type if piece else "unknown",
                    "label": piece.label if piece else "",
                    "in_catalog": piece is not None,
                    "thumbnail_url": f"/api/thumbnail/{item_id}",
                }
            )
        return {
            "uid": result.uid,
            "nickname": result.nickname,
            "region": result.region,
            "requested_region": region,
            "avatar_id": result.avatar_id,
            "avatar_in_catalog": catalog.body(result.avatar_id) is not None,
            "clothes": clothes,
            "clothes_state": result.clothes_state,
            "catalog_version": catalog.version,
            "catalog_problems": list(catalog.problems),
        }

    @app.get("/thumbnail/{item_id}", dependencies=[Depends(require_token)])
    async def thumbnail(item_id: str, request: Request) -> Response:
        if not ITEM_PATTERN.fullmatch(item_id):
            raise HTTPException(status_code=400, detail={"error": "invalid_item_id"})
        store: Store = request.app.state.store
        cached = store.thumbnail(item_id)
        if cached is not None:
            body, content_type, _ = cached
            return Response(
                content=body,
                media_type=content_type,
                headers={"Cache-Control": "public, max-age=604800", "X-Cache": "hit"},
            )
        try:
            async with request.app.state.client_factory() as client:
                body, content_type = await client.image(item_id)
        except ImageUnavailable:
            raise HTTPException(status_code=404, detail={"error": "image_unavailable"}) from None
        except ProviderError as exc:
            raise provider_http_error(exc) from None
        store.put_thumbnail(item_id, body, content_type)
        return Response(
            content=body,
            media_type=content_type,
            headers={"Cache-Control": "public, max-age=604800", "X-Cache": "miss"},
        )

    @app.post("/jobs", dependencies=[Depends(require_token)])
    async def create_job(payload: JobRequest, request: Request) -> dict[str, Any]:
        uid = validate_uid(payload.uid)
        region = validate_region(payload.region)
        catalog = current_catalog(request)

        if payload.items is not None:
            if not payload.avatar_id or not AVATAR_PATTERN.fullmatch(payload.avatar_id):
                raise HTTPException(status_code=400, detail={"error": "invalid_avatar_id"})
            invalid = [item for item in payload.items if not ITEM_PATTERN.fullmatch(item)]
            if invalid:
                raise HTTPException(
                    status_code=400, detail={"error": "invalid_item_id", "items": invalid[:5]}
                )
            avatar_id = payload.avatar_id
            items = list(payload.items)
        else:
            try:
                async with request.app.state.client_factory() as client:
                    profile: Profile = await client.profile(uid, region)
            except ProviderError as exc:
                raise provider_http_error(exc) from None
            if profile.clothes_state != "available":
                raise HTTPException(
                    status_code=409,
                    detail={"error": f"clothes_{profile.clothes_state}", "uid": uid},
                )
            avatar_id = profile.avatar_id
            items = list(profile.clothes or ())

        if catalog.body(avatar_id) is None:
            raise HTTPException(
                status_code=409,
                detail={"error": "avatar_not_in_catalog", "avatar_id": avatar_id},
            )

        job, created = enqueue(
            request.app.state.store,
            uid=uid,
            region=region,
            avatar_id=avatar_id,
            items=items,
            catalog_version=catalog.version or request.app.state.config.catalog_version,
            exporter_version=request.app.state.config.exporter_version,
        )
        return {"job": job_payload(job), "created": created}

    @app.get("/jobs/{job_id}", dependencies=[Depends(require_token)])
    def get_job(job_id: str, request: Request) -> dict[str, Any]:
        job = request.app.state.store.get_job(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail={"error": "job_not_found"})
        return {"job": job_payload(job)}

    @app.get("/files/{name}", dependencies=[Depends(require_token)])
    def download(name: str, request: Request) -> FileResponse:
        if not FILE_NAME_PATTERN.fullmatch(name):
            raise HTTPException(status_code=400, detail={"error": "invalid_file_name"})
        path = Path(request.app.state.config.data_dir) / "files" / name
        if not path.is_file():
            raise HTTPException(status_code=404, detail={"error": "file_not_ready"})
        return FileResponse(
            path,
            media_type="model/gltf-binary",
            filename=f"{name.rsplit('.', 1)[0][:16]}.glb",
            headers={"Cache-Control": "public, max-age=86400"},
        )

    return app
