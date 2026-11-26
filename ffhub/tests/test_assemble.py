from __future__ import annotations

import io
import json
import struct
from pathlib import Path

import numpy as np
import pytest
import trimesh

from app.assemble import AssemblyError, build_outfit, count_resources
from app.catalog import load_catalog
from app.validate import verify_export

REAL_CATALOG = Path(__file__).resolve().parents[1] / "catalog"
TRYSTORE_MODELS = Path(__file__).resolve().parents[2] / "ThreeOneOSFive" / "CharacterModels"
SAMPLE_DIR = Path(__file__).resolve().parents[2] / "artifacts" / "ffhub-example"


def node_names(glb: bytes) -> list[str]:
    scene = trimesh.load(io.BytesIO(glb), file_type="glb", force="scene", process=False)
    assert isinstance(scene, trimesh.Scene)
    return list(scene.geometry.keys())


def glb_document(data: bytes) -> dict:
    magic, version, total = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67
    assert version == 2
    assert total == len(data)
    offset = 12
    while offset < total:
        size, kind = struct.unpack_from("<II", data, offset)
        if kind == 0x4E4F534A:
            return json.loads(data[offset + 8 : offset + 8 + size].rstrip(b" \t\r\n\x00"))
        offset += 8 + size
    raise AssertionError("GLB has no JSON chunk")


def canonical_triangles(mesh: trimesh.Trimesh) -> list[tuple[tuple[float, float, float], ...]]:
    """Triangle surfaces, independent of vertex indexing and weld order."""
    triangles = []
    for triangle in np.asarray(mesh.triangles):
        triangles.append(
            tuple(sorted(tuple(np.round(vertex, 5)) for vertex in triangle))
        )
    return sorted(triangles)


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


def test_real_catalog_pieces_keep_their_vertices_when_attached() -> None:
    """Downloaded catalogue pieces must mount, not be deformed."""
    catalog = load_catalog(REAL_CATALOG)
    assert catalog.problems == ()
    item_ids = ["205000070", "204000103", "203000196", "211000303", "214000000"]

    result = build_outfit(avatar_id="102000015", items=item_ids, catalog=catalog)
    assert result.status == "ready"
    assert sorted(result.mounted) == sorted(item_ids)

    assembled = trimesh.load(
        io.BytesIO(result.glb), file_type="glb", force="scene", process=False
    )
    assert isinstance(assembled, trimesh.Scene)

    pieces, missing = catalog.ordered_pieces(item_ids)
    assert missing == []
    for piece in pieces:
        source = trimesh.load(piece.mesh, force="scene", process=False)
        assert isinstance(source, trimesh.Scene)
        assert len(source.geometry) == 1
        source_geometry = next(iter(source.geometry.values()))

        matching = [name for name in assembled.geometry if piece.item_id in name]
        assert len(matching) == 1, f"{piece.item_id} was not attached exactly once"
        attached = assembled.geometry[matching[0]]

        assert len(attached.vertices) == len(source_geometry.vertices)
        assert len(attached.faces) == len(source_geometry.faces)
        assert np.allclose(
            np.sort(np.asarray(attached.vertices), axis=0),
            np.sort(np.asarray(source_geometry.vertices), axis=0),
            atol=1e-5,
        ), f"{piece.item_id} changed its vertices while being mounted"
        assert np.allclose(attached.bounds, source_geometry.bounds, atol=1e-5)


def test_catalog_body_is_the_trystore_sakura_model() -> None:
    """The GLB body is the same mesh the TryStore app loads, not a proxy."""
    source = trimesh.load(
        TRYSTORE_MODELS / "sakura" / "sakura.obj", force="scene", process=False
    )
    assert isinstance(source, trimesh.Scene)
    assert "mat0" in source.geometry
    source_geometry = source.geometry["mat0"]

    body = trimesh.load(
        REAL_CATALOG / "body" / "102000015" / "mesh.glb",
        force="scene",
        process=False,
    )
    assert isinstance(body, trimesh.Scene) and len(body.geometry) == 1
    body_geometry = next(iter(body.geometry.values()))

    assert body_geometry.vertices.shape == source_geometry.vertices.shape
    assert body_geometry.faces.shape == source_geometry.faces.shape
    assert np.allclose(
        np.sort(np.asarray(body_geometry.vertices), axis=0),
        np.sort(np.asarray(source_geometry.vertices), axis=0),
        atol=1e-5,
    )


