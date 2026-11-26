#!/usr/bin/env python3
"""Split a Sketchfab bundle into catalog entries: one body, one GLB per piece.

A bundle downloaded from the community arrives as a single scene with every
part merged into one file (`Object_0`, `Object_1`...), no skeleton and no
useful node names. The catalog wants one directory per part, each with its own
mesh and manifest, so this bakes each node's world transform into its vertices
and writes one GLB per entry with its own material and texture inside.

    .venv/bin/python scripts/import_bundle.py .incoming/glb/golden_sakura.glb

The mapping below is decided once per bundle by looking at the parts: vertical
extent tells feet from hair, and the texture tells skin from a garment. Rerun
with `--dry-run` to print the parts and their bounds without writing.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import trimesh

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.assemble import count_resources  # noqa: E402

# Bundle part -> (kind, catalog id, label). "body" goes under catalog/body/<id>.
GOLDEN_SAKURA = {
    "Object_0": ("body", "golden_sakura", "Cuerpo base Golden Sakura"),
    "Object_1": ("feet", "gsk_feet", "Botas Golden Sakura"),
    "Object_2": ("legs", "gsk_legs", "Pantalón Golden Sakura"),
    "Object_3": ("torso", "gsk_torso", "Kimono Golden Sakura"),
    "Object_4": ("head", "gsk_head", "Adorno de cabeza Golden Sakura"),
    "Object_5": ("hair", "gsk_hair", "Pelo Golden Sakura"),
}

CATALOG_VERSION = "golden-sakura-1"


def parts(path: Path) -> dict[str, trimesh.Trimesh]:
    """Every geometry in the bundle, in world space, keyed by its mesh name."""
    scene = trimesh.load(path, force="scene", process=False)
    if not isinstance(scene, trimesh.Scene) or not scene.geometry:
        raise SystemExit(f"{path}: no geometry in this file")
    found: dict[str, trimesh.Trimesh] = {}
    for node in scene.graph.nodes_geometry:
        transform, geometry_name = scene.graph[node]
        geometry = scene.geometry[geometry_name].copy()
        # The bundle keeps a Z-up root matrix; baking it means every catalog
        # entry shares one coordinate system and needs no mount transform.
        geometry.apply_transform(transform)
        found[geometry_name] = geometry
    return found


def one_mesh_glb(geometry: trimesh.Trimesh, node_name: str) -> bytes:
    scene = trimesh.Scene()
    scene.add_geometry(geometry, node_name=node_name, geom_name=node_name)
    exported = scene.export(file_type="glb")
    if not isinstance(exported, (bytes, bytearray)) or not exported:
        raise SystemExit(f"{node_name}: export produced no bytes")
    return bytes(exported)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="import_bundle", description=__doc__.splitlines()[0])
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path(__file__).resolve().parent.parent / "catalog")
    parser.add_argument("--dry-run", action="store_true", help="print the parts and stop")
    args = parser.parse_args(argv)

    found = parts(args.bundle)
    unknown = sorted(set(found) - set(GOLDEN_SAKURA))
    absent = sorted(set(GOLDEN_SAKURA) - set(found))
    for name in sorted(found, key=lambda key: found[key].bounds[1][1]):
        geometry = found[name]
        low, high = geometry.bounds
        kind, entry_id, label = GOLDEN_SAKURA.get(name, ("?", "?", "?"))
        texture = getattr(getattr(geometry.visual, "material", None), "baseColorTexture", None)
        print(
            f"{name:<10} {kind:<10} y[{low[1]:+.2f},{high[1]:+.2f}] "
            f"x[{low[0]:+.2f},{high[0]:+.2f}] verts={len(geometry.vertices):5d} "
            f"texture={'yes' if texture is not None else 'NO'}  {label}"
        )
    if unknown or absent:
        print(f"mapping does not fit this bundle: unknown={unknown} missing={absent}")
        return 2
    if args.dry_run:
        return 0

    written = 0
    for name, (kind, entry_id, label) in GOLDEN_SAKURA.items():
        directory = args.catalog / kind / entry_id
        directory.mkdir(parents=True, exist_ok=True)
        glb = one_mesh_glb(found[name], node_name=kind)
        (directory / "mesh.glb").write_bytes(glb)
        manifest = {
            "mesh": "mesh.glb",
            "catalog_version": CATALOG_VERSION,
        }
        if kind == "body":
            manifest = {"avatar_id": entry_id, **manifest}
        else:
            manifest = {"item_id": entry_id, "type": kind, "label": label, **manifest}
            manifest["mount"] = {"position": [0.0, 0.0, 0.0], "scale": 1.0}
        (directory / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        meshes, materials, images = count_resources(glb)
        print(f"wrote {directory.relative_to(args.catalog)} {len(glb) / 1024:.0f} KB "
              f"meshes={meshes} materials={materials} textures={images}")
        if images != meshes:
            print(f"  {name}: {meshes - images} mesh(es) lost their texture")
            return 3
        written += 1
    print(f"{written} entries under {args.catalog}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
