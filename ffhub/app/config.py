from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


class ConfigError(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    api_key: str
    api_base: str
    data_dir: Path
    catalog_dir: Path
    bearer_token: str
    exporter_version: str
    catalog_version: str
    request_timeout: float
    max_glb_bytes: int
    provider_attempts: int

    @classmethod
    def from_env(cls) -> "Config":
        api_key = os.environ.get("FREE_FIRE_API_KEY", "").strip()
        if not api_key:
            raise ConfigError(
                "FREE_FIRE_API_KEY is not set; put it in the systemd EnvironmentFile, not in the repo"
            )
        bearer = os.environ.get("FFHUB_TOKEN", "").strip()
        if not bearer:
            raise ConfigError("FFHUB_TOKEN is not set; the panel has no way to authenticate without it")

        here = Path(__file__).resolve().parent.parent
        return cls(
            api_key=api_key,
            api_base=os.environ.get(
                "FIRE_API_BASE", "https://developers.freefirecommunity.com/api/v1"
            ).rstrip("/"),
            data_dir=Path(os.environ.get("FFHUB_DATA_DIR", here / "data")).resolve(),
            catalog_dir=Path(os.environ.get("FFHUB_CATALOG_DIR", here / "catalog")).resolve(),
            bearer_token=bearer,
            # Both versions feed the reuse key, so bumping either invalidates
            # cached GLBs instead of serving a stale outfit.
            exporter_version=os.environ.get("FFHUB_EXPORTER_VERSION", "1"),
            catalog_version=os.environ.get("FFHUB_CATALOG_VERSION", "1"),
            request_timeout=float(os.environ.get("FFHUB_REQUEST_TIMEOUT", "20")),
            max_glb_bytes=int(os.environ.get("FFHUB_MAX_GLB_BYTES", str(256 * 1024 * 1024))),
            provider_attempts=int(os.environ.get("FFHUB_PROVIDER_ATTEMPTS", "3")),
        )

    def ensure_dirs(self) -> None:
        (self.data_dir / "files").mkdir(parents=True, exist_ok=True)
        (self.data_dir / "work").mkdir(parents=True, exist_ok=True)
