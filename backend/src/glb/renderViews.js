/**
 * Synthetic view renderer for dual-output Pipeline B.
 *
 * Primary path (this environment): headless Chromium + three.js
 *   - Transparent canvas, unlit MeshBasicMaterial from map/color
 *   - Orbit around 1–99th percentile vertex bounds (same idea as Blender reference)
 *   - Elevations: camera orbit uses Blender-style 10° / 35° for framing;
 *     metadata elevations written as 0 / 15 to match CapturePass / DemoBurger.
 *
 * Optional path: if process.env.BLENDER points at a Blender 4.2+ binary,
 * shells out to scripts/blender/render_views.py (adapted from the box reference).
 *
 * Resolution default 512² — justified for mobile photographic billboards
 * (on-screen dish ≈ 200–400 CSS px); override with RENDER_RES. Avoids 72×1024 bloat.
 */

import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_SCRIPTS = path.resolve(__dirname, "../../scripts/blender");

/** Capture conventions (must match iOS CaptureConstants / adaptive planner). */
export const VIEW_PRESETS = {
  views16: {
    key: "16",
    azStep: 45,
    label: "adaptive_16",
    metaElevations: [
      { label: "low", metaDeg: 0, cameraDeg: 10 },
      { label: "high", metaDeg: 15, cameraDeg: 35 },
    ],
  },
  views72: {
    key: "72",
    azStep: 10,
    label: "classic_72",
    metaElevations: [
      { label: "low", metaDeg: 0, cameraDeg: 10 },
      { label: "high", metaDeg: 15, cameraDeg: 35 },
    ],
  },
};

export function renderConfigHash({ azStep, res, engine }) {
  return createHash("sha256")
    .update(JSON.stringify({ azStep, res, engine, elev: [10, 35], meta: [0, 15], v: 1 }))
    .digest("hex")
    .slice(0, 16);
}

/**
 * @param {Buffer} glbBuf
 * @param {string} outDir
 * @param {{ azStep: number, res?: number, engine?: 'three'|'blender' }} opts
 */
