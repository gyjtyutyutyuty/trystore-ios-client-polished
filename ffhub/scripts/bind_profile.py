#!/usr/bin/env python3
"""Point the Golden Sakura catalog at a real profile's avatar and item ids.

The catalog ships with placeholder ids (`golden_sakura`, `gsk_*`) because a
downloaded bundle carries no Free Fire ids. A saved `/profile` answer has them:

    curl -s -H "Authorization: Bearer $FFHUB_TOKEN" \\
         -H 'content-type: application/json' \\
         -d '{"uid":"11807385","region":"us"}' \\
         https://hub.example.com/profile > profile.json
    .venv/bin/python scripts/bind_profile.py profile.json

One directory rename per entry and a manifest rewritten inside it. Every
refusal happens before the first rename: a half-renamed catalog loads as
invalid and the worker fails closed, so nothing is moved on a bad input.

A profile saved against this catalog cannot say what each garment *is* — the
panel fills `type` from the catalog, so unknown ids come back as `unknown`.
Pass the slots yourself, one `--map` each, keyed by type or by the current
entry id:

    ... bind_profile.py profile.json --map feet=205000070 --map gsk_torso=203000196
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.catalog import load_catalog  # noqa: E402
from app.ids import AVATAR_PATTERN, ITEM_PATTERN  # noqa: E402

PIECE_TYPES = ("feet", "legs", "torso", "head", "hair")
SOURCE_BODY = "golden_sakura"
SOURCE_PIECES = {
    "feet": "gsk_feet",
    "legs": "gsk_legs",
    "torso": "gsk_torso",
    "head": "gsk_head",
    "hair": "gsk_hair",
}

EXIT_OK = 0
EXIT_BROKEN = 1
EXIT_BAD_PROFILE = 2
EXIT_NOT_A_BUNDLE = 3
EXIT_CONFLICT = 4

ENTRY_ID_KEYS = ("item_id", "itemId", "itemID", "id")


class Refusal(RuntimeError):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Binding:
    piece_type: str
    source: Path
    target: Path
    item_id: str


def _entry_id(entry: object) -> str:
    if isinstance(entry, dict):
        for key in ENTRY_ID_KEYS:
            value = entry.get(key)
            if value not in (None, ""):
                return str(value).strip()
        return ""
    return str(entry).strip()


def _entry_type(entry: object) -> str | None:
    if not isinstance(entry, dict):
        return None
    value = entry.get("type")
    return value if value in PIECE_TYPES else None


def read_profile(path: Path) -> tuple[str, list[tuple[str | None, str]]]:
    """Avatar id and (type or None, item id) pairs, from either JSON shape."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise Refusal(EXIT_BAD_PROFILE, f"could not read {path}: {exc}") from None
    except ValueError:
        raise Refusal(EXIT_BAD_PROFILE, f"{path} is not JSON") from None
    if not isinstance(payload, dict):
        raise Refusal(EXIT_BAD_PROFILE, "profile is not an object")

    avatar = payload.get("avatar_id") or payload.get("avatarId")
    entries = payload.get("clothes")
    if entries is None:
        # The provider payload nests everything under profileInfo and sends
        # clothes as a bare id list, with no slots at all.
        info = payload.get("profileInfo")
        if isinstance(info, dict):
            avatar = avatar or info.get("avatarId")
            entries = info.get("clothes")
    if entries is None or not isinstance(entries, (list, tuple)):
        raise Refusal(
            EXIT_BAD_PROFILE,
            "profile has no clothes list — save the /profile answer or the provider payload",
        )

    pairs: list[tuple[str | None, str]] = []
    for entry in entries:
        item_id = _entry_id(entry)
        if not item_id:
            raise Refusal(EXIT_BAD_PROFILE, "a clothes entry has no id")
        pairs.append((_entry_type(entry), item_id))
    return (str(avatar).strip() if avatar else ""), pairs


def parse_map(raw: str) -> tuple[str, str]:
    key, separator, value = raw.partition("=")
    key, value = key.strip(), value.strip()
    if not separator or not key or not value:
        raise Refusal(EXIT_BAD_PROFILE, f"--map expects TYPE=ITEM_ID, got {raw!r}")
    if key in PIECE_TYPES:
        return key, value
    for piece_type, source in SOURCE_PIECES.items():
        if key == source:
            return piece_type, value
    if key == SOURCE_BODY:
        raise Refusal(
            EXIT_BAD_PROFILE, "the body id comes from the profile's avatar_id, not from --map"
        )
    raise Refusal(
        EXIT_BAD_PROFILE,
        f"unknown --map key {key!r}; use one of {', '.join(PIECE_TYPES)} "
        f"or {', '.join(SOURCE_PIECES.values())}",
    )


def collect(
    pairs: list[tuple[str | None, str]], overrides: list[tuple[str, str]]
) -> dict[str, str]:
    targets: dict[str, str] = {}
    for piece_type, item_id in pairs:
        if piece_type is None:
            continue
        if piece_type in targets and targets[piece_type] != item_id:
            raise Refusal(
                EXIT_BAD_PROFILE,
                f"two ids claim to be {piece_type}: {targets[piece_type]} and {item_id}",
            )
        targets[piece_type] = item_id
    for piece_type, item_id in overrides:
        targets[piece_type] = item_id

    missing = [piece_type for piece_type in PIECE_TYPES if piece_type not in targets]
    if missing:
        flags = " ".join(f"--map {piece_type}=<item_id>" for piece_type in missing)
        raise Refusal(
            EXIT_BAD_PROFILE,
            f"no item id for {', '.join(missing)}; the profile only carries ids, "
            f"so tell the script which slot is which: {flags}",
        )
    return targets


