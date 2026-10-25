/**
 * Dual-output GLB import pipeline.
 * Pipeline A: preserve original + optimized HQ/mobile GLBs.
 * Pipeline B: 16-view + 72-view synthetic sets (cached by source hash + config).
 */

import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { config } from "../config.js";
import { validateGlb } from "./validate.js";
import { inspectGlb } from "./inspect.js";
import { suggestCleanup } from "./cleanup.js";
import { optimizeGlb } from "./optimize.js";
import {
  renderViewSet,
  renderConfigHash,
  sourceHash,
  VIEW_PRESETS,
} from "./renderViews.js";

export function draftsDir() {
  return path.join(config.dataDir, "glb-drafts");
}

export function cacheDir() {
  return path.join(config.dataDir, "glb-cache");
}

export async function ensureGlbDirs() {
  await fs.mkdir(draftsDir(), { recursive: true });
  await fs.mkdir(cacheDir(), { recursive: true });
  await fs.mkdir(path.join(config.dataDir, "glb-temp"), { recursive: true });
}

/**
 * Stage 1: validate, inspect, suggest cleanup. Keep original recoverable.
 */
export async function createImportDraft(buf, meta = {}) {
  await ensureGlbDirs();
  const validation = validateGlb(buf, { maxBytes: config.maxGlbBytes });
  if (!validation.ok) {
    const err = new Error(validation.error);
    err.status = 400;
    err.code = validation.code;
    throw err;
  }

  const inspection = inspectGlb(buf);
  const { suggestions, autoSafe } = suggestCleanup(inspection);
  const hash = sourceHash(buf);
  const draftId = randomUUID().replace(/-/g, "");
  const dir = path.join(draftsDir(), draftId);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, "original.glb"), buf);

  const draft = {
    draftId,
    status: "preview",
    createdAt: new Date().toISOString(),
    name: meta.name || "Imported dish",
    widthCm: meta.widthCm != null ? Number(meta.widthCm) : 12,
    description: meta.description || "",
    sourceHash: hash,
    originalBytes: buf.length,
    inspection,
    suggestions,
    autoSafe,
    acceptedSuggestionIds: [],
    model3d: null,
    renderSets: null,
    error: null,
  };
  await fs.writeFile(path.join(dir, "draft.json"), JSON.stringify(draft, null, 2));
  return draft;
}