export async function renderViewSet(glbBuf, outDir, opts) {
  const azStep = opts.azStep;
  const res = opts.res ?? Number(process.env.RENDER_RES || 512);
  const blender = process.env.BLENDER;
  const preferBlender = opts.engine === "blender" || (opts.engine !== "three" && blender && existsSync(blender));

  await fs.mkdir(outDir, { recursive: true });
  const glbPath = path.join(outDir, "_source.glb");
  await fs.writeFile(glbPath, glbBuf);

  let result;
  if (preferBlender) {
    result = await renderWithBlender(blender, glbPath, outDir, azStep, res);
  } else {
    result = await renderWithThree(glbPath, outDir, azStep, res);
  }

  // Map to FoodObject views[] (view_XXX.png + meta elevations 0/15)
  const views = [];
  let index = 0;
  for (const elev of VIEW_PRESETS.views72.metaElevations) {
    // use same elev labels for both presets
    for (let az = 0; az < 360; az += azStep) {
      const srcName = `azimuth_${String(az).padStart(3, "0")}_elevation_${elev.label}.png`;
      const destName = `view_${String(index).padStart(3, "0")}.png`;
      const src = path.join(outDir, srcName);
      const dest = path.join(outDir, destName);
      await fs.copyFile(src, dest);
      views.push({
        id: `synth-${azStep}-${az}-${elev.label}`,
        azimuth: az,
        elevation: elev.metaDeg,
        image: destName,
        distance: 0.45,
        source: "synthetic_render",
        status: "rendered_unreviewed",
        cameraElevationDeg: elev.cameraDeg,
        renderName: srcName,
      });
      index++;
    }
  }

  const manifest = {
    ...(result.manifest || {}),
    engine: result.engine,
    azStep,
    resolution: res,
    viewCount: views.length,
    views,
    metaElevationsNote:
      "Camera orbit elevations 10°/35° (Blender reference). Metadata elevations 0/15 match CapturePass / DemoBurger for the photographic loader.",
  };
  await fs.writeFile(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
  return { views, manifest, engine: result.engine, outDir };
}

async function renderWithBlender(blenderBin, glbPath, outDir, azStep, res) {
  const script = path.join(REPO_SCRIPTS, "render_views.py");
  if (!existsSync(script)) {
    throw new Error("Blender render_views.py missing under backend/scripts/blender");
  }
  await runCmd(blenderBin, ["-b", "-P", script, "--", glbPath, outDir, String(azStep), String(res)], {
    timeoutMs: 30 * 60 * 1000,
  });
  let manifest = {};
  try {
    manifest = JSON.parse(await fs.readFile(path.join(outDir, "manifest.json"), "utf8"));
  } catch {
    /* rebuilt below */
  }
  return { engine: "blender", manifest };
}

async function renderWithThree(glbPath, outDir, azStep, res) {
  const browser = await chromium.launch({
    headless: true,
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--no-sandbox"],
  });
  try {
    const page = await browser.newPage({
      viewport: { width: res, height: res },
      deviceScaleFactor: 1,
    });
    const glbBuf = await fs.readFile(glbPath);
    // Serve GLB via route (avoids file:// CORS and huge evaluate payloads).
    await page.route("**/__model.glb", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "model/gltf-binary",
        body: glbBuf,
      });
    });
    const html = threeRenderHtml(res);
    await page.setContent(html, { waitUntil: "load" });
    await page.waitForFunction(() => window.__RENDER_READY === true, null, { timeout: 120_000 });
    const loadResult = await page.evaluate(async () => {
      return window.__loadGlbUrl("http://localhost/__model.glb");
    });
    if (!loadResult?.ok) {
      throw new Error(loadResult?.error || "Failed to load GLB in headless three.js");
    }

    const elevs = [
      { label: "low", cameraDeg: 10 },
      { label: "high", cameraDeg: 35 },
    ];
    const manViews = [];
    for (const elev of elevs) {
      for (let az = 0; az < 360; az += azStep) {
        const pngB64 = await page.evaluate(
          ({ az, el }) => window.__renderView(az, el),
          { az, el: elev.cameraDeg }
        );
        const fn = `azimuth_${String(az).padStart(3, "0")}_elevation_${elev.label}.png`;
        const buf = Buffer.from(pngB64, "base64");
        await fs.writeFile(path.join(outDir, fn), buf);
        manViews.push({
          path: fn,
          azimuth_deg: az,
          elevation_label: elev.label,
          elevation_deg: elev.cameraDeg,
          width: res,
          height: res,
          source: "synthetic_render",
          status: "rendered_unreviewed",
        });
      }
    }
    const meta = await page.evaluate(() => window.__getMeta());
    return {
      engine: "three_playwright",
      manifest: {
        source_glb: path.basename(glbPath),
        camera: meta.camera,
        bbox_min: meta.bboxMin,
        bbox_max: meta.bboxMax,
        views: manViews,
      },
    };
  } finally {
    await browser.close();
  }
}

function threeRenderHtml(res) {
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<style>html,body{margin:0;background:transparent;overflow:hidden}canvas{display:block}</style>
</head><body>
<script type="importmap">
{"imports":{
  "three":"https://unpkg.com/three@0.170.0/build/three.module.js",
  "three/addons/":"https://unpkg.com/three@0.170.0/examples/jsm/"
}}
</script>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const res = ${res};
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setClearColor(0x000000, 0);
renderer.setSize(res, res, false);
renderer.setPixelRatio(1);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 1000);
camera.filmGauge = 36;
// ~50mm equivalent: fov already ~40° horizontal-ish; keep fixed

let root = null;
let center = new THREE.Vector3();
let dist = 2;
let bboxMin = [0,0,0], bboxMax = [0,0,0];

function percentileBounds(positions, pLow, pHigh) {
  const xs=[], ys=[], zs=[];
  for (let i=0;i<positions.length;i+=3){ xs.push(positions[i]); ys.push(positions[i+1]); zs.push(positions[i+2]); }
  xs.sort((a,b)=>a-b); ys.sort((a,b)=>a-b); zs.sort((a,b)=>a-b);
  const pick=(a,p)=>a[Math.min(a.length-1, Math.max(0, Math.floor(p/100*(a.length-1))))];
  return {
    min: new THREE.Vector3(pick(xs,pLow), pick(ys,pLow), pick(zs,pLow)),
    max: new THREE.Vector3(pick(xs,pHigh), pick(ys,pHigh), pick(zs,pHigh)),
  };
}

