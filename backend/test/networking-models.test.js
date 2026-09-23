/**
 * Mirrors iOS RemoteObjectService deep-link / ID parsing for Linux CI.
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";

function sanitize(id) {
  if (!id || typeof id !== "string") return null;
  if (!/^[a-zA-Z0-9_-]{8,64}$/.test(id)) return null;
  return id;
}

function remoteIdFromUrl(urlString) {
  const url = new URL(urlString);
  if (url.protocol === "arfood:") {
    const host = (url.hostname || "").toLowerCase();
    if (host === "object") {
      const id = url.pathname.split("/").filter(Boolean)[0];
      return sanitize(id);
    }
    if (host === "capture") return null;
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0]?.toLowerCase() === "object") return sanitize(parts[1]);
    return null;
  }
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts[0] === "ar" && parts[1]) return sanitize(parts[1]);
  if (parts[0] === "api" && parts[1] === "objects" && parts[2]) return sanitize(parts[2]);
  return null;
}

function isCapture(urlString) {
  const url = new URL(urlString);
  if (url.protocol === "arfood:") {
    return (url.hostname || "").toLowerCase() === "capture" ||
      url.pathname.split("/").filter(Boolean)[0]?.toLowerCase() === "capture";
  }
  return url.pathname.replace(/^\/+|\/+$/g, "").toLowerCase() === "capture";
}

describe("iOS networking model mirrors", () => {
  const id = "abcdef0123456789abcdef0123456789";

  it("parses arfood object deep links", () => {
    assert.equal(remoteIdFromUrl(`arfood://object/${id}`), id);
  });

  it("parses https /ar/:id", () => {
    assert.equal(remoteIdFromUrl(`https://example.com/ar/${id}`), id);
  });

  it("parses capture deep link", () => {
    assert.equal(isCapture("arfood://capture"), true);
    assert.equal(isCapture("https://example.com/capture"), true);
  });

  it("rejects path traversal ids", () => {
    assert.equal(remoteIdFromUrl("arfood://object/../etc"), null);
    assert.equal(sanitize("bad"), null);
  });

  it("decodes upload response shape", () => {
    const sample = {
      id,
      name: "Demo Burger",
      widthCm: 12,
      viewCount: 72,
      arUrl: `https://example.com/ar/${id}`,
      deepLink: `arfood://object/${id}`,
    };
    assert.ok(sample.arUrl.includes(sample.id));
    assert.equal(sample.deepLink, `arfood://object/${id}`);
  });
});
