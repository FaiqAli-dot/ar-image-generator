import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";

const ID_RE = /^[a-zA-Z0-9_-]{8,64}$/;
const IMAGE_NAME_RE = /^[a-zA-Z0-9._-]{1,128}\.png$/i;

export function isValidObjectId(id) {
  return typeof id === "string" && ID_RE.test(id);
}

export function sanitizeImageFilename(name) {
  if (typeof name !== "string") return null;
  const base = path.basename(name);
  if (!IMAGE_NAME_RE.test(base)) return null;
  return base;
}

export function newObjectId() {
  return randomUUID().replace(/-/g, "");
}

export async function ensureStorage() {
  await fs.mkdir(config.objectsDir, { recursive: true });
}

function objectDir(id) {
  return path.join(config.objectsDir, id);
}

function metaPath(id) {
  return path.join(objectDir(id), "object.json");
}

export async function objectExists(id) {
  if (!isValidObjectId(id)) return false;
  try {
    await fs.access(metaPath(id));
    return true;
  } catch {
    return false;
  }
}

export async function readObject(id) {
  if (!isValidObjectId(id)) return null;
  try {
    const raw = await fs.readFile(metaPath(id), "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export async function writeObjectMeta(id, meta) {
  const dir = objectDir(id);
  await fs.mkdir(path.join(dir, "images"), { recursive: true });
  await fs.mkdir(path.join(dir, "thumbnail"), { recursive: true });
  await fs.writeFile(metaPath(id), JSON.stringify(meta, null, 2), "utf8");
}

export function imagePath(id, filename) {
  const safe = sanitizeImageFilename(filename);
  if (!safe) return null;
  return path.join(objectDir(id), "images", safe);
}

export function thumbnailPath(id) {
  return path.join(objectDir(id), "thumbnail", "thumb.png");
}

/**
 * Build permanent public URLs for an object.
 * @param {string} id
 * @param {string} baseUrl no trailing slash
 */
export function publicUrls(id, baseUrl) {
  const base = baseUrl.replace(/\/$/, "");
  return {
    arUrl: `${base}/ar/${id}`,
    apiUrl: `${base}/api/objects/${id}`,
    deepLink: `arfood://object/${id}`,
    captureDeepLink: "arfood://capture",
  };
}

/**
 * Normalize capture metadata into FoodObject-compatible shape.
 */
export function buildObjectRecord({
  id,
  name,
  widthCm,
  description,
  views,
  isDemo = false,
  createdAt = new Date().toISOString(),
}) {
  const cleanedViews = (views || []).map((v, index) => {
    const image = sanitizeImageFilename(v.image) || `view_${String(index).padStart(3, "0")}.png`;
    const azimuth = normalizeAzimuth(Number(v.azimuth) || 0);
    const elevation = Number(v.elevation) || 0;
    return {
      id: typeof v.id === "string" && v.id ? v.id : randomUUID(),
      azimuth,
      elevation,
      image,
      distance: v.distance == null ? undefined : Number(v.distance),
      capturedAt: v.capturedAt || undefined,
    };
  });

  return {
    id,
    name: String(name || "Food").slice(0, 120),
    createdAt,
    widthCm: clampNumber(Number(widthCm) || 12, 1, 200),
    viewCount: cleanedViews.length,
    isDemo: Boolean(isDemo),
    schemaVersion: 1,
    kind: "photographicARObject",
    notes: description ? String(description).slice(0, 2000) : undefined,
    description: description ? String(description).slice(0, 2000) : undefined,
    views: cleanedViews,
  };
}

function normalizeAzimuth(value) {
  let a = value % 360;
  if (a < 0) a += 360;
  return a;
}

function clampNumber(n, min, max) {
  if (Number.isNaN(n)) return min;
  return Math.min(max, Math.max(min, n));
}

export function resolveBaseUrl(req) {
  if (config.publicBaseUrl) return config.publicBaseUrl;
  const proto = (req.headers["x-forwarded-proto"] || req.protocol || "http").split(",")[0].trim();
  const host = (req.headers["x-forwarded-host"] || req.headers.host || `localhost:${config.port}`)
    .toString()
    .split(",")[0]
    .trim();
  return `${proto}://${host}`;
}
