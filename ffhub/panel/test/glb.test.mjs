import assert from "node:assert/strict";
import { test } from "node:test";

import { buildGlb, mergeGlbs, parseGlb } from "../lib/glb.js";

const PNG = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);

function texturedPiece(name = "piece") {
  const doc = {
    asset: { version: "2.0" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0, name }],
    meshes: [{ name: "m", primitives: [{ attributes: {}, material: 0 }] }],
    materials: [{ name: "mat", pbrMetallicRoughness: { baseColorTexture: { index: 0 } } }],
    textures: [{ sampler: 0, source: 0 }],
    samplers: [{}],
    images: [{ bufferView: 0, mimeType: "image/png" }],
    bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: PNG.length }],
    buffers: [{ byteLength: PNG.length }],
  };
  return buildGlb(doc, PNG);
}

test("a GLB round-trips through parse and build", () => {
  const parsed = parseGlb(texturedPiece());

  assert.equal(parsed.json.meshes.length, 1);
  assert.equal(parsed.bin.length, PNG.length);
  assert.deepEqual([...parsed.bin], [...PNG]);
});

test("merging two pieces keeps one texture each and shifts the buffer", () => {
  const merged = parseGlb(
    mergeGlbs([
      { name: "feet_1", bytes: texturedPiece() },
      { name: "hair_2", bytes: texturedPiece() },
    ]),
  );

  assert.equal(merged.json.meshes.length, 2);
  assert.equal(merged.json.materials.length, 2);
  assert.equal(merged.json.images.length, 2);
  assert.deepEqual(merged.json.bufferViews.map((view) => view.byteOffset), [0, 8]);
  assert.deepEqual(merged.json.textures.map((texture) => texture.source), [0, 1]);
  assert.deepEqual(
    merged.json.materials.map((material) => material.pbrMetallicRoughness.baseColorTexture.index),
    [0, 1],
  );
  assert.equal(merged.json.buffers[0].byteLength, 16);
  assert.deepEqual(merged.json.nodes.map((node) => node.name), ["feet_1", "hair_2"]);
  assert.equal(merged.bin.length, 16);
});

test("a node transform survives the merge", () => {
  const doc = {
    asset: { version: "2.0" },
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0, translation: [0, 2, 0] }],
    meshes: [{ primitives: [{ attributes: {} }] }],
    buffers: [{ byteLength: 0 }],
  };

  const merged = parseGlb(
    mergeGlbs([{ name: "hat", bytes: buildGlb(doc, new Uint8Array(0)) }]),
  );

  assert.deepEqual(merged.json.nodes[0].translation, [0, 2, 0]);
  assert.equal(merged.json.nodes[0].mesh, 0);
});

test("an external buffer is refused instead of half-merged", () => {
  const doc = {
    asset: { version: "2.0" },
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0 }],
    meshes: [{ primitives: [{ attributes: {} }] }],
    buffers: [{ byteLength: 8, uri: "mesh.bin" }],
  };

  assert.throws(
    () => mergeGlbs([{ name: "bad", bytes: buildGlb(doc, PNG) }]),
    /external buffers are not supported/,
  );
});

test("an image stored outside the buffer is refused", () => {
  const doc = {
    asset: { version: "2.0" },
    scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0 }],
    meshes: [{ primitives: [{ attributes: {} }] }],
    images: [{ uri: "texture.png" }],
    textures: [{ source: 0 }],
    materials: [{ pbrMetallicRoughness: { baseColorTexture: { index: 0 } } }],
    buffers: [{ byteLength: 0 }],
  };

  assert.throws(
    () => mergeGlbs([{ name: "bad", bytes: buildGlb(doc, new Uint8Array(0)) }]),
    /image without a bufferView/,
  );
});