export async function readDraft(draftId) {
  try {
    const raw = await fs.readFile(path.join(draftsDir(), draftId, "draft.json"), "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function writeDraft(draft) {
  const dir = path.join(draftsDir(), draft.draftId);
  await fs.writeFile(path.join(dir, "draft.json"), JSON.stringify(draft, null, 2));
}

/**
 * Stage 2: optimize + dual render (or reuse cache). Does not publish.
 */
export async function processDraft(draftId, { acceptedSuggestionIds = [], skipRenders = false } = {}) {
  const draft = await readDraft(draftId);
  if (!draft) {
    const err = new Error("Draft not found");
    err.status = 404;
    throw err;
  }
  draft.status = "processing";
  draft.acceptedSuggestionIds = acceptedSuggestionIds;
  draft.error = null;
  await writeDraft(draft);

  const dir = path.join(draftsDir(), draftId);
  const originalBuf = await fs.readFile(path.join(dir, "original.glb"));
  const res = Number(process.env.RENDER_RES || config.renderRes || 512);

  try {
    const { hq, mobile, stats } = await optimizeGlb(originalBuf, {
      acceptedSuggestionIds,
      suggestions: draft.suggestions,
    });
    await fs.writeFile(path.join(dir, "optimized.glb"), hq);
    await fs.writeFile(path.join(dir, "optimized-mobile.glb"), mobile);

    draft.model3d = {
      status: "ready",
      originalGlb: "original.glb",
      optimizedGlb: "optimized.glb",
      mobileGlb: "optimized-mobile.glb",
      sourceHash: draft.sourceHash,
      optimizations: stats,
      sizes: {
        originalBytes: originalBuf.length,
        optimizedBytes: hq.length,
        mobileBytes: mobile.length,
      },
    };

    if (!skipRenders) {
      draft.renderSets = await buildRenderSets(originalBuf, draft.sourceHash, dir, res);
    }

    draft.status = "processed";
    draft.processedAt = new Date().toISOString();
    await writeDraft(draft);
    return draft;
  } catch (e) {
    draft.status = "failed";
    draft.error = e.message || String(e);
    await writeDraft(draft);
    throw e;
  }
}

async function buildRenderSets(originalBuf, hash, draftDir, res) {
  const sets = {};
  for (const preset of [VIEW_PRESETS.views16, VIEW_PRESETS.views72]) {
    const cfgHash = renderConfigHash({
      azStep: preset.azStep,
      res,
      engine: process.env.BLENDER ? "blender" : "three",
    });
    const cacheKey = `${hash}_${preset.key}_${cfgHash}`;
    const cachePath = path.join(cacheDir(), cacheKey);
    const outLocal = path.join(draftDir, `renders_${preset.key}`);

    if (existsSync(path.join(cachePath, "manifest.json"))) {
      await fs.cp(cachePath, outLocal, { recursive: true });
      const manifest = JSON.parse(await fs.readFile(path.join(outLocal, "manifest.json"), "utf8"));
      sets[preset.key] = {
        status: "ready",
        cached: true,
        cacheKey,
        path: `renders_${preset.key}`,
        azStep: preset.azStep,
        resolution: res,
        viewCount: manifest.viewCount || manifest.views?.length,
        configHash: cfgHash,
        engine: manifest.engine,
        footprintBytes: await dirSize(outLocal),
      };
      continue;
    }

    // Render into temp then promote to cache (retry-safe: don't corrupt cache mid-write)
    const temp = path.join(config.dataDir, "glb-temp", cacheKey);
    await fs.rm(temp, { recursive: true, force: true });
    await fs.mkdir(temp, { recursive: true });
    const rendered = await renderViewSet(originalBuf, temp, { azStep: preset.azStep, res });
    await fs.mkdir(cachePath, { recursive: true });
    await fs.cp(temp, cachePath, { recursive: true });
    await fs.cp(temp, outLocal, { recursive: true });
    await fs.rm(temp, { recursive: true, force: true });

    sets[preset.key] = {
      status: "ready",
      cached: false,
      cacheKey,
      path: `renders_${preset.key}`,
      azStep: preset.azStep,
      resolution: res,
      viewCount: rendered.views.length,
      configHash: cfgHash,
      engine: rendered.engine,
      footprintBytes: await dirSize(outLocal),
    };
  }
  return sets;
}

async function dirSize(dir) {
  let total = 0;
  async function walk(d) {
    const entries = await fs.readdir(d, { withFileTypes: true });
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) await walk(p);
      else {
        const st = await fs.stat(p);
        total += st.size;
      }
    }
  }
  try {
    await walk(dir);
  } catch {
    return 0;
  }
  return total;
}

/**
 * Publish draft → permanent object. Image views come from chosen default render set
 * when publishedDefault is views16/views72; direct3d keeps empty views or optional 16 for fallback.
 */
