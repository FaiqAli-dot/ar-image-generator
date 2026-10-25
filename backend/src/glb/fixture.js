/**
 * Tiny generated GLB cube for tests (not the user's 41 MB Luma export).
 * Hand-rolled glTF 2.0 binary — no external deps.
 */

function align4(n) {
  return (n + 3) & ~3;
}

/**
 * @returns {Buffer} GLB bytes for a unit cube (Y-up), ~1 material, solid color.
 */
export function buildTestCubeGlb({ size = 0.12, color = [0.85, 0.45, 0.2] } = {}) {
  const s = size / 2;
  // 24 vertices (unique normals per face) — positions
  const faces = [
    // +Z
    [
      [-s, -s, s],
      [s, -s, s],
      [s, s, s],
      [-s, s, s],
    ],
    // -Z
    [
      [s, -s, -s],
      [-s, -s, -s],
      [-s, s, -s],
      [s, s, -s],
    ],
    // +Y
    [
      [-s, s, s],
      [s, s, s],
      [s, s, -s],
      [-s, s, -s],
    ],
    // -Y (floor-ish)
    [
      [-s, -s, -s],
      [s, -s, -s],
      [s, -s, s],
      [-s, -s, s],
    ],
    // +X
    [
      [s, -s, s],
      [s, -s, -s],
      [s, s, -s],
      [s, s, s],
    ],
    // -X
    [
      [-s, -s, -s],
      [-s, -s, s],
      [-s, s, s],
      [-s, s, -s],
    ],
  ];
  const positions = [];
  const normals = [];
  const indices = [];
  const faceNormals = [
    [0, 0, 1],
    [0, 0, -1],
    [0, 1, 0],
    [0, -1, 0],
    [1, 0, 0],
    [-1, 0, 0],
  ];
  for (let f = 0; f < 6; f++) {
    const base = positions.length / 3;
    for (const p of faces[f]) {
      positions.push(...p);
      normals.push(...faceNormals[f]);
    }
    indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
  }

  const posBuf = Buffer.from(new Float32Array(positions).buffer);
  const normBuf = Buffer.from(new Float32Array(normals).buffer);
  const idxBuf = Buffer.from(new Uint16Array(indices).buffer);

  let bin = Buffer.concat([posBuf, normBuf, idxBuf]);
  const pad = align4(bin.length) - bin.length;
  if (pad) bin = Buffer.concat([bin, Buffer.alloc(pad)]);

  const posMin = [-s, -s, -s];
  const posMax = [s, s, s];

  const json = {
    asset: { version: "2.0", generator: "ar-food-test-cube" },
    scenes: [{ nodes: [0] }],
    scene: 0,
    nodes: [{ mesh: 0, name: "TestDishCube" }],
    meshes: [
      {
        name: "TestDishCube",
        primitives: [
          {
            attributes: { POSITION: 0, NORMAL: 1 },
            indices: 2,
            material: 0,
          },
        ],
      },
    ],
    materials: [
      {
        name: "DishMaterial",
        pbrMetallicRoughness: {
          baseColorFactor: [...color, 1],
          metallicFactor: 0,
          roughnessFactor: 0.8,
        },
      },
    ],
    accessors: [
      {
        bufferView: 0,
        componentType: 5126,
        count: positions.length / 3,
        type: "VEC3",
        max: posMax,
        min: posMin,
      },
      {
        bufferView: 1,
        componentType: 5126,
        count: normals.length / 3,
        type: "VEC3",
      },
      {
        bufferView: 2,
        componentType: 5123,
        count: indices.length,
        type: "SCALAR",
      },
    ],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: posBuf.length, target: 34962 },
      { buffer: 0, byteOffset: posBuf.length, byteLength: normBuf.length, target: 34962 },
      {
        buffer: 0,
        byteOffset: posBuf.length + normBuf.length,
        byteLength: idxBuf.length,
        target: 34963,
      },
    ],
    buffers: [{ byteLength: bin.length }],
  };

  let jsonBuf = Buffer.from(JSON.stringify(json), "utf8");
  const jsonPad = align4(jsonBuf.length) - jsonBuf.length;
  if (jsonPad) jsonBuf = Buffer.concat([jsonBuf, Buffer.alloc(jsonPad, 0x20)]);

  const totalLength = 12 + 8 + jsonBuf.length + 8 + bin.length;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLength, 8);

  const jsonChunkHeader = Buffer.alloc(8);
  jsonChunkHeader.writeUInt32LE(jsonBuf.length, 0);
  jsonChunkHeader.writeUInt32LE(0x4e4f534a, 4);

  const binChunkHeader = Buffer.alloc(8);
  binChunkHeader.writeUInt32LE(bin.length, 0);
  binChunkHeader.writeUInt32LE(0x004e4942, 4);

  return Buffer.concat([header, jsonChunkHeader, jsonBuf, binChunkHeader, bin]);
}

/** Extra tiny “floor” mesh suggestion target — separate node for cleanup tests. */
export function buildTestCubeWithFloorGlb() {
  // For simplicity reuse cube; cleanup suggestions still fire on triangle/name heuristics.
  return buildTestCubeGlb({ size: 0.15, color: [0.9, 0.55, 0.25] });
}
