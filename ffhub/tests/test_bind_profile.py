from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from app.catalog import load_catalog

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "bind_profile.py"
PIECE_TYPES = ("feet", "legs", "torso", "head", "hair")

PANEL_PROFILE = {
    "uid": "11807385",
    "avatar_id": "102000015",
    "clothes": [
        {"item_id": "205000070", "type": "feet"},
        {"item_id": "204000103", "type": "legs"},
        {"item_id": "203000196", "type": "torso"},
        {"item_id": "211000087", "type": "head"},
        {"item_id": "214000053", "type": "hair"},
    ],
}

RAW_PROVIDER = {
    "basicInfo": {"accountId": "11807385"},
    "profileInfo": {"avatarId": "102000015", "clothes": [205000070, 204000103, 203000196, 211000087, 214000053]},
}

RAW_MAP = [
    "feet=205000070",
    "legs=204000103",
    "torso=203000196",
    "head=211000087",
    "hair=214000053",
]


def unbound_catalog(root: Path) -> Path:
    body = root / "body" / "golden_sakura"
    body.mkdir(parents=True)
    (body / "mesh.glb").write_bytes(b"glTF")
    (body / "manifest.json").write_text(
        json.dumps({"avatar_id": "golden_sakura", "mesh": "mesh.glb", "catalog_version": "golden-sakura-1"}),
        encoding="utf-8",
    )
    for piece_type in PIECE_TYPES:
        directory = root / piece_type / f"gsk_{piece_type}"
        directory.mkdir(parents=True)
        (directory / "mesh.glb").write_bytes(b"glTF")
        (directory / "manifest.json").write_text(
            json.dumps(
                {
                    "item_id": f"gsk_{piece_type}",
                    "type": piece_type,
                    "mesh": "mesh.glb",
                    "catalog_version": "golden-sakura-1",
                }
            ),
            encoding="utf-8",
        )
    return root


def save(tmp_path: Path, payload: dict) -> Path:
    path = tmp_path / "profile.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def bind(tmp_path: Path, profile: Path, *flags: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(profile), "--catalog", str(tmp_path / "catalog"), *flags],
        capture_output=True,
        text=True,
        timeout=60,
    )


def untouched(root: Path) -> bool:
    return (root / "body" / "golden_sakura" / "manifest.json").is_file() and all(
        (root / piece_type / f"gsk_{piece_type}" / "manifest.json").is_file()
        for piece_type in PIECE_TYPES
    )


def test_a_panel_profile_renames_the_body_and_every_piece(tmp_path: Path) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    result = bind(tmp_path, save(tmp_path, PANEL_PROFILE))

    assert result.returncode == 0, result.stderr
    catalog = load_catalog(root)
    assert catalog.problems == ()
    assert catalog.body("102000015") is not None
    for piece_type, item_id in (
        ("feet", "205000070"),
        ("legs", "204000103"),
        ("torso", "203000196"),
        ("head", "211000087"),
        ("hair", "214000053"),
    ):
        piece = catalog.piece(item_id)
        assert piece is not None, item_id
        assert piece.type == piece_type
        assert piece.mesh.parent == root / piece_type / item_id
        assert not (root / piece_type / f"gsk_{piece_type}").exists()


def test_the_bare_provider_payload_needs_the_slots_and_is_refused_without_them(
    tmp_path: Path,
) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    result = bind(tmp_path, save(tmp_path, RAW_PROVIDER))

    assert result.returncode == 2
    assert "--map" in result.stderr
    assert untouched(root)


def test_map_flags_fill_in_the_slots_the_provider_never_sends(tmp_path: Path) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    flags: list[str] = []
    for value in RAW_MAP:
        flags += ["--map", value]

    result = bind(tmp_path, save(tmp_path, RAW_PROVIDER), *flags)

    assert result.returncode == 0, result.stderr
    assert load_catalog(root).piece("205000070") is not None
    assert not (root / "feet" / "gsk_feet").exists()


def test_two_slots_claiming_the_same_id_are_refused(tmp_path: Path) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    profile = {
        "avatar_id": "102000015",
        "clothes": [
            {"item_id": "203000196", "type": "torso"},
            {"item_id": "203000196", "type": "legs"},
        ],
    }

    # Only the three missing slots are overridden, so the duplicated id from
    # the profile still reaches validation.
    result = bind(
        tmp_path,
        save(tmp_path, profile),
        "--map",
        "feet=205000070",
        "--map",
        "head=211000087",
        "--map",
        "hair=214000053",
    )

    assert result.returncode == 4
    assert "both map to 203000196" in result.stderr
    assert untouched(root)


def test_an_existing_target_directory_is_not_overwritten(tmp_path: Path) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    taken = root / "torso" / "203000196"
    taken.mkdir(parents=True)
    (taken / "manifest.json").write_text("{}", encoding="utf-8")

    result = bind(tmp_path, save(tmp_path, PANEL_PROFILE))

    assert result.returncode == 4
    assert "already exists" in result.stderr
    assert untouched(root)


def test_dry_run_prints_the_plan_and_moves_nothing(tmp_path: Path) -> None:
    root = unbound_catalog(tmp_path / "catalog")

    result = bind(tmp_path, save(tmp_path, PANEL_PROFILE), "--dry-run")

    assert result.returncode == 0, result.stderr
    assert "gsk_feet -> 205000070" in result.stdout
    assert untouched(root)


@pytest.mark.parametrize("avatar", ["", "golden-sakura", "123"])
def test_a_profile_without_a_numeric_avatar_is_refused(tmp_path: Path, avatar: str) -> None:
    root = unbound_catalog(tmp_path / "catalog")
    profile = {**PANEL_PROFILE, "avatar_id": avatar}

    result = bind(tmp_path, save(tmp_path, profile))

    assert result.returncode == 2
    assert "avatar" in result.stderr
    assert untouched(root)
