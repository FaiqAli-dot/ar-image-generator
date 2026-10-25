/**
 * Server-side GLB optimization via gltf-transform (open source).
 * Produces HQ preview + mobile variants. Original buffer is never overwritten.
 * Meshopt compression is applied — model-viewer ships meshopt decoder.
 */

import { NodeIO } from "@gltf-transform/core";
import { ALL_EXTENSIONS } from "@gltf-transform/extensions";
import {
  cloneDocument,
  dedup,
  prune,
  resample,
  textureCompress,
  simplify,
  weld,
} from "@gltf-transform/functions";
import { MeshoptEncoder, MeshoptSimplifier, MeshoptDecoder } from "meshoptimizer";
import { applyMeshExclusions } from "./cleanup.js";

await MeshoptEncoder.ready;
await MeshoptDecoder.ready;
await MeshoptSimplifier.ready;

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
  "meshopt.encoder": MeshoptEncoder,
  "meshopt.decoder": MeshoptDecoder,
  "meshopt.simplifier": MeshoptSimplifier,
});

/**
 * @param {Buffer} originalBuf
 * @param {{
 *   acceptedSuggestionIds?: string[],
 *   suggestions?: object[],
 *   simplifyRatio?: number,
 *   maxTextureHq?: number,
 *   maxTextureMobile?: number,
 * }} [opts]
 */
export async function optimizeGlb(originalBuf, opts = {}) {
  const started = Date.now();
  const acceptedSuggestionIds = opts.acceptedSuggestionIds || [];
  const suggestions = opts.suggestions || [];
  const simplifyRatio =
    opts.simplifyRatio ??
    (suggestions.find((s) => s.id === "decimate-hq")?.recommendedRatio || 0.4);
  const doSimplify =
    acceptedSuggestionIds.includes("decimate-hq") || opts.forceSimplify === true;
  const doTexture =
    acceptedSuggestionIds.includes("texture-resize") || opts.forceTextureResize !== false;

  const maxTextureHq = opts.maxTextureHq ?? 2048;
  const maxTextureMobile = opts.maxTextureMobile ?? 1024;

  const document = await io.readBinary(new Uint8Array(originalBuf));
  const exclusion = await applyMeshExclusions(document, acceptedSuggestionIds, suggestions);

  await document.transform(dedup(), weld(), prune());

  if (doSimplify) {
    try {
      await document.transform(
        simplify({
          simplifier: MeshoptSimplifier,
          ratio: simplifyRatio,
          error: 0.001,
        })
      );
    } catch (e) {
      // Soft-fail simplify — still emit texture-optimized assets
      exclusion.simplifyError = e.message || String(e);
    }
  }

  // HQ variant
  const hqDoc = cloneDocument(document);
  if (doTexture) {
    try {
      await hqDoc.transform(
        textureCompress({
          targetFormat: "png",
          resize: [maxTextureHq, maxTextureHq],
        })
      );
    } catch {
      /* keep textures */
    }
  }
  await hqDoc.transform(resample(), prune());
  const hqBytes = Buffer.from(await io.writeBinary(hqDoc));

  // Mobile variant — stronger texture cap + quantize (model-viewer friendly)
  const mobileDoc = cloneDocument(document);
  if (doTexture) {
    try {
      await mobileDoc.transform(
        textureCompress({
          targetFormat: "png",
          resize: [maxTextureMobile, maxTextureMobile],
        })
      );
    } catch {
      /* keep */
    }
  }
  try {
    const { quantize } = await import("@gltf-transform/functions");
    await mobileDoc.transform(quantize(), prune());
  } catch {
    await mobileDoc.transform(prune());
  }

  let mobileBytes;
  try {
    const { MeshoptCompression } = await import("@gltf-transform/extensions");
    mobileDoc.createExtension(MeshoptCompression).setRequired(false);
    mobileBytes = Buffer.from(await io.writeBinary(mobileDoc));
  } catch {
    mobileBytes = Buffer.from(await io.writeBinary(mobileDoc));
  }

  const stats = {
    originalBytes: originalBuf.length,
    hqBytes: hqBytes.length,
    mobileBytes: mobileBytes.length,
    removedMeshes: exclusion.removed || [],
    simplifyApplied: doSimplify && !exclusion.simplifyError,
    simplifyRatio: doSimplify ? simplifyRatio : null,
    simplifyError: exclusion.simplifyError || null,
    textureResize: doTexture,
    maxTextureHq,
    maxTextureMobile,
    durationMs: Date.now() - started,
    compression: "meshopt_when_available",
    viewerSupport: "model-viewer includes meshopt decoder",
  };

  return { hq: hqBytes, mobile: mobileBytes, stats };
}

export { io as gltfIo };
