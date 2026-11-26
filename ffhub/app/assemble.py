"""Outfit assembly.

Static pose export: the body scene is loaded, hidden body nodes are dropped per
the pieces' `hides` rules, every compatible piece is mounted with its own
transform, and the whole scene is written as one GLB with the materials and
textures already inside it.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import trimesh

from .catalog import Body, Catalog, Transform


class AssemblyError(RuntimeError):
    pass


@dataclass
class AssemblyResult:
    glb: bytes
    mounted: list[str]
    missing: list[str]
    skipped: list[dict[str, str]]
    meshes: int
    materials: int
    images: int
    status: str
    detail: str = ""

    @property
    def expected_parts(self) -> int:
        return len(self.mounted) + len(self.missing) + len([s for s in self.skipped])


def matrix_for(transform: Transform) -> np.ndarray:
    rotation = trimesh.transformations.euler_matrix(
        *[np.radians(angle) for angle in transform.rotation_euler_deg], "sxyz"
    )
    scale = np.eye(4)
    scale[0, 0] = scale[1, 1] = scale[2, 2] = transform.scale
    translation = np.eye(4)
    translation[:3, 3] = transform.position
    return translation @ rotation @ scale


def _load_scene(path: Path) -> trimesh.Scene:
    try:
        loaded = trimesh.load(path, force="scene", process=False)
    except Exception as exc:  # trimesh raises bare Exception subtypes per loader
        raise AssemblyError(f"could not read {path.name}: {exc.__class__.__name__}") from None
    if not isinstance(loaded, trimesh.Scene):
        raise AssemblyError(f"{path.name} is not a scene")
    if not loaded.geometry:
        raise AssemblyError(f"{path.name} has no geometry")
    return loaded


def _node_names(scene: trimesh.Scene) -> list[str]:
    return list(scene.geometry.keys())


def build_outfit(
    *,
    avatar_id: str,
    items: list[str] | tuple[str, ...],
    catalog: Catalog,
) -> AssemblyResult:
    body: Body | None = catalog.body(avatar_id)
    if body is None:
        raise AssemblyError(f"catalog has no body for avatar {avatar_id}")

    scene = _load_scene(body.mesh)
    scene.apply_transform(matrix_for(body.mount))
    body_nodes = _node_names(scene)

    pieces, missing = catalog.ordered_pieces(items)
    mounted: list[str] = []
    skipped: list[dict[str, str]] = []

    hidden: set[str] = set()
    for piece in pieces:
        if not piece.fits(avatar_id):
            skipped.append({"item_id": piece.item_id, "reason": "incompatible_body"})
            continue
        try:
            piece_scene = _load_scene(piece.mesh)
        except AssemblyError as exc:
            skipped.append({"item_id": piece.item_id, "reason": f"unreadable_mesh: {exc}"})
            continue

        transform = matrix_for(piece.mount)
        for name, geometry in list(piece_scene.geometry.items()):
            # Node names collide across pieces (every torso may ship "torso"),
            # so namespace them by item id and keep the export self-describing.
            node_name = f"{piece.type}_{piece.item_id}_{name}"
            if node_name in scene.geometry:
                node_name = f"{node_name}_2"
            try:
                scene.add_geometry(
                    geometry.copy(),
                    node_name=node_name,
                    geom_name=node_name,
                    transform=transform,
                )
            except Exception as exc:
                skipped.append(
                    {"item_id": piece.item_id, "reason": f"mount_failed: {exc.__class__.__name__}"}
                )
                break
        else:
            mounted.append(piece.item_id)
            hidden.update(piece.hides)

    if hidden:
        # `body:head_skin` refers to the body node; a bare name is matched in the
        # body scene only, so a piece can never hide another piece's mesh.
        victims = [
            name
            for name in body_nodes
            if name in hidden or f"body:{name}" in hidden
        ]
        if victims:
            scene.delete_geometry(victims)

    try:
        exported = scene.export(file_type="glb")
    except Exception as exc:
        raise AssemblyError(f"glb export failed: {exc.__class__.__name__}") from None
    if not isinstance(exported, (bytes, bytearray)) or not exported:
        raise AssemblyError("glb export produced no bytes")
    glb = bytes(exported)

    meshes, materials, images = count_resources(glb)
    status = "partial" if (missing or skipped) else "ready"
    detail_parts = []
    if missing:
        detail_parts.append("missing from catalog: " + ", ".join(sorted(missing)))
    if skipped:
        detail_parts.append(
            "skipped: " + ", ".join(f"{entry['item_id']} ({entry['reason']})" for entry in skipped)
        )
    return AssemblyResult(
        glb=glb,
        mounted=mounted,
        missing=sorted(missing),
        skipped=skipped,
        meshes=meshes,
        materials=materials,
        images=images,
        status=status,
        detail="; ".join(detail_parts),
    )


def count_resources(glb: bytes | bytearray | Path) -> tuple[int, int, int]:
    """Meshes, materials and embedded images in a GLB, read back from bytes."""
    try:
        if isinstance(glb, Path):
            scene = trimesh.load(glb, force="scene", process=False)
        else:
            scene = trimesh.load(io.BytesIO(bytes(glb)), file_type="glb", force="scene", process=False)
    except Exception as exc:
        raise AssemblyError(f"glb could not be reloaded: {exc.__class__.__name__}") from None
    if not isinstance(scene, trimesh.Scene):
        raise AssemblyError("glb is not a scene")

    materials = 0
    images = 0
    seen_materials: set[int] = set()
    for geometry in scene.geometry.values():
        visual = getattr(geometry, "visual", None)
        material = getattr(visual, "material", None)
        if material is None:
            continue
        if id(material) not in seen_materials:
            seen_materials.add(id(material))
            materials += 1
        texture = getattr(material, "baseColorTexture", None)
        if texture is not None:
            images += 1
    return len(scene.geometry), materials, images
