/**
 * GLB validation: magic, version, size, parseable JSON chunk.
 * Content-based — not extension trust.
 */

export const GLB_MAGIC = 0x46546c67; // 'glTF'
export const GLB_VERSION = 2;

/**
 * @param {Buffer} buf
 * @param {{ maxBytes?: number }} [opts]
 * @returns {{ ok: true, json: object, binByteLength: number, jsonByteLength: number } | { ok: false, error: string, code: string }}
 */
export function validateGlb(buf, opts = {}) {
  const maxBytes = opts.maxBytes ?? 80 * 1024 * 1024;
  if (!Buffer.isBuffer(buf) || buf.length === 0) {
    return { ok: false, error: "Empty upload — choose a .glb file.", code: "EMPTY" };
  }
  if (buf.length < 20) {
    return { ok: false, error: "File too small to be a GLB.", code: "TOO_SMALL" };
  }
  if (buf.length > maxBytes) {
    return {
      ok: false,
      error: `File is ${(buf.length / 1024 / 1024).toFixed(1)} MB; max is ${(maxBytes / 1024 / 1024).toFixed(0)} MB.`,
      code: "TOO_LARGE",
    };
  }
  const magic = buf.readUInt32LE(0);
  if (magic !== GLB_MAGIC) {
    return {
      ok: false,
      error: "Not a GLB file (missing glTF magic). Export as Binary glTF (.glb).",
      code: "BAD_MAGIC",
    };
  }
  const version = buf.readUInt32LE(4);
  if (version !== GLB_VERSION) {
    return {
      ok: false,
      error: `Unsupported glTF version ${version} (need 2).`,
      code: "BAD_VERSION",
    };
  }
  const length = buf.readUInt32LE(8);
  if (length !== buf.length) {
    return {
      ok: false,
      error: `GLB length header (${length}) does not match file size (${buf.length}).`,
      code: "BAD_LENGTH",
    };
  }
  const jsonChunkLength = buf.readUInt32LE(12);
  const jsonChunkType = buf.readUInt32LE(16);
  if (jsonChunkType !== 0x4e4f534a) {
    return { ok: false, error: "GLB JSON chunk missing or corrupt.", code: "BAD_JSON_CHUNK" };
  }
  if (20 + jsonChunkLength > buf.length) {
    return { ok: false, error: "GLB JSON chunk extends past end of file.", code: "TRUNCATED" };
  }
  let json;
  try {
    const jsonText = buf.subarray(20, 20 + jsonChunkLength).toString("utf8").replace(/\0+$/, "");
    json = JSON.parse(jsonText);
  } catch {
    return { ok: false, error: "GLB JSON chunk is not valid JSON.", code: "JSON_PARSE" };
  }
  if (!json.asset || !json.asset.version) {
    return { ok: false, error: "GLB missing asset.version.", code: "NO_ASSET" };
  }
  let binByteLength = 0;
  const afterJson = 20 + jsonChunkLength;
  if (afterJson + 8 <= buf.length) {
    binByteLength = buf.readUInt32LE(afterJson);
    const binType = buf.readUInt32LE(afterJson + 4);
    if (binType !== 0x004e4942) {
      return { ok: false, error: "GLB BIN chunk type unexpected.", code: "BAD_BIN_CHUNK" };
    }
  }
  if (!Array.isArray(json.meshes) || json.meshes.length === 0) {
    return { ok: false, error: "GLB has no meshes.", code: "NO_MESHES" };
  }
  return {
    ok: true,
    json,
    binByteLength,
    jsonByteLength: jsonChunkLength,
  };
}

export function looksLikeGlb(buf) {
  return Buffer.isBuffer(buf) && buf.length >= 8 && buf.readUInt32LE(0) === GLB_MAGIC;
}
