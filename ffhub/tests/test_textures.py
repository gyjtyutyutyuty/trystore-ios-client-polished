"""Texture regression guard.

trimesh silently drops embedded images when Pillow is missing, and the export
still succeeds with valid geometry. That failure was invisible once already:
six materials, zero textures, status "ready". These tests read the pixels back
out of the exported bytes, so a texture-less GLB cannot pass.
"""

from __future__ import annotations

import io
from pathlib import Path

import pytest
import trimesh
from PIL import Image

from app.assemble import build_outfit, count_resources
from app.catalog import load_catalog
from app.jobs import enqueue
from app.store import Store
from app.worker import process_job

from conftest import make_config, write_body

TEXTURE_RGB = (200, 60, 30)


def write_textured_piece(path: Path, *, colour: tuple[int, int, int] = TEXTURE_RGB) -> Path:
    image = Image.new("RGB", (8, 8), colour)
    mesh = trimesh.Trimesh(
        vertices=[[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0]],
        faces=[[0, 1, 2], [0, 2, 3]],
    )
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
        material=trimesh.visual.material.PBRMaterial(
            name="textured", baseColorTexture=image, metallicFactor=0.0, roughnessFactor=0.8
        ),
    )
    scene = trimesh.Scene()
    scene.add_geometry(mesh, node_name="quad", geom_name="quad")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(scene.export(file_type="glb"))
    return path


@pytest.fixture
def textured_catalog(tmp_path: Path) -> Path:
    root = tmp_path / "catalog"
    write_body(root, "102000015", ["torso_body"])
    piece_dir = root / "torso" / "203000196"
    write_textured_piece(piece_dir / "mesh.glb")
    (piece_dir / "manifest.json").write_text(
        '{"item_id": "203000196", "type": "torso", "mesh": "mesh.glb",'
        ' "mount": {"position": [0, 0, 0]}, "catalog_version": "test-1"}',
        encoding="utf-8",
    )
    return root


def textured_materials(glb: bytes) -> list[object]:
    scene = trimesh.load(io.BytesIO(glb), file_type="glb", force="scene", process=False)
    assert isinstance(scene, trimesh.Scene)
    found = []
    for geometry in scene.geometry.values():
        material = getattr(getattr(geometry, "visual", None), "material", None)
        texture = getattr(material, "baseColorTexture", None) if material is not None else None
        if texture is not None:
            found.append(texture)
    return found


def test_pillow_is_installed_otherwise_textures_are_dropped_silently() -> None:
    # This is the canary: without Pillow, trimesh loads the same GLB with zero
    # textures and exports a valid but untextured file.
    assert Image.__version__


def test_export_keeps_the_embedded_texture(textured_catalog: Path) -> None:
    catalog = load_catalog(textured_catalog)
    assert catalog.problems == ()

    result = build_outfit(
        avatar_id="102000015", items=["203000196"], catalog=catalog
    )
    assert result.status == "ready"

    textures = textured_materials(result.glb)
    assert textures, "exported GLB lost its texture"
    assert textures[0].size == (8, 8)

    pixels = textures[0].convert("RGB").getpixel((0, 0))
    assert pixels == TEXTURE_RGB


def test_resource_count_reports_the_texture(textured_catalog: Path) -> None:
    catalog = load_catalog(textured_catalog)
    result = build_outfit(
        avatar_id="102000015", items=["203000196"], catalog=catalog
    )
    meshes, materials, images = count_resources(result.glb)
    assert meshes >= 2
    assert materials >= 2
    assert images == len(textured_materials(result.glb))
    assert result.images == images


def test_worker_publishes_a_file_that_still_has_pixels(
    textured_catalog: Path, tmp_path: Path
) -> None:
    config = make_config(tmp_path, textured_catalog)
    store = Store(config.data_dir / "ffhub.sqlite3")
    enqueue(
        store,
        uid="11807385",
        region="br",
        avatar_id="102000015",
        items=["203000196"],
        catalog_version="test-1",
        exporter_version="test",
    )
    claimed = store.claim_next()
    assert claimed is not None

    finished = process_job(claimed, config=config, store=store)
    assert finished.state == "ready"

    published = Path(finished.glb_path).read_bytes()
    textures = textured_materials(published)
    assert textures, "published GLB lost its texture"
    assert textures[0].size == (8, 8)
    assert textures[0].convert("RGB").getpixel((0, 0)) == TEXTURE_RGB
    assert "textured" in finished.detail
