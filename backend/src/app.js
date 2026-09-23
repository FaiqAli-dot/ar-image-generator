import express from "express";
import multer from "multer";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import {
  buildObjectRecord,
  imagePath,
  isValidObjectId,
  newObjectId,
  objectExists,
  publicUrls,
  readObject,
  resolveBaseUrl,
  sanitizeImageFilename,
  thumbnailPath,
  writeObjectMeta,
} from "./storage.js";

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: config.maxImageBytes,
    files: config.maxFiles,
  },
  fileFilter(_req, file, cb) {
    const name = sanitizeImageFilename(file.originalname) || sanitizeImageFilename(file.fieldname);
    const okType =
      !file.mimetype ||
      file.mimetype === "image/png" ||
      file.mimetype === "application/octet-stream" ||
      file.mimetype === "image/jpeg";
    if (!okType) {
      cb(new Error("Only PNG/JPEG image uploads are allowed"));
      return;
    }
    // thumbnail field may use any safe name; views must be .png eventually
    if (file.fieldname === "thumbnail" || name) {
      cb(null, true);
      return;
    }
    cb(new Error("Invalid filename"));
  },
});

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    next();
  });
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "ar-food-object-api", version: "2.0.0" });
  });

  /** Capture QR minimum path — opens CAPTURE NEW FOOD via deep link. */
  app.get("/capture", (req, res) => {
    const deepLink = "arfood://capture";
    if (wantsJson(req)) {
      res.json({ deepLink, path: "capture" });
      return;
    }
    res.type("html").send(landingHtml({
      title: "Capture New Food",
      subtitle: "Open AR Food Capture to photograph a dish.",
      deepLink,
      buttonLabel: "Open Capture",
    }));
  });

  app.get("/ar/:id", async (req, res) => {
    const { id } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    const obj = await readObject(id);
    if (!obj) {
      res.status(404).json({ error: "Object not found" });
      return;
    }
    const base = resolveBaseUrl(req);
    const urls = publicUrls(id, base);
    if (wantsJson(req)) {
      res.json({
        id,
        name: obj.name,
        widthCm: obj.widthCm,
        viewCount: obj.viewCount,
        arUrl: urls.arUrl,
        apiUrl: urls.apiUrl,
        deepLink: urls.deepLink,
      });
      return;
    }
    res.type("html").send(landingHtml({
      title: obj.name,
      subtitle: `${obj.viewCount} photographic views · ${obj.widthCm} cm — open in AR Food to place on a table.`,
      deepLink: urls.deepLink,
      buttonLabel: "View in AR",
      metaUrl: urls.apiUrl,
    }));
  });

  app.get("/api/objects/:id", async (req, res) => {
    const { id } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    const obj = await readObject(id);
    if (!obj) {
      res.status(404).json({ error: "Object not found" });
      return;
    }
    const base = resolveBaseUrl(req);
    const urls = publicUrls(id, base);
    res.json({
      ...obj,
      arUrl: urls.arUrl,
      apiUrl: urls.apiUrl,
      deepLink: urls.deepLink,
      imageBaseUrl: `${base}/api/objects/${id}/images`,
      thumbnailUrl: `${base}/api/objects/${id}/thumbnail`,
    });
  });

  app.get("/api/objects/:id/images/:filename", async (req, res) => {
    const { id, filename } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    const file = imagePath(id, filename);
    if (!file || !fs.existsSync(file)) {
      res.status(404).json({ error: "Image not found" });
      return;
    }
    res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
    res.sendFile(path.resolve(file));
  });

  app.get("/api/objects/:id/thumbnail", async (req, res) => {
    const { id } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    const file = thumbnailPath(id);
    if (!fs.existsSync(file)) {
      res.status(404).json({ error: "Thumbnail not found" });
      return;
    }
    res.setHeader("Cache-Control", "public, max-age=86400");
    res.sendFile(path.resolve(file));
  });

  app.post(
    "/api/objects",
    (req, res, next) => {
      upload.any()(req, res, (err) => {
        if (err) {
          res.status(400).json({ error: err.message || "Upload failed" });
          return;
        }
        next();
      });
    },
    async (req, res) => {
      try {
        const result = await handleCreateObject(req);
        res.status(201).json(result);
      } catch (err) {
        const status = err.status || 500;
        res.status(status).json({ error: err.message || "Server error" });
      }
    }
  );

  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    res.status(status).json({ error: err.message || "Server error" });
  });

  return app;
}

