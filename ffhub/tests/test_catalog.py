from __future__ import annotations

import json
from pathlib import Path

from app.catalog import MOUNT_ORDER, load_catalog

from conftest import write_body, write_piece


def test_catalog_loads_body_and_pieces(catalog_root: Path) -> None:
    catalog = load_catalog(catalog_root)
    assert catalog.problems == ()
    assert catalog.version == "test-1"
    assert catalog.body("102000015") is not None
    assert set(catalog.pieces) == {"211000087", "203000196", "204000103", "205000070"}
    assert catalog.pieces["211000087"].hides == ("body:head_skin",)


def test_pieces_come_back_in_mount_order(catalog_root: Path) -> None:
    catalog = load_catalog(catalog_root)
    ordered, missing = catalog.ordered_pieces(
        ["211000087", "203000196", "205000070", "204000103"]
    )
    assert [piece.type for piece in ordered] == ["feet", "legs", "torso", "head"]
    assert [piece.type for piece in ordered] == sorted(
        [piece.type for piece in ordered], key=MOUNT_ORDER.index
    )
    assert missing == []


def test_unknown_item_is_reported_as_missing(catalog_root: Path) -> None:
    catalog = load_catalog(catalog_root)
    ordered, missing = catalog.ordered_pieces(["203000196", "999999999"])
    assert [piece.item_id for piece in ordered] == ["203000196"]
    assert missing == ["999999999"]


def test_duplicate_items_are_ignored_once(catalog_root: Path) -> None:
    catalog = load_catalog(catalog_root)
    ordered, _ = catalog.ordered_pieces(["203000196", "203000196"])
    assert len(ordered) == 1


def test_missing_mesh_fails_at_load(tmp_path: Path) -> None:
    root = tmp_path / "catalog"
    directory = root / "torso" / "203000196"
    directory.mkdir(parents=True)
    (directory / "manifest.json").write_text(
        json.dumps({"item_id": "203000196", "type": "torso", "mesh": "absent.glb"}),
        encoding="utf-8",
    )
    catalog = load_catalog(root)
    assert catalog.pieces == {}
    assert any("mesh not found" in problem for problem in catalog.problems)


def test_unknown_type_fails_at_load(tmp_path: Path) -> None:
    root = tmp_path / "catalog"
    write_piece(root, item_id="203000196", piece_type="hat", nodes=["x"])
    catalog = load_catalog(root)
    assert catalog.pieces == {}
    assert any("unknown type" in problem for problem in catalog.problems)


def test_duplicate_item_id_fails_at_load(tmp_path: Path) -> None:
    root = tmp_path / "catalog"
    write_piece(root, item_id="203000196", piece_type="torso", nodes=["a"])
    write_piece(root, item_id="203000196", piece_type="legs", nodes=["b"])
    catalog = load_catalog(root)
    assert any("duplicate piece" in problem for problem in catalog.problems)


def test_mesh_outside_piece_directory_is_refused(tmp_path: Path) -> None:
    root = tmp_path / "catalog"
    directory = root / "torso" / "203000196"
    directory.mkdir(parents=True)
    outside = tmp_path / "elsewhere.glb"
    outside.write_bytes(b"glTF-not-really")
    (directory / "manifest.json").write_text(
        json.dumps({"item_id": "203000196", "type": "torso", "mesh": "../../../elsewhere.glb"}),
        encoding="utf-8",
    )
    catalog = load_catalog(root)
    assert any("escapes" in problem for problem in catalog.problems)


def test_mixed_catalog_versions_are_flagged(tmp_path: Path) -> None:
    root = tmp_path / "catalog"
    write_body(root, "102000015", ["head_skin"])
    write_piece(root, item_id="203000196", piece_type="torso", nodes=["a"])
    manifest = root / "torso" / "203000196" / "manifest.json"
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    payload["catalog_version"] = "test-2"
    manifest.write_text(json.dumps(payload), encoding="utf-8")
    catalog = load_catalog(root)
    assert any("mixes versions" in problem for problem in catalog.problems)
    assert catalog.version == ""
