"""Post-export verification.

A GLB that opens but is missing a piece is a partial result, not a success. The
worker publishes only after this check names every expected piece.
"""

from __future__ import annotations

from pathlib import Path

import trimesh


def verify_export(path: Path, mounted: list[str], *, minimum_meshes: int = 1) -> tuple[str, str]:
    """Return (state, detail): ('ready', '') or ('partial'|'error', reason)."""
    if not path.is_file():
        return "error", "exported file is missing"
    if path.stat().st_size == 0:
        return "error", "exported file is empty"
    try:
        scene = trimesh.load(path, force="scene", process=False)
    except Exception as exc:
        return "error", f"exported glb does not open: {exc.__class__.__name__}"
    if not isinstance(scene, trimesh.Scene) or not scene.geometry:
        return "error", "exported glb has no geometry"

    nodes = list(scene.geometry.keys())
    if len(nodes) < minimum_meshes:
        return "error", f"exported glb has {len(nodes)} meshes, expected at least {minimum_meshes}"

    absent = [
        item_id
        for item_id in mounted
        if not any(node.startswith(item_id) or f"_{item_id}_" in node for node in nodes)
    ]
    if absent:
        return "partial", "missing from export: " + ", ".join(sorted(absent))

    textured = 0
    for geometry in scene.geometry.values():
        material = getattr(getattr(geometry, "visual", None), "material", None)
        if material is not None and getattr(material, "baseColorTexture", None) is not None:
            textured += 1
    detail = f"{len(nodes)} meshes, {textured} textured"
    return "ready", detail