def test_items_can_change_without_rebuilding_the_body() -> None:
    catalog = load_catalog(REAL_CATALOG)
    full = build_outfit(
        avatar_id="102000015",
        items=["205000070", "204000103", "203000196", "211000303", "214000000"],
        catalog=catalog,
    )
    swapped = build_outfit(
        avatar_id="102000015",
        items=["203000196", "204000103"],
        catalog=catalog,
    )
    assert full.status == "ready" and swapped.status == "ready"

    full_nodes = node_names(full.glb)
    swapped_nodes = node_names(swapped.glb)
    assert "body" in full_nodes and "body" in swapped_nodes
    assert any("203000196" in node for node in swapped_nodes)
    assert any("204000103" in node for node in swapped_nodes)
    assert not any("205000070" in node for node in swapped_nodes)
    assert not any("211000303" in node for node in swapped_nodes)

    full_scene = trimesh.load(
        io.BytesIO(full.glb), file_type="glb", force="scene", process=False
    )
    swapped_scene = trimesh.load(
        io.BytesIO(swapped.glb), file_type="glb", force="scene", process=False
    )
    assert isinstance(full_scene, trimesh.Scene) and isinstance(swapped_scene, trimesh.Scene)
    assert np.allclose(
        np.sort(np.asarray(full_scene.geometry["body"].vertices), axis=0),
        np.sort(np.asarray(swapped_scene.geometry["body"].vertices), axis=0),
        atol=1e-5,
    )


def test_real_outfit_never_stretches_a_garment() -> None:
    catalog = load_catalog(REAL_CATALOG)
    result = build_outfit(
        avatar_id="102000015",
        items=["205000070", "204000103", "203000196", "211000303", "214000000"],
        catalog=catalog,
    )
    assert result.status == "ready"

    document = glb_document(result.glb)
    for node in document.get("nodes", []):
        scale = node.get("scale")
        if scale:
            assert max(scale) - min(scale) < 1e-6, (
                f"node {node.get('name')} has a non-uniform scale {scale}"
            )
        matrix = node.get("matrix")
        if matrix:
            lengths = [
                sum(matrix[column * 4 + row] ** 2 for row in range(3)) ** 0.5
                for column in range(3)
            ]
            assert max(lengths) - min(lengths) < 1e-6, (
                f"node {node.get('name')} has a non-uniform matrix scale {lengths}"
            )


def test_sample_outfit_geometry_matches_the_original_backup() -> None:
    if not SAMPLE_DIR.is_dir():
        pytest.skip("sample outfit artifacts are not present in this checkout")

    sample_path = SAMPLE_DIR / "sample-outfit.glb"
    original_path = SAMPLE_DIR / "sample-outfit.original.glb"
    assert original_path.is_file(), "the original GLB backup is missing"

    sample = trimesh.load(sample_path, force="scene", process=False)
    original = trimesh.load(original_path, force="scene", process=False)
    assert isinstance(sample, trimesh.Scene) and isinstance(original, trimesh.Scene)
    assert sample.geometry.keys() == original.geometry.keys()

    for name in original.geometry:
        actual = sample.geometry[name]
        expected = original.geometry[name]
        assert len(actual.faces) == len(expected.faces), f"{name} lost faces"
        assert canonical_triangles(actual) == canonical_triangles(
            expected
        ), f"{name} was deformed"
        assert np.allclose(actual.bounds, expected.bounds, atol=1e-5), (
            f"{name} moved while being optimized"
        )


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
