import assert from "node:assert/strict";
import { createServer } from "node:http";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import { createApp } from "../src/app.js";
import { config } from "../src/config.js";
import { ensureStorage } from "../src/storage.js";

/** Minimal valid 1x1 PNG */
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64"
);

function multipartBody({ fields, files }) {
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

describe("AR Food object API", () => {
  let server;
  let baseUrl;
  let tmpDir;

  before(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "arfood-api-"));
    config.objectsDir = path.join(tmpDir, "objects");
    config.dataDir = tmpDir;
    config.publicBaseUrl = "";
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

  it("GET /health", async () => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.ok, true);
  });

  it("rejects create without metadata", async () => {
    const { body, contentType } = multipartBody({
      fields: {},
      files: [{ field: "images", filename: "view_000.png", buffer: PNG }],
    });
    const res = await fetch(`${baseUrl}/api/objects`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(res.status, 400);
  });

  it("rejects invalid id retrieval", async () => {
    const res = await fetch(`${baseUrl}/api/objects/bad`);
    assert.equal(res.status, 400);
  });

  it("creates object, stores real PNGs, returns permanent arUrl", async () => {
    const metadata = {
      name: "Test Burger",
      widthCm: 14,
      description: "Phase 2 upload test",
      views: [
        { azimuth: 0, elevation: 0, image: "view_000.png" },
        { azimuth: 10, elevation: 0, image: "view_001.png" },
      ],
    };
    const { body, contentType } = multipartBody({
      fields: { metadata: JSON.stringify(metadata) },
      files: [
        { field: "images", filename: "view_000.png", buffer: PNG },
        { field: "images", filename: "view_001.png", buffer: PNG },
        { field: "thumbnail", filename: "thumb.png", buffer: PNG },
      ],
    });
    const createRes = await fetch(`${baseUrl}/api/objects`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(createRes.status, 201);
    const created = await createRes.json();
    assert.ok(created.id);
    assert.ok(created.arUrl.includes(`/ar/${created.id}`));
    assert.equal(created.viewCount, 2);
    assert.equal(created.widthCm, 14);

    const getRes = await fetch(`${baseUrl}/api/objects/${created.id}`);
    assert.equal(getRes.status, 200);
    const obj = await getRes.json();
    assert.equal(obj.name, "Test Burger");
    assert.equal(obj.views.length, 2);
    assert.equal(obj.kind, "photographicARObject");

    const imgRes = await fetch(`${baseUrl}/api/objects/${created.id}/images/view_000.png`);
    assert.equal(imgRes.status, 200);
    const imgBuf = Buffer.from(await imgRes.arrayBuffer());
    assert.equal(imgBuf[0], 0x89);
    assert.equal(imgBuf[1], 0x50);

    const arRes = await fetch(`${baseUrl}/ar/${created.id}`, {
      headers: { Accept: "application/json" },
    });
    assert.equal(arRes.status, 200);
    const ar = await arRes.json();
    assert.equal(ar.deepLink, `arfood://object/${created.id}`);
  });

  it("returns 404 for missing object", async () => {
    const res = await fetch(`${baseUrl}/api/objects/0123456789abcdef0123456789abcdef`);
    assert.equal(res.status, 404);
  });

  it("rejects path-traversal image names", async () => {
    const metadata = {
      name: "Bad",
      widthCm: 10,
      views: [{ azimuth: 0, elevation: 0, image: "../etc/passwd.png" }],
    };
    const { body, contentType } = multipartBody({
      fields: { metadata: JSON.stringify(metadata) },
      files: [{ field: "images", filename: "view_000.png", buffer: PNG }],
    });
    const res = await fetch(`${baseUrl}/api/objects`, {
      method: "POST",
      headers: { "Content-Type": contentType },
      body,
    });
    assert.equal(res.status, 400);
  });
});
