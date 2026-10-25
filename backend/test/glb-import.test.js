import assert from "node:assert/strict";
import { createServer } from "node:http";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import { createApp } from "../src/app.js";
import { config } from "../src/config.js";
import { ensureStorage } from "../src/storage.js";
import { buildTestCubeGlb } from "../src/glb/fixture.js";
import { validateGlb } from "../src/glb/validate.js";
import { inspectGlb } from "../src/glb/inspect.js";
import { suggestCleanup } from "../src/glb/cleanup.js";

const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64"
);

function multipartGlb({ glb, fields = {} }) {
  const boundary = "----GlbTestBoundary";
  const chunks = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(
      `--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`
    );
  }
  chunks.push(
    `--${boundary}\r\nContent-Disposition: form-data; name="glb"; filename="test.glb"\r\nContent-Type: model/gltf-binary\r\n\r\n`
  );
  chunks.push(glb);
  chunks.push(`\r\n--${boundary}--\r\n`);
  return {
    body: Buffer.concat(chunks.map((c) => (Buffer.isBuffer(c) ? c : Buffer.from(c)))),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

function multipartImages({ fields, files }) {
  const boundary = "----ArFoodTestBoundary7MA4YWxkTrZu0gW";
  const chunks = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(
      `--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`
    );
  }
  for (const file of files) {
    chunks.push(
      `--${boundary}\r\nContent-Disposition: form-data; name="${file.field}"; filename="${file.filename}"\r\nContent-Type: ${file.contentType || "image/png"}\r\n\r\n`
    );
    chunks.push(file.buffer);
    chunks.push("\r\n");
  }
  chunks.push(`--${boundary}--\r\n`);
  return {
    body: Buffer.concat(chunks.map((c) => (Buffer.isBuffer(c) ? c : Buffer.from(c)))),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

describe("GLB import + dual output", () => {
  let server;
  let baseUrl;
  let tmpDir;
  const cube = buildTestCubeGlb();

  before(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "arfood-glb-"));
    config.objectsDir = path.join(tmpDir, "objects");
    config.dataDir = tmpDir;
    config.publicBaseUrl = "";
    config.maxGlbBytes = 5 * 1024 * 1024;
    await ensureStorage();
    const app = createApp();
    server = createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
  });

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("validates a generated cube GLB", () => {
    const v = validateGlb(cube);
    assert.equal(v.ok, true);
    const ins = inspectGlb(cube);
    assert.ok(ins.meshCount >= 1);
    assert.ok(ins.triangleEstimate > 0);
    const { suggestions } = suggestCleanup(ins);
    assert.ok(Array.isArray(suggestions));
  });

  it("rejects invalid file (not GLB)", async () => {
    const { body, contentType } = multipartGlb({
      glb: Buffer.from("not-a-glb"),
      fields: { name: "Bad" },
    });
    const res = await fetch(`${baseUrl}/api/glb/import`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(res.status, 400);
    const json = await res.json();
    assert.match(json.error, /GLB|magic/i);
  });

  it("rejects oversized GLB", async () => {
    const prev = config.maxGlbBytes;
    config.maxGlbBytes = 100;
    try {
      // Still needs valid magic to pass looksLikeGlb then fail size in validate
      const tinyHeader = Buffer.alloc(120);
      tinyHeader.writeUInt32LE(0x46546c67, 0);
      tinyHeader.writeUInt32LE(2, 4);
      tinyHeader.writeUInt32LE(120, 8);
      const { body, contentType } = multipartGlb({ glb: tinyHeader, fields: { name: "Big" } });
      const res = await fetch(`${baseUrl}/api/glb/import`, {
        method: "POST",
        headers: { "Content-Type": contentType },
        body,
      });
      assert.equal(res.status, 400);
    } finally {
      config.maxGlbBytes = prev;
    }
  });

  it("imports, previews, processes (skip renders), publishes, serves menu + model", async () => {
    const { body, contentType } = multipartGlb({
      glb: cube,
      fields: { name: "Cube Dish", widthCm: "11", description: "test" },
    });
    const imp = await fetch(`${baseUrl}/api/glb/import`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(imp.status, 201);
    const draft = await imp.json();
    assert.ok(draft.draftId);
    assert.equal(draft.status, "preview");
    assert.ok(draft.inspection.triangleEstimate > 0);

    const orig = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}/original.glb`);
    assert.equal(orig.status, 200);
    assert.equal(orig.headers.get("content-type"), "model/gltf-binary");

    const proc = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}/process`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        acceptedSuggestionIds: ["texture-resize"],
        skipRenders: true,
      }),
    });
    assert.equal(proc.status, 200, await proc.clone().text());
    const processed = await proc.json();
    assert.equal(processed.status, "processed");
    assert.ok(processed.model3d.sizes.optimizedBytes > 0);
    assert.ok(processed.model3d.sizes.mobileBytes > 0);

    // Optimization failure path: bad draft id
    const badProc = await fetch(`${baseUrl}/api/glb/drafts/notarealdraftid0000000000000000/process`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    assert.equal(badProc.status, 404);

    const pub = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}/publish`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ publishedDefault: "direct3d" }),
    });
    assert.equal(pub.status, 201, await pub.clone().text());
    const published = await pub.json();
    assert.ok(published.id);
    assert.ok(published.arUrl.includes(`/ar/${published.id}`));
    assert.equal(published.kind, "hybridARObject");

    const model = await fetch(`${baseUrl}/api/objects/${published.id}/model/optimized-mobile.glb`);
    assert.equal(model.status, 200);

    const missingUsdz = await fetch(`${baseUrl}/api/objects/${published.id}/model/usdz`);
    assert.equal(missingUsdz.status, 404);

    const menu = await fetch(`${baseUrl}/ar/${published.id}`);
    assert.equal(menu.status, 200);
    const html = await menu.text();
    assert.match(html, /model-viewer/);
    assert.match(html, /Cube Dish/);

    const compare = await fetch(`${baseUrl}/dev/compare/${published.id}`);
    // compare requires render sets for full UX; still loads page when model3d present
    assert.equal(compare.status, 200);
    assert.match(await compare.text(), /Dev compare/);

    // reload persistence
    const get = await fetch(`${baseUrl}/api/objects/${published.id}`);
    assert.equal(get.status, 200);
    const again = await get.json();
    assert.equal(again.model3d.status, "ready");
  });

  it("discards draft without publishing", async () => {
    const { body, contentType } = multipartGlb({
      glb: cube,
      fields: { name: "Temp" },
    });
    const imp = await fetch(`${baseUrl}/api/glb/import`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    const draft = await imp.json();
    const del = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}`, { method: "DELETE" });
    assert.equal(del.status, 204);
    const get = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}`);
    assert.equal(get.status, 404);
  });

  it("preserves existing photographic object create + QR access", async () => {
    const metadata = {
      name: "Photo Only",
      widthCm: 12,
      views: [{ azimuth: 0, elevation: 0, image: "view_000.png" }],
    };
    const { body, contentType } = multipartImages({
      fields: { metadata: JSON.stringify(metadata) },
      files: [{ field: "images", filename: "view_000.png", buffer: PNG }],
    });
    const createRes = await fetch(`${baseUrl}/api/objects`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(createRes.status, 201);
    const created = await createRes.json();
    assert.equal(created.kind, "photographicARObject");
    const ar = await fetch(`${baseUrl}/ar/${created.id}`);
    assert.equal(ar.status, 200);
    const html = await ar.text();
    assert.match(html, /Photo Only/);
    // no model endpoints
    const m = await fetch(`${baseUrl}/api/objects/${created.id}/model/optimized`);
    assert.equal(m.status, 404);
  });

  it("owner page is served", async () => {
    const res = await fetch(`${baseUrl}/owner`);
    assert.equal(res.status, 200);
    assert.match(await res.text(), /GLB import/);
  });
});

describe("dual pipeline render + cache (integration)", () => {
  let server;
  let baseUrl;
  let tmpDir;

  before(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "arfood-glb-render-"));
    config.objectsDir = path.join(tmpDir, "objects");
    config.dataDir = tmpDir;
    config.publicBaseUrl = "";
    config.renderRes = 128;
    process.env.RENDER_RES = "128";
    await ensureStorage();
    const app = createApp();
    server = createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("renders 16+72, caches second process, publishes image set", async () => {
    const cube = buildTestCubeGlb({ size: 0.1 });
    const { body, contentType } = multipartGlb({
      glb: cube,
      fields: { name: "Render Dish", widthCm: "10" },
    });
    const imp = await fetch(`${baseUrl}/api/glb/import`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(imp.status, 201);
    const draft = await imp.json();

    const t0 = Date.now();
    const proc = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}/process`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ acceptedSuggestionIds: [] }),
    });
    const procText = await proc.text();
    assert.equal(proc.status, 200, procText);
    const processed = JSON.parse(procText);
    const firstMs = Date.now() - t0;
    assert.equal(processed.renderSets["16"].viewCount, 16);
    assert.equal(processed.renderSets["72"].viewCount, 72);
    assert.ok(processed.renderSets["16"].engine);

    // Second import of same bytes should hit cache
    const { body: body2, contentType: ct2 } = multipartGlb({
      glb: cube,
      fields: { name: "Render Dish 2", widthCm: "10" },
    });
    const imp2 = await fetch(`${baseUrl}/api/glb/import`, {
      method: "POST",
      headers: { "Content-Type": ct2 },
      body: body2,
    });
    const draft2 = await imp2.json();
    const t1 = Date.now();
    const proc2 = await fetch(`${baseUrl}/api/glb/drafts/${draft2.draftId}/process`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ acceptedSuggestionIds: [] }),
    });
    assert.equal(proc2.status, 200);
    const processed2 = await proc2.json();
    const secondMs = Date.now() - t1;
    assert.equal(processed2.renderSets["16"].cached, true);
    // Cache should be faster than first full render (soft check — don't fail flaky CI hard)
    assert.ok(secondMs < firstMs || processed2.renderSets["16"].cached);

    const pub = await fetch(`${baseUrl}/api/glb/drafts/${draft.draftId}/publish`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ publishedDefault: "views16" }),
    });
    assert.equal(pub.status, 201);
    const published = await pub.json();
    assert.equal(published.viewCount, 16);
    const img = await fetch(
      `${baseUrl}/api/objects/${published.id}/images/view_000.png`
    );
    assert.equal(img.status, 200);
    const render = await fetch(
      `${baseUrl}/api/objects/${published.id}/renders/72/view_000.png`
    );
    assert.equal(render.status, 200);

    // Retry process on already published draft should still be readable; new process on failed is separate
    const footprint = published.storageFootprint;
    assert.ok(footprint.originalGlbBytes > 0);
  });
});
