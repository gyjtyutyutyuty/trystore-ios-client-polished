from __future__ import annotations

import io
from pathlib import Path

import pytest
import trimesh

from app.assemble import AssemblyError, build_outfit, count_resources
from app.catalog import load_catalog
from app.validate import verify_export


def node_names(glb: bytes) -> list[str]:
    scene = trimesh.load(io.BytesIO(glb), file_type="glb", force="scene", process=False)
    assert isinstance(scene, trimesh.Scene)
    return list(scene.geometry.keys())


def test_outfit_mounts_every_piece(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    result = build_outfit(
        avatar_id="102000015",
        items=["211000087", "203000196", "204000103", "205000070"],
        catalog=catalog,
    )
    assert result.status == "ready"
    assert sorted(result.mounted) == ["203000196", "204000103", "205000070", "211000087"]
    assert result.missing == []
    nodes = node_names(result.glb)
    assert len(nodes) == 6  # 3 body nodes + 4 pieces, minus the hidden head skin
    for item_id in result.mounted:
        assert any(item_id in node for node in nodes)


def test_hide_rule_drops_body_skin(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    result = build_outfit(
        avatar_id="102000015",
        items=["211000087"],
        catalog=catalog,
    )
    nodes = node_names(result.glb)
    assert "head_skin" not in nodes
    assert "torso_body" in nodes
    assert any("211000087" in node for node in nodes)


def test_missing_piece_makes_the_result_partial(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    result = build_outfit(
        avatar_id="102000015",
        items=["203000196", "999999999"],
        catalog=catalog,
    )
    assert result.status == "partial"
    assert result.missing == ["999999999"]
    assert "999999999" in result.detail


def test_incompatible_body_is_skipped_not_mounted(tmp_path: Path) -> None:
    from conftest import write_body, write_piece

    root = tmp_path / "catalog"
    write_body(root, "102000015", ["head_skin"])
    write_piece(
        root,
        item_id="211000087",
        piece_type="head",
        nodes=["head_hat"],
        compatible=["999000111"],
    )
    catalog = load_catalog(root)
    result = build_outfit(avatar_id="102000015", items=["211000087"], catalog=catalog)
    assert result.status == "partial"
    assert result.skipped[0]["reason"] == "incompatible_body"
    assert result.mounted == []


def test_unknown_avatar_is_an_error(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    with pytest.raises(AssemblyError):
        build_outfit(avatar_id="000000000", items=[], catalog=catalog)


def test_resources_are_counted_from_bytes(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    result = build_outfit(avatar_id="102000015", items=["203000196"], catalog=catalog)
    meshes, materials, _images = count_resources(result.glb)
    assert meshes == len(node_names(result.glb))
    assert materials >= 1


def test_verify_export_reports_ready_and_partial(catalog_root: Path, tmp_path: Path) -> None:
    catalog = load_catalog(catalog_root)
    result = build_outfit(avatar_id="102000015", items=["203000196"], catalog=catalog)
    exported = tmp_path / "outfit.glb"
    exported.write_bytes(result.glb)

    state, detail = verify_export(exported, ["203000196"])
    assert state == "ready"
    assert "meshes" in detail

    state, detail = verify_export(exported, ["203000196", "204000103"])
    assert state == "partial"
    assert "204000103" in detail


def test_verify_export_rejects_garbage(tmp_path: Path) -> None:
    broken = tmp_path / "broken.glb"
    broken.write_bytes(b"not a glb")
    state, _ = verify_export(broken, [])
    assert state == "error"
