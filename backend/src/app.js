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
  modelPath,
  newObjectId,
  objectExists,
  publicUrls,
  readObject,
  renderImagePath,
  resolveBaseUrl,
  sanitizeImageFilename,
  thumbnailPath,
  writeObjectMeta,
} from "./storage.js";
import {
  createImportDraft,
  processDraft,
  publishDraft,
  readDraft,
  discardDraft,
  ensureGlbDirs,
} from "./glb/pipeline.js";
import { looksLikeGlb } from "./glb/validate.js";
import { menuHtml } from "./pages/menuHtml.js";
import { ownerHtml } from "./pages/ownerHtml.js";
import { compareHtml } from "./pages/compareHtml.js";

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: Math.max(config.maxImageBytes, config.maxGlbBytes),
    files: config.maxFiles,
  },
  fileFilter(_req, file, cb) {
    if (file.fieldname === "glb" || file.fieldname === "model") {
      cb(null, true);
      return;
    }
    const name = sanitizeImageFilename(file.originalname) || sanitizeImageFilename(file.fieldname);
    const okType =
      !file.mimetype ||
      file.mimetype === "image/png" ||
      file.mimetype === "application/octet-stream" ||
      file.mimetype === "image/jpeg" ||
      file.mimetype === "model/gltf-binary";
    if (!okType) {
      cb(new Error("Only PNG/JPEG image or GLB uploads are allowed"));
      return;
    }
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
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    next();
  });
  app.use(express.json({ limit: "2mb" }));

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      service: "ar-food-object-api",
      version: "3.0.0",
      features: ["photographic", "glb-import", "model-viewer-menu", "dual-output"],
    });
  });

  /** Owner UI (was missing — added in backend web app). */
  app.get(["/owner", "/owner/"], (req, res) => {
    const base = resolveBaseUrl(req);
    res.type("html").send(ownerHtml({ base }));
  });

  /** Capture QR minimum path — opens CAPTURE NEW FOOD via deep link. */
  app.get("/capture", (req, res) => {
    const deepLink = "arfood://capture";
    if (wantsJson(req)) {
      res.json({ deepLink, path: "capture" });
      return;
    }
    res.type("html").send(
      landingHtml({
        title: "Capture New Food",
        subtitle: "Open AR Food Capture to photograph a dish.",
        deepLink,
        buttonLabel: "Open Capture",
      })
    );
  });

  /** Customer QR menu — browser 3D when model present; else deep-link / photo. */
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
        kind: obj.kind,
        publishedDefault: obj.publishedDefault || null,
        hasModel3d: Boolean(obj.model3d),
        arUrl: urls.arUrl,
        apiUrl: urls.apiUrl,
        deepLink: urls.deepLink,
      });
      return;
    }
    // Hybrid / model objects get the menu viewer; pure photographic keep enhanced menu with photo spin + deep link.
    res.type("html").send(menuHtml({ obj, urls, base }));
  });

  /** Dev-only dual-output comparison UI. */
  app.get("/dev/compare/:id", async (req, res) => {
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
    if (!obj.model3d) {
      res.status(400).type("html").send("<p>Object has no GLB dual-output assets. Import via /owner first.</p>");
      return;
    }
    const base = resolveBaseUrl(req);
    res.type("html").send(compareHtml({ obj, base }));
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
      modelBaseUrl: obj.model3d ? `${base}/api/objects/${id}/model` : undefined,
      compareUrl: obj.model3d ? `${base}/dev/compare/${id}` : undefined,
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

  app.get("/api/objects/:id/model/:variant", async (req, res) => {
    const { id, variant } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    const map = {
      original: "original.glb",
      "original.glb": "original.glb",
      optimized: "optimized.glb",
      "optimized.glb": "optimized.glb",
      "optimized-mobile": "optimized-mobile.glb",
      "optimized-mobile.glb": "optimized-mobile.glb",
      mobile: "optimized-mobile.glb",
      usdz: "model.usdz",
      "model.usdz": "model.usdz",
    };
    const filename = map[variant];
    if (!filename) {
      res.status(400).json({ error: "Unknown model variant" });
      return;
    }
    const file = modelPath(id, filename);
    if (!file || !fs.existsSync(file)) {
      res.status(404).json({
        error: "Model asset not found",
        note:
          filename.endsWith(".usdz")
            ? "Server-side USDZ is not generated on Linux; use model-viewer Quick Look client conversion when available."
            : undefined,
      });
      return;
    }
    res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
    res.setHeader(
      "Content-Type",
      filename.endsWith(".usdz") ? "model/vnd.usdz+zip" : "model/gltf-binary"
    );
    res.sendFile(path.resolve(file));
  });

  app.get("/api/objects/:id/renders/:setKey/:filename", async (req, res) => {
    const { id, setKey, filename } = req.params;
    if (!isValidObjectId(id)) {
      res.status(400).json({ error: "Invalid object id" });
      return;
    }
    if (filename === "manifest.json") {
      const file = path.join(
        config.objectsDir,
        id,
        "renders",
        `views_${setKey}`,
        "manifest.json"
      );
      if (!fs.existsSync(file)) {
        res.status(404).json({ error: "Manifest not found" });
        return;
      }
      res.setHeader("Cache-Control", "public, max-age=86400");
      res.sendFile(path.resolve(file));
      return;
    }
    const file = renderImagePath(id, setKey, filename);
    if (!file || !fs.existsSync(file)) {
      res.status(404).json({ error: "Render image not found" });
      return;
    }
    res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
    res.sendFile(path.resolve(file));
  });

  // —— GLB import API ——
  app.post("/api/glb/import", (req, res, next) => {
    upload.single("glb")(req, res, (err) => {
      if (err) {
        res.status(400).json({ error: err.message || "Upload failed" });
        return;
      }
      next();
    });
  }, async (req, res) => {
    try {
      await ensureGlbDirs();
      const file = req.file;
      if (!file?.buffer?.length) {
        res.status(400).json({ error: "Missing glb file field" });
        return;
      }
      if (!looksLikeGlb(file.buffer)) {
        res.status(400).json({
          error: "File is not a GLB (bad magic). Export Binary glTF (.glb).",
          code: "BAD_MAGIC",
        });
        return;
      }
      const draft = await createImportDraft(file.buffer, {
        name: req.body?.name,
        widthCm: req.body?.widthCm,
        description: req.body?.description,
      });
      res.status(201).json(draft);
    } catch (err) {
      res.status(err.status || 500).json({ error: err.message || "Import failed", code: err.code });
    }
  });

  app.get("/api/glb/drafts/:draftId", async (req, res) => {
    const draft = await readDraft(req.params.draftId);
    if (!draft) {
      res.status(404).json({ error: "Draft not found" });
      return;
    }
    res.json(draft);
  });

  app.get("/api/glb/drafts/:draftId/:file", async (req, res) => {
    const allowed = new Set(["original.glb", "optimized.glb", "optimized-mobile.glb"]);
    if (!allowed.has(req.params.file)) {
      res.status(400).json({ error: "Invalid draft file" });
      return;
    }
    const file = path.join(config.dataDir, "glb-drafts", req.params.draftId, req.params.file);
    if (!fs.existsSync(file)) {
      res.status(404).json({ error: "File not found" });
      return;
    }
    res.setHeader("Content-Type", "model/gltf-binary");
    res.setHeader("Cache-Control", "no-store");
    res.sendFile(path.resolve(file));
  });

  app.post("/api/glb/drafts/:draftId/process", async (req, res) => {
    try {
      const draft = await processDraft(req.params.draftId, {
        acceptedSuggestionIds: req.body?.acceptedSuggestionIds || [],
        skipRenders: Boolean(req.body?.skipRenders),
      });
      res.json(draft);
    } catch (err) {
      res.status(err.status || 500).json({ error: err.message || "Process failed" });
    }
  });

  app.post("/api/glb/drafts/:draftId/publish", async (req, res) => {
    try {
      const record = await publishDraft(req.params.draftId, {
        publishedDefault: req.body?.publishedDefault,
        name: req.body?.name,
        widthCm: req.body?.widthCm,
        description: req.body?.description,
      });
      const base = resolveBaseUrl(req);
      const urls = publicUrls(record.id, base);
      res.status(201).json({
        ...record,
        arUrl: urls.arUrl,
        apiUrl: urls.apiUrl,
        deepLink: urls.deepLink,
        compareUrl: `${base}/dev/compare/${record.id}`,
      });
    } catch (err) {
      res.status(err.status || 500).json({ error: err.message || "Publish failed" });
    }
  });

  app.delete("/api/glb/drafts/:draftId", async (req, res) => {
    await discardDraft(req.params.draftId);
    res.status(204).end();
  });

  // —— Existing photographic create (preserved) ——
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
    <p class="hint">Requires the AR Food iPhone app for native photographic AR.</p>
    ${meta}
  </div>
  <script>
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