def validate(avatar: str, targets: dict[str, str]) -> None:
    if not avatar:
        raise Refusal(EXIT_BAD_PROFILE, "profile has no avatar_id")
    if not AVATAR_PATTERN.fullmatch(avatar):
        raise Refusal(EXIT_BAD_PROFILE, f"avatar_id {avatar!r} is not 6 to 20 digits")
    malformed = [
        f"{piece_type}={item_id}"
        for piece_type, item_id in targets.items()
        if not ITEM_PATTERN.fullmatch(item_id)
    ]
    if malformed:
        raise Refusal(
            EXIT_BAD_PROFILE,
            f"not an item id (4 to 20 digits): {', '.join(malformed)}",
        )
    claimed: dict[str, str] = {}
    for piece_type in PIECE_TYPES:
        item_id = targets[piece_type]
        if item_id in claimed:
            raise Refusal(
                EXIT_CONFLICT,
                f"{claimed[item_id]} and {piece_type} both map to {item_id}",
            )
        claimed[item_id] = piece_type


def plan(root: Path, avatar: str, targets: dict[str, str]) -> tuple[list[Binding], Path, Path]:
    if not root.is_dir():
        raise Refusal(EXIT_NOT_A_BUNDLE, f"no catalog at {root}")

    bindings: list[Binding] = []
    for piece_type in PIECE_TYPES:
        source = root / piece_type / SOURCE_PIECES[piece_type]
        if not (source / "manifest.json").is_file() or not (source / "mesh.glb").is_file():
            raise Refusal(
                EXIT_NOT_A_BUNDLE,
                f"{source} is not an unbound Golden Sakura entry — already bound, "
                "or this catalog is a different bundle",
            )
        target = root / piece_type / targets[piece_type]
        if target != source and target.exists():
            raise Refusal(EXIT_CONFLICT, f"{target} already exists; refusing to overwrite it")
        bindings.append(Binding(piece_type, source, target, targets[piece_type]))

    body_source = root / "body" / SOURCE_BODY
    if not (body_source / "manifest.json").is_file() or not (body_source / "mesh.glb").is_file():
        raise Refusal(
            EXIT_NOT_A_BUNDLE,
            f"{body_source} is not the unbound Golden Sakura body — already bound, "
            "or this catalog is a different bundle",
        )
    body_target = root / "body" / avatar
    if body_target != body_source and body_target.exists():
        raise Refusal(EXIT_CONFLICT, f"{body_target} already exists; refusing to overwrite it")
    return bindings, body_source, body_target


def rewrite_manifest(directory: Path, key: str, value: str, avatar: str) -> None:
    manifest_path = directory / "manifest.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    payload[key] = value
    compatible = payload.get("compatible_avatars")
    if isinstance(compatible, list) and SOURCE_BODY in compatible:
        payload["compatible_avatars"] = [
            avatar if entry == SOURCE_BODY else entry for entry in compatible
        ]
    manifest_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bind_profile", description=__doc__.splitlines()[0])
    parser.add_argument("profile", type=Path, help="saved /profile or provider JSON")
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "catalog",
        help="catalog root (default: ffhub/catalog)",
    )
    parser.add_argument(
        "--map",
        action="append",
        default=[],
        metavar="TYPE=ITEM_ID",
        help="slot for one item id, e.g. feet=205000070 or gsk_feet=205000070; repeatable",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the renames and stop")
    args = parser.parse_args(argv)

    try:
        avatar, pairs = read_profile(args.profile)
        overrides = [parse_map(value) for value in args.map]
        targets = collect(pairs, overrides)
        validate(avatar, targets)
        bindings, body_source, body_target = plan(args.catalog, avatar, targets)
    except Refusal as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return exc.code

    print(f"body    {body_source.name} -> {avatar}")
    for binding in bindings:
        print(f"{binding.piece_type:<7} {binding.source.name} -> {binding.item_id}")
    if args.dry_run:
        return EXIT_OK

    for binding in bindings:
        if binding.source != binding.target:
            binding.source.rename(binding.target)
        rewrite_manifest(binding.target, "item_id", binding.item_id, avatar)
    if body_source != body_target:
        body_source.rename(body_target)
    rewrite_manifest(body_target, "avatar_id", avatar, avatar)

    catalog = load_catalog(args.catalog)
    if catalog.problems:
        print(f"catalog is invalid after binding: {catalog.problems[0]}", file=sys.stderr)
        return EXIT_BROKEN
    unresolved = [targets[name] for name in PIECE_TYPES if catalog.piece(targets[name]) is None]
    if unresolved or catalog.body(avatar) is None:
        print(
            f"catalog did not reload with avatar {avatar} and {', '.join(unresolved) or 'all pieces'}",
            file=sys.stderr,
        )
        return EXIT_BROKEN

    print(f"bound 1 body and {len(bindings)} pieces to avatar {avatar}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
