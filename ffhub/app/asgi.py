"""ASGI entry point for uvicorn.

Configuration is read at import time so a missing secret fails at boot instead
of on the first request.
"""

from __future__ import annotations

from .config import Config
from .main import create_app

app = create_app(Config.from_env())
