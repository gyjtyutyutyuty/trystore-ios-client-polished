from __future__ import annotations

import asyncio
import json
from pathlib import Path

import pytest
import trimesh

from app.config import Config
from app.ffapi import Profile


def write_glb(path: Path, node_names: list[str]) -> Path:
    scene = trimesh.Scene()
    for index, name in enumerate(node_names):
        box = trimesh.creation.box(extents=(1.0, 1.0, 1.0))
        box.apply_translation((index * 2.0, 0.0, 0.0))
        # Real pieces always carry a material; give the fixtures one so the
        # resource count is exercised instead of trivially zero.
        box.visual = trimesh.visual.TextureVisuals(
            material=trimesh.visual.material.PBRMaterial(
                name=f"mat-{name}",
                baseColorFactor=[0.8, 0.4, 0.2, 1.0],
                metallicFactor=0.0,
                roughnessFactor=0.9,
            )
        )
        scene.add_geometry(box, node_name=name, geom_name=name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(scene.export(file_type="glb"))
    return path


def write_body(root: Path, avatar_id: str, nodes: list[str]) -> Path:
    directory = root / "body" / avatar_id
    directory.mkdir(parents=True, exist_ok=True)
    write_glb(directory / "mesh.glb", nodes)
    (directory / "manifest.json").write_text(
        json.dumps(
            {
                "avatar_id": avatar_id,
                "mesh": "mesh.glb",
                "mount": {"position": [0, 0, 0], "scale": 1.0},
                "catalog_version": "test-1",
            }
        ),
        encoding="utf-8",
    )
    return directory


def write_piece(
    root: Path,
    *,
    item_id: str,
    piece_type: str,
    nodes: list[str],
    hides: list[str] | None = None,
    compatible: list[str] | None = None,
    mount: dict | None = None,
) -> Path:
    directory = root / piece_type / item_id
    directory.mkdir(parents=True, exist_ok=True)
    write_glb(directory / "mesh.glb", nodes)
    manifest = {
        "item_id": item_id,
        "type": piece_type,
        "mesh": "mesh.glb",
        "label": f"{piece_type} {item_id}",
        "mount": mount or {"position": [0, 1, 0], "rotation_euler_deg": [0, 0, 0], "scale": 1.0},
        "hides": hides or [],
        "compatible_avatars": compatible or [],
        "catalog_version": "test-1",
    }
    (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return directory


@pytest.fixture
def catalog_root(tmp_path: Path) -> Path:
    root = tmp_path / "catalog"
    write_body(root, "102000015", ["head_skin", "torso_body", "legs_skin"])
    write_piece(
        root,
        item_id="211000087",
        piece_type="head",
        nodes=["head_hat"],
        hides=["body:head_skin"],
        mount={"position": [0, 2, 0], "rotation_euler_deg": [0, 0, 180], "scale": 1.0},
    )
    write_piece(root, item_id="203000196", piece_type="torso", nodes=["torso_shirt"])
    write_piece(root, item_id="204000103", piece_type="legs", nodes=["legs_pants"])
    write_piece(root, item_id="205000070", piece_type="feet", nodes=["feet_boots"])
    return root


def make_config(tmp_path: Path, catalog_dir: Path | None = None) -> Config:
    return Config(
        api_key="test-key-not-real",
        api_base="https://example.invalid/api/v1",
        data_dir=tmp_path / "data",
        catalog_dir=catalog_dir or (tmp_path / "catalog"),
        bearer_token="panel-token",
        exporter_version="test",
        catalog_version="test-1",
        request_timeout=5.0,
        max_glb_bytes=64 * 1024 * 1024,
        provider_attempts=1,
    )


def run(coro):
    return asyncio.run(coro)


def profile_payload(**overrides) -> Profile:
    base = dict(
        uid="11807385",
        account_id="11807385",
        nickname="Carlos",
        region="US",
        avatar_id="102000015",
        clothes=("211000087", "203000196", "204000103", "205000070"),
        raw={},
    )
    base.update(overrides)
    return Profile(**base)
