"""Catalog loader.

One directory per piece, one manifest per piece:

    catalog/<type>/<item_id>/manifest.json
    catalog/body/<avatar_id>/manifest.json

The manifest is the only contract between the asset folders and the
assembler, so it is validated up front: a piece that names a mesh it does not
ship, or a body that is not listed, fails at load instead of at export.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

PIECE_TYPES = ("feet", "legs", "torso", "face_paint", "head", "hair", "accessory")

# Order matters: feet first so a later torso/head can hide body skin that the
# lower layers already covered.
MOUNT_ORDER = ("feet", "legs", "torso", "face_paint", "head", "hair", "accessory")

REQUIRED_PIECE_FIELDS = ("item_id", "type", "mesh")
REQUIRED_BODY_FIELDS = ("avatar_id", "mesh")


class CatalogError(RuntimeError):
    pass


@dataclass(frozen=True)
class Transform:
    position: tuple[float, float, float] = (0.0, 0.0, 0.0)
    rotation_euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0)
    scale: float = 1.0

    @classmethod
    def from_json(cls, payload: dict[str, Any] | None) -> "Transform":
        if payload is None:
            return cls()
        if not isinstance(payload, dict):
            raise CatalogError("mount must be an object")

        def triple(key: str) -> tuple[float, float, float]:
            value = payload.get(key, [0.0, 0.0, 0.0])
            if not isinstance(value, (list, tuple)) or len(value) != 3:
                raise CatalogError(f"mount.{key} must be three numbers")
            try:
                return tuple(float(component) for component in value)  # type: ignore[return-value]
            except (TypeError, ValueError):
                raise CatalogError(f"mount.{key} must be three numbers") from None

        scale = payload.get("scale", 1.0)
        try:
            scale_value = float(scale)
        except (TypeError, ValueError):
            raise CatalogError("mount.scale must be a number") from None
        if scale_value <= 0:
            raise CatalogError("mount.scale must be positive")
        return cls(position=triple("position"), rotation_euler_deg=triple("rotation_euler_deg"), scale=scale_value)


@dataclass(frozen=True)
class Piece:
    item_id: str
    type: str
    mesh: Path
    mount: Transform
    hides: tuple[str, ...] = ()
    compatible_avatars: tuple[str, ...] = ()
    label: str = ""
    catalog_version: str = ""

    def fits(self, avatar_id: str) -> bool:
        # An empty compatibility list means "any body", which is how simple
        # accessories can be shared across avatars.
        return not self.compatible_avatars or avatar_id in self.compatible_avatars


@dataclass(frozen=True)
class Body:
    avatar_id: str
    mesh: Path
    mount: Transform = field(default_factory=Transform)


@dataclass(frozen=True)
class Catalog:
    bodies: dict[str, Body]
    pieces: dict[str, Piece]
    version: str
    problems: tuple[str, ...] = ()

    def piece(self, item_id: str) -> Piece | None:
        return self.pieces.get(str(item_id))

    def body(self, avatar_id: str) -> Body | None:
        return self.bodies.get(str(avatar_id))

    def ordered_pieces(self, item_ids: Iterable[str]) -> tuple[list[Piece], list[str]]:
        """Pieces in mount order, plus the ids the catalog does not ship."""
        resolved: list[Piece] = []
        missing: list[str] = []
        seen: set[str] = set()
        for item_id in item_ids:
            key = str(item_id)
            if key in seen:
                continue
            seen.add(key)
            piece = self.piece(key)
            if piece is None:
                missing.append(key)
            else:
                resolved.append(piece)
        rank = {name: index for index, name in enumerate(MOUNT_ORDER)}
        resolved.sort(key=lambda piece: (rank.get(piece.type, len(rank)), piece.item_id))
        return resolved, missing


def load_catalog(root: Path) -> Catalog:
    bodies: dict[str, Body] = {}
    pieces: dict[str, Piece] = {}
    problems: list[str] = []
    versions: set[str] = set()

    if not root.is_dir():
        return Catalog(bodies={}, pieces={}, version="", problems=(f"catalog root missing: {root}",))

    for manifest_path in sorted(root.rglob("manifest.json")):
        try:
            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            problems.append(f"{manifest_path}: unreadable manifest ({exc.__class__.__name__})")
            continue
        if not isinstance(payload, dict):
            problems.append(f"{manifest_path}: manifest is not an object")
            continue

        directory = manifest_path.parent
        is_body = directory.parent.name == "body"
        required = REQUIRED_BODY_FIELDS if is_body else REQUIRED_PIECE_FIELDS
        absent = [key for key in required if not str(payload.get(key, "")).strip()]
        if absent:
            problems.append(f"{manifest_path}: missing {', '.join(absent)}")
            continue

        mesh_name = str(payload["mesh"])
        mesh_path = (directory / mesh_name).resolve()
        if not mesh_path.is_file():
            problems.append(f"{manifest_path}: mesh not found ({mesh_name})")
            continue
        if directory.resolve() not in mesh_path.parents:
            problems.append(f"{manifest_path}: mesh escapes its piece directory")
            continue

        try:
            mount = Transform.from_json(payload.get("mount"))
        except CatalogError as exc:
            problems.append(f"{manifest_path}: {exc}")
            continue

        version = str(payload.get("catalog_version", "")).strip()
        if version:
            versions.add(version)

        if is_body:
            avatar_id = str(payload["avatar_id"]).strip()
            if avatar_id in bodies:
                problems.append(f"{manifest_path}: duplicate body for avatar {avatar_id}")
                continue
            bodies[avatar_id] = Body(avatar_id=avatar_id, mesh=mesh_path, mount=mount)
            continue

        item_id = str(payload["item_id"]).strip()
        piece_type = str(payload["type"]).strip()
        if piece_type not in PIECE_TYPES:
            problems.append(f"{manifest_path}: unknown type {piece_type!r}")
            continue
        if item_id in pieces:
            problems.append(f"{manifest_path}: duplicate piece {item_id}")
            continue
        hides = payload.get("hides", [])
        if not isinstance(hides, list) or not all(isinstance(entry, str) for entry in hides):
            problems.append(f"{manifest_path}: hides must be a list of node names")
            continue
        compatible = payload.get("compatible_avatars", [])
        if not isinstance(compatible, list) or not all(isinstance(entry, str) for entry in compatible):
            problems.append(f"{manifest_path}: compatible_avatars must be a list of avatar ids")
            continue
        pieces[item_id] = Piece(
            item_id=item_id,
            type=piece_type,
            mesh=mesh_path,
            mount=mount,
            hides=tuple(hides),
            compatible_avatars=tuple(compatible),
            label=str(payload.get("label", "")).strip(),
            catalog_version=version,
        )

    if len(versions) > 1:
        problems.append(f"catalog mixes versions: {', '.join(sorted(versions))}")
    return Catalog(
        bodies=bodies,
        pieces=pieces,
        version=(versions.pop() if len(versions) == 1 else ""),
        problems=tuple(problems),
    )