async function handleCreateObject(req) {
  let metaPayload;
  try {
    const raw = req.body?.metadata ?? req.body?.meta;
    if (!raw) {
      const err = new Error("Missing metadata field (JSON string or object)");
      err.status = 400;
      throw err;
    }
    metaPayload = typeof raw === "string" ? JSON.parse(raw) : raw;
  } catch (e) {
    if (e.status) throw e;
    const err = new Error("Invalid metadata JSON");
    err.status = 400;
    throw err;
  }

  const name = metaPayload.name;
  const widthCm = metaPayload.widthCm;
  const description = metaPayload.description ?? metaPayload.notes ?? null;
  const views = metaPayload.views;
  const isDemo = Boolean(metaPayload.isDemo);

  if (!name || typeof name !== "string") {
    const err = new Error("name is required");
    err.status = 400;
    throw err;
  }
  if (widthCm == null || Number.isNaN(Number(widthCm))) {
    const err = new Error("widthCm is required");
    err.status = 400;
    throw err;
  }
  if (!Array.isArray(views) || views.length === 0) {
    const err = new Error("views array is required");
    err.status = 400;
    throw err;
  }
  if (views.length > config.maxViews) {
    const err = new Error(`Too many views (max ${config.maxViews})`);
    err.status = 400;
    throw err;
  }

  const files = Array.isArray(req.files) ? req.files : [];
  const imageFiles = files.filter((f) => f.fieldname === "images" || f.fieldname.startsWith("image"));
  const thumbFile = files.find((f) => f.fieldname === "thumbnail");

  // Also accept files keyed by filename
  const byName = new Map();
  for (const f of files) {
    const safe = sanitizeImageFilename(f.originalname) || sanitizeImageFilename(f.fieldname);
    if (safe && f.fieldname !== "thumbnail") {
      byName.set(safe, f);
    }
  }
  for (const f of imageFiles) {
    const safe = sanitizeImageFilename(f.originalname);
    if (safe) byName.set(safe, f);
  }

  for (const view of views) {
    const fname = sanitizeImageFilename(view.image);
    if (!fname) {
      const err = new Error(`Invalid image filename in views: ${view.image}`);
      err.status = 400;
      throw err;
    }
    if (!byName.has(fname)) {
      const err = new Error(`Missing uploaded image for view: ${fname}`);
      err.status = 400;
      throw err;
    }
    const buf = byName.get(fname).buffer;
    if (!buf || buf.length === 0) {
      const err = new Error(`Empty image for ${fname}`);
      err.status = 400;
      throw err;
    }
    if (!looksLikePng(buf) && !looksLikeJpeg(buf)) {
      const err = new Error(`File is not a PNG/JPEG image: ${fname}`);
      err.status = 400;
      throw err;
    }
  }

  const id = newObjectId();
  if (await objectExists(id)) {
    const err = new Error("ID collision — retry");
    err.status = 409;
    throw err;
  }

  const record = buildObjectRecord({
    id,
    name,
    widthCm,
    description,
    views,
    isDemo,
  });

  await writeObjectMeta(id, record);

  for (const view of record.views) {
    const file = byName.get(view.image);
    const dest = imagePath(id, view.image);
    await fsp.writeFile(dest, file.buffer);
  }

  if (thumbFile?.buffer?.length) {
    await fsp.writeFile(thumbnailPath(id), thumbFile.buffer);
  } else {
    // Use first view as thumbnail fallback
    const first = record.views[0];
    const src = imagePath(id, first.image);
    await fsp.copyFile(src, thumbnailPath(id));
  }

  const base = resolveBaseUrl(req);
  const urls = publicUrls(id, base);
  return {
    id,
    name: record.name,
    widthCm: record.widthCm,
    viewCount: record.viewCount,
    createdAt: record.createdAt,
    description: record.description,
    isDemo: record.isDemo,
    kind: record.kind,
    arUrl: urls.arUrl,
    apiUrl: urls.apiUrl,
    deepLink: urls.deepLink,
  };
}

function wantsJson(req) {
  const accept = (req.headers.accept || "").toLowerCase();
  return accept.includes("application/json") || req.query.format === "json";
}

function looksLikePng(buf) {
  return (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47
  );
}

function looksLikeJpeg(buf) {
  return buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
}

function landingHtml({ title, subtitle, deepLink, buttonLabel, metaUrl }) {
  const safeTitle = escapeHtml(title);
  const safeSub = escapeHtml(subtitle);
  const safeLink = escapeHtml(deepLink);
  const safeBtn = escapeHtml(buttonLabel);
  const meta = metaUrl
    ? `<p class="meta"><a href="${escapeHtml(metaUrl)}">Object JSON</a></p>`
    : "";
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeTitle} · AR Food</title>
  <style>
    :root { color-scheme: dark; }
    body { margin:0; min-height:100vh; font-family: ui-rounded, system-ui, sans-serif;
      background: radial-gradient(1200px 600px at 80% -10%, #3a2a12, transparent),
                  linear-gradient(160deg, #12141a, #050506); color:#f5f5f5;
      display:flex; align-items:center; justify-content:center; padding:24px; }
    .card { max-width:420px; width:100%; text-align:center; }
    h1 { font-size:1.75rem; margin:0 0 12px; letter-spacing:0.04em; }
    p { opacity:0.75; line-height:1.45; }
    a.btn { display:inline-block; margin-top:28px; padding:16px 28px; border-radius:14px;
      background: linear-gradient(135deg,#f2b849,#d98c2e); color:#111; font-weight:700;
      text-decoration:none; letter-spacing:0.08em; text-transform:uppercase; }
    .meta { margin-top:24px; font-size:0.85rem; }
    .meta a { color:#f2b849; }
    .hint { margin-top:18px; font-size:0.8rem; opacity:0.55; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${safeTitle}</h1>
    <p>${safeSub}</p>
    <a class="btn" href="${safeLink}">${safeBtn}</a>
    <p class="hint">Requires the AR Food iPhone app. Photographic multi-view AR — not a 3D mesh.</p>
    ${meta}
  </div>
  <script>
    // Best-effort auto-open of the native deep link when scanned on device.
    setTimeout(function () {
      try { window.location.href = ${JSON.stringify(deepLink)}; } catch (e) {}
    }, 400);
  </script>
</body>
</html>`;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
