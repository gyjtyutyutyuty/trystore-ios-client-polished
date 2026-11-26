"""Shapes of the ids the API accepts.

The HTTP layer and the catalog tools have to agree on what an id looks like,
so the patterns live here instead of in one of the two.
"""

from __future__ import annotations

import re

UID_PATTERN = re.compile(r"^[0-9]{5,15}$")
ITEM_PATTERN = re.compile(r"^[0-9]{4,20}$")
AVATAR_PATTERN = re.compile(r"^[0-9]{6,20}$")
FILE_NAME_PATTERN = re.compile(r"^[a-f0-9]{64}\.glb$")