export async function publishDraft(draftId, opts = {}) {
  const draft = await readDraft(draftId);
  if (!draft || draft.status !== "processed" || !draft.model3d) {
    const err = new Error("Draft must be processed successfully before publish");
    err.status = 400;
    throw err;
  }

  const publishedDefault = opts.publishedDefault || "direct3d";
  const { buildObjectRecord, writeObjectMeta, newObjectId, imagePath, thumbnailPath, objectExists } =
    await import("../storage.js");

  const id = newObjectId();
  if (await objectExists(id)) {
    const err = new Error("ID collision — retry");
    err.status = 409;
    throw err;
  }

  const draftDir = path.join(draftsDir(), draftId);
  const objectDir = path.join(config.objectsDir, id);
  await fs.mkdir(path.join(objectDir, "images"), { recursive: true });
  await fs.mkdir(path.join(objectDir, "thumbnail"), { recursive: true });
  await fs.mkdir(path.join(objectDir, "models"), { recursive: true });
  await fs.mkdir(path.join(objectDir, "renders"), { recursive: true });

  // Copy models (original once; no needless duplication beyond object store)
  await fs.copyFile(path.join(draftDir, "original.glb"), path.join(objectDir, "models", "original.glb"));
  await fs.copyFile(path.join(draftDir, "optimized.glb"), path.join(objectDir, "models", "optimized.glb"));
  await fs.copyFile(
    path.join(draftDir, "optimized-mobile.glb"),
    path.join(objectDir, "models", "optimized-mobile.glb")
  );

  // Copy both render sets
  for (const key of ["16", "72"]) {
    const src = path.join(draftDir, `renders_${key}`);
    if (existsSync(src)) {
      await fs.cp(src, path.join(objectDir, "renders", `views_${key}`), { recursive: true });
    }
  }

  // Choose views for photographic compatibility
  let views = [];
  const viewSourceKey = publishedDefault === "views72" ? "72" : publishedDefault === "views16" ? "16" : "16";
  const renderManifestPath = path.join(objectDir, "renders", `views_${viewSourceKey}`, "manifest.json");
  if (existsSync(renderManifestPath)) {
    const man = JSON.parse(await fs.readFile(renderManifestPath, "utf8"));
    views = (man.views || []).map((v) => ({
      id: v.id,
      azimuth: v.azimuth,
      elevation: v.elevation,
      image: v.image,
      distance: v.distance ?? 0.45,
      source: v.source,
      status: v.status,
    }));
    // Copy selected set into images/ for existing image URL pattern
    for (const v of views) {
      const src = path.join(objectDir, "renders", `views_${viewSourceKey}`, v.image);
      if (existsSync(src)) {
        await fs.copyFile(src, imagePath(id, v.image));
      }
    }
    // Thumbnail from first view
    if (views[0]) {
      const tsrc = path.join(objectDir, "renders", `views_${viewSourceKey}`, views[0].image);
      if (existsSync(tsrc)) await fs.copyFile(tsrc, thumbnailPath(id));
    }
  }

  const record = buildObjectRecord({
    id,
    name: opts.name || draft.name,
    widthCm: opts.widthCm ?? draft.widthCm,
    description: opts.description ?? draft.description,
    views,
    isDemo: false,
  });

  record.kind = "hybridARObject";
  record.schemaVersion = 2;
  record.publishedDefault = publishedDefault;
  record.model3d = {
    ...draft.model3d,
    originalGlb: "models/original.glb",
    optimizedGlb: "models/optimized.glb",
    mobileGlb: "models/optimized-mobile.glb",
    usdz: null,
    usdzNote:
      "No server-side USDZ on Linux. iOS Quick Look uses model-viewer client-side generation when available; not verified on a physical iPhone in this environment.",
  };
  record.renderSets = {
    "16": summarizePublishedSet(draft.renderSets?.["16"], "renders/views_16"),
    "72": summarizePublishedSet(draft.renderSets?.["72"], "renders/views_72"),
  };
  record.storageFootprint = {
    originalGlbBytes: draft.model3d.sizes.originalBytes,
    optimizedGlbBytes: draft.model3d.sizes.optimizedBytes,
    mobileGlbBytes: draft.model3d.sizes.mobileBytes,
    views16Bytes: draft.renderSets?.["16"]?.footprintBytes ?? null,
    views72Bytes: draft.renderSets?.["72"]?.footprintBytes ?? null,
  };
  record.sourceDraftId = draftId;

  await writeObjectMeta(id, record);

  draft.status = "published";
  draft.publishedObjectId = id;
  await writeDraft(draft);

  return record;
}

function summarizePublishedSet(set, relPath) {
  if (!set) return null;
  return {
    status: set.status,
    path: relPath,
    azStep: set.azStep,
    resolution: set.resolution,
    viewCount: set.viewCount,
    configHash: set.configHash,
    engine: set.engine,
    footprintBytes: set.footprintBytes,
    cachedAtImport: set.cached,
  };
}

export async function discardDraft(draftId) {
  const dir = path.join(draftsDir(), draftId);
  await fs.rm(dir, { recursive: true, force: true });
}

export async function cleanupAbandonedDrafts({ maxAgeMs = 24 * 60 * 60 * 1000 } = {}) {
  await ensureGlbDirs();
  const entries = await fs.readdir(draftsDir(), { withFileTypes: true });
  const now = Date.now();
  let removed = 0;
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const draft = await readDraft(e.name);
    if (!draft) continue;
    if (draft.status === "published") continue;
    const created = Date.parse(draft.createdAt || 0);
    if (now - created > maxAgeMs) {
      await discardDraft(e.name);
      removed++;
    }
  }
  return { removed };
}
