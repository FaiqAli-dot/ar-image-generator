/**
 * Inspect GLB structure for owner preview + cleanup suggestions.
 * Uses parsed glTF JSON + optional binary bounds heuristics.
 */

import { validateGlb } from "./validate.js";

/**
 * @param {Buffer} buf
 * @returns {object}
 */
export function inspectGlb(buf) {
  const v = validateGlb(buf);
  if (!v.ok) {
    const err = new Error(v.error);
    err.status = 400;
    err.code = v.code;
    throw err;
  }
  const { json } = v;
  const meshes = json.meshes || [];
  const materials = json.materials || [];
  const textures = json.textures || [];
  const images = json.images || [];
  const nodes = json.nodes || [];
  const accessors = json.accessors || [];
  const extensionsUsed = json.extensionsUsed || [];
  const extensionsRequired = json.extensionsRequired || [];

  let primitiveCount = 0;
  let triangleEstimate = 0;
  const meshSummaries = [];

  for (let mi = 0; mi < meshes.length; mi++) {
    const mesh = meshes[mi];
    const prims = mesh.primitives || [];
    primitiveCount += prims.length;
    let meshTris = 0;
    for (const p of prims) {
      const tris = estimatePrimitiveTriangles(p, accessors);
      meshTris += tris;
      triangleEstimate += tris;
    }
    meshSummaries.push({
      index: mi,
      name: mesh.name || `mesh_${mi}`,
      primitives: prims.length,
      triangles: meshTris,
      materialIndices: prims.map((p) => (p.material == null ? null : p.material)),
    });
  }

  const imageSummaries = images.map((im, i) => ({
    index: i,
    mimeType: im.mimeType || (im.uri?.endsWith?.(".jpg") ? "image/jpeg" : "image/png"),
    name: im.name || `image_${i}`,
    bufferView: im.bufferView,
    uri: im.uri ? "(external/data-uri)" : undefined,
  }));

  const bbox = computeSceneBBox(json);
  const upAxis = json.asset?.generator?.toLowerCase?.().includes("gltfpack")
    ? "Y-up (gltfpack-written typical)"
    : "Y-up (glTF convention)";

  return {
    byteLength: buf.length,
    generator: json.asset?.generator || null,
    copyright: json.asset?.copyright || null,
    version: json.asset?.version,
    meshCount: meshes.length,
    primitiveCount,
    materialCount: materials.length,
    textureCount: textures.length,
    imageCount: images.length,
    nodeCount: nodes.length,
    triangleEstimate,
    extensionsUsed,
    extensionsRequired,
    hasDraco: extensionsUsed.includes("KHR_draco_mesh_compression"),
    hasMeshopt: extensionsUsed.includes("EXT_meshopt_compression"),
    hasKtx2: extensionsUsed.includes("KHR_texture_basisu"),
    meshes: meshSummaries,
    images: imageSummaries,
    materials: materials.map((m, i) => ({
      index: i,
      name: m.name || `material_${i}`,
      alphaMode: m.alphaMode || "OPAQUE",
      doubleSided: Boolean(m.doubleSided),
    })),
    bbox,
    upAxis,
    scaleHintMeters: bbox ? approxSizeMeters(bbox) : null,
  };
}

function estimatePrimitiveTriangles(prim, accessors) {
  if (prim.indices != null && accessors[prim.indices]) {
    const count = accessors[prim.indices].count || 0;
    const mode = prim.mode == null ? 4 : prim.mode;
    if (mode === 4) return Math.floor(count / 3);
    if (mode === 5 || mode === 6) return Math.max(0, count - 2);
    return Math.floor(count / 3);
  }
  const pos = prim.attributes?.POSITION;
  if (pos != null && accessors[pos]) {
    const count = accessors[pos].count || 0;
    return Math.floor(count / 3);
  }
  return 0;
}

function computeSceneBBox(json) {
  const accessors = json.accessors || [];
  let min = [Infinity, Infinity, Infinity];
  let max = [-Infinity, -Infinity, -Infinity];
  let found = false;
  for (const mesh of json.meshes || []) {
    for (const p of mesh.primitives || []) {
      const pos = p.attributes?.POSITION;
      if (pos == null || !accessors[pos]) continue;
      const a = accessors[pos];
      if (a.min && a.max && a.min.length >= 3 && a.max.length >= 3) {
        found = true;
        for (let i = 0; i < 3; i++) {
          min[i] = Math.min(min[i], a.min[i]);
          max[i] = Math.max(max[i], a.max[i]);
        }
      }
    }
  }
  if (!found) return null;
  return { min, max, size: [max[0] - min[0], max[1] - min[1], max[2] - min[2]] };
}

function approxSizeMeters(bbox) {
  const [sx, sy, sz] = bbox.size;
  const longest = Math.max(sx, sy, sz);
  return {
    longestAxis: longest,
    likelyMeters: longest > 0.01 && longest < 5,
    note:
      longest > 50
        ? "Very large units — may be centimeters or scene units; check scale before publish."
        : longest < 0.02
          ? "Very small bounds — may need scale-up for AR."
          : "Bounds look plausible for a dish-scale object (meters).",
  };
}
