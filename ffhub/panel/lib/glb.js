// A GLB merger, no engine attached.
//
// Every catalog entry is already in world space and carries its own material
// and embedded texture, so dressing a character is concatenating their binary
// chunks and remapping the indices between them: bufferViews shift by the
// running binary length, accessors and images point at the new bufferViews,
// textures at the new images/samplers, and primitives at the new accessors.
//
// Only what the catalog format produces is supported on purpose: one buffer per
// file, images stored in the buffer (never external URIs), no skins or
// animations. Anything else raises instead of exporting a quietly wrong file.

const MAGIC = 0x46546c67;
const JSON_CHUNK = 0x4e4f534a;
const BIN_CHUNK = 0x004e4942;

const TEXTURE_KEYS = new Set([
  "baseColorTexture",
  "metallicRoughnessTexture",
  "normalTexture",
  "occlusionTexture",
  "emissiveTexture",
  "clearcoatTexture",
  "clearcoatRoughnessTexture",
  "clearcoatNormalTexture",
  "sheenColorTexture",
  "sheenRoughnessTexture",
  "specularTexture",
  "specularColorTexture",
  "transmissionTexture",
  "thicknessTexture",
  "iridescenceTexture",
  "iridescenceThicknessTexture",
  "anisotropyTexture",
  "diffuseTexture",
]);

export function parseGlb(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0, true) !== MAGIC) throw new Error("not a GLB");
  if (view.getUint32(4, true) !== 2) throw new Error("only glTF 2.0 GLBs are supported");
  const total = view.getUint32(8, true);
  let offset = 12;
  let json = null;
  let bin = new Uint8Array(0);
  while (offset + 8 <= total) {
    const length = view.getUint32(offset, true);
    const type = view.getUint32(offset + 4, true);
    const start = offset + 8;
    if (type === JSON_CHUNK) {
      json = JSON.parse(new TextDecoder().decode(bytes.subarray(start, start + length)));
    } else if (type === BIN_CHUNK) {
      bin = bytes.subarray(start, start + length);
    }
    offset = start + length;
  }
  if (!json) throw new Error("GLB without a JSON chunk");
  const declared = json.buffers?.[0]?.byteLength;
  if (typeof declared === "number" && declared <= bin.length) {
    bin = bin.subarray(0, declared);
  }
  return { json, bin };
}

export function buildGlb(json, bin) {
  const jsonBytes = new TextEncoder().encode(JSON.stringify(json));
  const jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  const binPad = (4 - (bin.length % 4)) % 4;
  const jsonLength = jsonBytes.length + jsonPad;
  const binLength = bin.length + binPad;
  const total = 12 + 8 + jsonLength + 8 + binLength;

  const out = new Uint8Array(total);
  const view = new DataView(out.buffer);
  view.setUint32(0, MAGIC, true);
  view.setUint32(4, 2, true);
  view.setUint32(8, total, true);

  view.setUint32(12, jsonLength, true);
  view.setUint32(16, JSON_CHUNK, true);
  out.set(jsonBytes, 20);
  out.fill(0x20, 20 + jsonBytes.length, 20 + jsonLength);

  const binHeader = 20 + jsonLength;
  view.setUint32(binHeader, binLength, true);
  view.setUint32(binHeader + 4, BIN_CHUNK, true);
  out.set(bin, binHeader + 8);
  return out;
}

function remapMaterial(material, textures) {
  const walk = (value) => {
    if (Array.isArray(value)) return value.map(walk);
    if (!value || typeof value !== "object") return value;
    const copy = {};
    for (const [key, child] of Object.entries(value)) {
      if (
        TEXTURE_KEYS.has(key) &&
        child &&
        typeof child === "object" &&
        typeof child.index === "number"
      ) {
        copy[key] = { ...child, index: textures[child.index] };
      } else {
        copy[key] = walk(child);
      }
    }
    return copy;
  };
  return walk(material);
}

