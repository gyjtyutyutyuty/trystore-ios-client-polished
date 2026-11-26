// Outfit assembly against the static catalog that ships with the panel.
//
// The index mirrors the Python loader's contract: one body per avatar and one
// entry per item, each pointing at a GLB whose geometry is already in the
// body's coordinate space. Pieces mount in slot order, exactly like
// app/assemble.py, so the same outfit produces the same layering.

import { mergeGlbs } from "./glb.js";

export const MOUNT_ORDER = [
  "feet",
  "legs",
  "torso",
  "face_paint",
  "head",
  "hair",
  "accessory",
];

export const INDEX_PATH = "catalog/index.json";

export class AssembleFailure extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

export function validateIndex(index) {
  if (!index || typeof index !== "object") throw new AssembleFailure("catalog_invalid", "index is not an object");
  if (!index.bodies || typeof index.bodies !== "object" || Object.keys(index.bodies).length === 0) {
    throw new AssembleFailure("catalog_invalid", "index has no bodies");
  }
  if (!index.pieces || typeof index.pieces !== "object") {
    throw new AssembleFailure("catalog_invalid", "index has no pieces map");
  }
  for (const [id, piece] of Object.entries(index.pieces)) {
    if (!piece || typeof piece.mesh !== "string" || typeof piece.type !== "string") {
      throw new AssembleFailure("catalog_invalid", `piece ${id} is incomplete`);
    }
    if (!MOUNT_ORDER.includes(piece.type)) {
      throw new AssembleFailure("catalog_invalid", `piece ${id} has unknown type ${piece.type}`);
    }
  }
  return index;
}

/** Same rule as the Python loader: a slot with no entry is reported, not guessed. */
export function resolveItems(index, items) {
  const seen = new Set();
  const ordered = [];
  const missing = [];
  for (const raw of items ?? []) {
    const id = String(raw).trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const piece = index.pieces[id];
    if (!piece) {
      missing.push(id);
      continue;
    }
    ordered.push({ id, type: piece.type, mesh: piece.mesh, label: piece.label ?? "" });
  }
  const rank = new Map(MOUNT_ORDER.map((type, position) => [type, position]));
  ordered.sort((a, b) => (rank.get(a.type) - rank.get(b.type)) || a.id.localeCompare(b.id));
  return { ordered, missing };
}

async function readAsset(assets, path) {
  const response = await assets.fetch(new Request(new URL(path, "https://panel.local/")));
  if (!response.ok) {
    throw new AssembleFailure("catalog_invalid", `${path} answered ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

export async function loadIndex(assets) {
  const bytes = await readAsset(assets, INDEX_PATH);
  let parsed;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new AssembleFailure("catalog_invalid", "catalog/index.json is not JSON");
  }
  return validateIndex(parsed);
}

export async function assembleOutfit({ assets, index, avatarId, items }) {
  const bodyPath = index.bodies[avatarId];
  if (!bodyPath) {
    throw new AssembleFailure("avatar_not_in_catalog", `no body for avatar ${avatarId}`);
  }

  const { ordered, missing } = resolveItems(index, items);
  const entries = [{ name: "body", bytes: await readAsset(assets, bodyPath) }];
  const mounted = [];
  let hidden = false;

  for (const piece of ordered) {
    try {
      entries.push({ name: `${piece.type}_${piece.id}`, bytes: await readAsset(assets, piece.mesh) });
      mounted.push(piece.id);
      if (piece.hides?.length) hidden = true;
    } catch (error) {
      throw new AssembleFailure("catalog_invalid", `${piece.id}: ${error.message}`);
    }
  }

  // A piece may declare body nodes to drop (app/assemble.py does the same
  // before export). The catalog ships none today, so refuse loudly instead of
  // exporting a body with clothing underneath.
  if (hidden) {
    throw new AssembleFailure("catalog_invalid", "this catalog uses hides, unsupported in the panel");
  }

  const bytes = entries.length === 1 ? entries[0].bytes : mergeGlbs(entries);
  return {
    bytes,
    mounted,
    missing,
    state: missing.length ? "partial" : "ready",
    detail: missing.length ? `missing from catalog: ${missing.join(", ")}` : "",
  };
}