function toUnlit(obj) {
  obj.traverse((c) => {
    if (!c.isMesh) return;
    const mats = Array.isArray(c.material) ? c.material : [c.material];
    const next = mats.map((m) => {
      const map = m.map || null;
      const color = m.color ? m.color.clone() : new THREE.Color(0xffffff);
      const mat = new THREE.MeshBasicMaterial({
        map, color, transparent: true, opacity: m.opacity ?? 1,
        side: THREE.DoubleSide, depthWrite: true,
      });
      return mat;
    });
    c.material = next.length === 1 ? next[0] : next;
  });
}

async function finishLoad(gltf) {
  root = gltf.scene;
  toUnlit(root);
  scene.add(root);
  const pos = [];
  root.updateMatrixWorld(true);
  root.traverse((c) => {
    if (!c.isMesh || !c.geometry) return;
    const attr = c.geometry.attributes.position;
    if (!attr) return;
    const v = new THREE.Vector3();
    for (let i=0;i<attr.count;i++){
      v.fromBufferAttribute(attr, i).applyMatrix4(c.matrixWorld);
      pos.push(v.x, v.y, v.z);
    }
  });
  if (pos.length < 3) return { ok:false, error:'No mesh positions' };
  const b = percentileBounds(pos, 1, 99);
  center = b.min.clone().add(b.max).multiplyScalar(0.5);
  const rad = b.max.clone().sub(b.min).length() / 2;
  const fov = THREE.MathUtils.degToRad(camera.fov);
  dist = (rad / Math.sin(fov / 2)) * 1.05;
  bboxMin = [b.min.x,b.min.y,b.min.z];
  bboxMax = [b.max.x,b.max.y,b.max.z];
  return { ok:true, center:[center.x,center.y,center.z], dist, rad };
}

window.__loadGlbUrl = async function(url) {
  try {
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync(url);
    return finishLoad(gltf);
  } catch (e) {
    return { ok:false, error: String(e.message||e) };
  }
};

window.__loadGlbBuffer = async function(arrayBuffer) {
  try {
    const loader = new GLTFLoader();
    const gltf = await loader.parseAsync(arrayBuffer, '');
    return finishLoad(gltf);
  } catch (e) {
    return { ok:false, error: String(e.message||e) };
  }
};

window.__renderView = function(azDeg, elDeg) {
  const e = THREE.MathUtils.degToRad(elDeg);
  const z = THREE.MathUtils.degToRad(azDeg);
  // Match Blender reference: az0 ≈ -Z in three Y-up (front)
  camera.position.set(
    center.x + dist * Math.cos(e) * Math.sin(z),
    center.y + dist * Math.sin(e),
    center.z + -dist * Math.cos(e) * Math.cos(z)
  );
  camera.lookAt(center);
  camera.updateProjectionMatrix();
  renderer.render(scene, camera);
  const dataUrl = renderer.domElement.toDataURL('image/png');
  return dataUrl.split(',')[1] || '';
};

window.__getMeta = function() {
  return {
    camera: { lens_mm_equiv: 50, distance: dist, center: [center.x,center.y,center.z], fov: camera.fov },
    bboxMin, bboxMax
  };
};

window.__RENDER_READY = true;
</script>
</body></html>`;
}

function runCmd(cmd, args, { timeoutMs }) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    const t = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`Command timed out: ${cmd}`));
    }, timeoutMs);
    child.stderr.on("data", (d) => {
      stderr += d.toString();
    });
    child.on("error", (e) => {
      clearTimeout(t);
      reject(e);
    });
    child.on("close", (code) => {
      clearTimeout(t);
      if (code === 0) resolve();
      else reject(new Error(`Exit ${code}: ${stderr.slice(-2000)}`));
    });
  });
}

export function sourceHash(buf) {
  return createHash("sha256").update(buf).digest("hex");
}