/**
 * Merge GLBs in order. `entries` is [{ name, bytes }]; the name becomes the
 * node name so the exported file stays readable in a viewer.
 */
export function mergeGlbs(entries) {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error("nothing to merge");
  }

  const doc = {
    asset: { version: "2.0", generator: "ffhub-panel" },
    scene: 0,
    scenes: [{ nodes: [] }],
    nodes: [],
    meshes: [],
    materials: [],
    textures: [],
    images: [],
    samplers: [],
    accessors: [],
    bufferViews: [],
    buffers: [{ byteLength: 0 }],
  };

  const parts = [];
  let binLength = 0;
  const appendBin = (data) => {
    const pad = (4 - (binLength % 4)) % 4;
    if (pad) {
      parts.push(new Uint8Array(pad));
      binLength += pad;
    }
    const start = binLength;
    parts.push(data);
    binLength += data.length;
    return start;
  };

  for (const entry of entries) {
    const { json, bin } = parseGlb(entry.bytes);
    if (!json.buffers || json.buffers.length !== 1) {
      throw new Error(`${entry.name}: expected exactly one buffer`);
    }
    if (json.buffers[0].uri) {
      throw new Error(`${entry.name}: external buffers are not supported`);
    }
    const base = appendBin(bin);

    const bufferViews = (json.bufferViews ?? []).map((item) => {
      doc.bufferViews.push({
        ...item,
        buffer: 0,
        byteOffset: (item.byteOffset ?? 0) + base,
      });
      return doc.bufferViews.length - 1;
    });

    const accessors = (json.accessors ?? []).map((item) => {
      const copy = { ...item };
      if (copy.bufferView !== undefined) copy.bufferView = bufferViews[copy.bufferView];
      doc.accessors.push(copy);
      return doc.accessors.length - 1;
    });

    const samplers = (json.samplers ?? []).map((item) => {
      doc.samplers.push({ ...item });
      return doc.samplers.length - 1;
    });

    const images = (json.images ?? []).map((item) => {
      if (item.bufferView === undefined) {
        throw new Error(`${entry.name}: image without a bufferView is not supported`);
      }
      doc.images.push({ ...item, bufferView: bufferViews[item.bufferView] });
      return doc.images.length - 1;
    });

    const textures = (json.textures ?? []).map((item) => {
      const copy = {};
      if (item.sampler !== undefined) copy.sampler = samplers[item.sampler];
      if (item.source !== undefined) copy.source = images[item.source];
      doc.textures.push(copy);
      return doc.textures.length - 1;
    });

    const materials = (json.materials ?? []).map((item) => {
      doc.materials.push(remapMaterial(item, textures));
      return doc.materials.length - 1;
    });

    const meshes = (json.meshes ?? []).map((mesh) => {
      const primitives = mesh.primitives.map((primitive) => {
        const attributes = {};
        for (const [key, index] of Object.entries(primitive.attributes ?? {})) {
          attributes[key] = accessors[index];
        }
        const copy = { ...primitive, attributes };
        if (primitive.indices !== undefined) copy.indices = accessors[primitive.indices];
        if (primitive.material !== undefined) copy.material = materials[primitive.material];
        return copy;
      });
      doc.meshes.push({ ...mesh, primitives });
      return doc.meshes.length - 1;
    });

    for (const node of json.nodes ?? []) {
      if (node.mesh === undefined) continue;
      const copy = { mesh: meshes[node.mesh], name: entry.name };
      for (const key of ["matrix", "translation", "rotation", "scale"]) {
        if (node[key] !== undefined) copy[key] = node[key];
      }
      doc.nodes.push(copy);
      doc.scenes[0].nodes.push(doc.nodes.length - 1);
    }
  }

  if (doc.meshes.length === 0) throw new Error("merge produced no meshes");
  doc.buffers[0].byteLength = binLength;

  const bin = new Uint8Array(binLength);
  let at = 0;
  for (const part of parts) {
    bin.set(part, at);
    at += part.length;
  }
  return buildGlb(doc, bin);
}
