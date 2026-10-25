/** Dev/testing comparison: Direct 3D / 16-view / 72-view. Not the customer menu. */

export function compareHtml({ obj, base }) {
  const id = obj.id;
  const title = escapeHtml(obj.name || id);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Compare · ${title}</title>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=IBM+Plex+Mono:wght@400;600&display=swap" rel="stylesheet" />
  <script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/4.0.0/model-viewer.min.js"></script>
  <style>
    :root { --bg:#0e1116; --ink:#e8eef7; --muted:#9aa7b8; --accent:#6cb6ff; --line:#243041; }
    *{box-sizing:border-box} body{margin:0;font-family:"IBM Plex Sans",system-ui,sans-serif;background:var(--bg);color:var(--ink)}
    header{padding:14px 16px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:10px;align-items:center}
    h1{font-size:1.05rem;margin:0;font-weight:600}
    .modes button{margin:0 4px 0 0;padding:8px 12px;border-radius:8px;border:1px solid var(--line);background:#18202c;color:var(--ink);font:inherit;cursor:pointer}
    .modes button.active{border-color:var(--accent);color:var(--accent)}
    .grid{display:grid;grid-template-columns:1fr;gap:12px;padding:12px}
    @media(min-width:900px){ .grid.side{grid-template-columns:1fr 1fr} }
    .pane{border:1px solid var(--line);min-height:52vh;position:relative;background:
      radial-gradient(600px 300px at 50% 0%, #1a2433, transparent), #0b0e13}
    .pane h2{position:absolute;top:8px;left:10px;margin:0;font-size:.8rem;color:var(--muted);z-index:2;font-family:"IBM Plex Mono",monospace}
    model-viewer, .spin{width:100%;height:min(62vh,560px);display:block}
    .spin{touch-action:none;display:flex;align-items:center;justify-content:center}
    .spin img{max-width:90%;max-height:90%;object-fit:contain;filter:drop-shadow(0 12px 24px #0008)}
    .metrics{padding:12px 16px 28px;font-family:"IBM Plex Mono",monospace;font-size:.78rem;color:var(--muted);white-space:pre-wrap}
    label.side{margin-left:auto;font-size:.85rem;color:var(--muted)}
    a{color:var(--accent)}
  </style>
</head>
<body>
<header>
  <h1>Dev compare · ${title}</h1>
  <div class="modes" id="modes">
    <button type="button" data-mode="direct3d" class="active">Direct 3D</button>
    <button type="button" data-mode="views16">16-view</button>
    <button type="button" data-mode="views72">72-view</button>
  </div>
  <label class="side"><input type="checkbox" id="sideBySide" /> Side-by-side (when wide)</label>
  <a href="${escapeHtml(base)}/ar/${encodeURIComponent(id)}">Customer menu</a>
</header>
<div class="grid" id="grid">
  <div class="pane" id="paneA"><h2 id="labelA">Direct 3D</h2><div id="slotA"></div></div>
  <div class="pane" id="paneB" hidden><h2 id="labelB">16-view</h2><div id="slotB"></div></div>
</div>
<pre class="metrics" id="metrics">Loading object metrics…</pre>
<script>
const BASE = ${JSON.stringify(base)};
const ID = ${JSON.stringify(id)};
const OBJ = ${JSON.stringify({
  id: obj.id,
  name: obj.name,
  publishedDefault: obj.publishedDefault,
  storageFootprint: obj.storageFootprint,
  model3d: obj.model3d
    ? {
        sizes: obj.model3d.sizes,
        optimizations: obj.model3d.optimizations,
        status: obj.model3d.status,
      }
    : null,
  renderSets: obj.renderSets,
  viewCount: obj.viewCount,
})};

let mode = "direct3d";
let startAz = 0;
let views16 = [];
let views72 = [];

async function loadViewManifest(key) {
  const res = await fetch(BASE + "/api/objects/" + ID + "/renders/" + key + "/manifest.json");
  if (!res.ok) return [];
  const man = await res.json();
  return (man.views || []).map(v => ({
    azimuth: v.azimuth,
    elevation: v.elevation,
    src: BASE + "/api/objects/" + ID + "/renders/" + key + "/" + encodeURIComponent(v.image),
  }));
}

function mountMV(slot, src) {
  slot.innerHTML = "";
  const mv = document.createElement("model-viewer");
  mv.src = src;
  mv.setAttribute("camera-controls", "");
  mv.setAttribute("touch-action", "pan-y");
  mv.setAttribute("exposure", "1.05");
  mv.setAttribute("environment-image", "neutral");
  mv.setAttribute("shadow-intensity", "0.5");
  mv.setAttribute("camera-orbit", startAz + "deg 65deg 105%");
  mv.setAttribute("field-of-view", "30deg");
  mv.style.width = "100%";
  mv.style.height = "min(62vh,560px)";
  const t0 = performance.now();
  mv.addEventListener("load", () => {
    recordMetric("direct3d", { timeToVisibleMs: Math.round(performance.now() - t0) });
  });
  slot.appendChild(mv);
  return mv;
}

function mountSpin(slot, views, key) {
  slot.innerHTML = "";
  const wrap = document.createElement("div");
  wrap.className = "spin";
  const img = document.createElement("img");
  img.alt = key;
  wrap.appendChild(img);
  slot.appendChild(wrap);
  let az = startAz;
  const elev = 0;
  const t0 = performance.now();
  let first = true;
  function nearest(a) {
    let best = views[0], score = 1e9;
    for (const v of views) {
      const da = Math.abs(((v.azimuth - a + 540) % 360) - 180);
      const de = Math.abs((v.elevation || 0) - elev);
      const s = da + de * 2;
      if (s < score) { score = s; best = v; }
    }
    return best;
  }
  function show(a) {
    az = ((a % 360) + 360) % 360;
    const v = nearest(az);
    if (img.dataset.src !== v.src) {
      img.dataset.src = v.src;
      img.onload = () => {
        if (first) {
          first = false;
          recordMetric(key, { timeToVisibleMs: Math.round(performance.now() - t0) });
        }
      };
      img.src = v.src;
    }
  }
  show(az);
  let dragging = false, lastX = 0;
  wrap.addEventListener("pointerdown", e => { dragging = true; lastX = e.clientX; wrap.setPointerCapture(e.pointerId); });
  wrap.addEventListener("pointermove", e => {
    if (!dragging) return;
    const dx = e.clientX - lastX; lastX = e.clientX;
    show(az - dx * 0.45);
  });
  wrap.addEventListener("pointerup", () => dragging = false);
  return { setAz: show, getAz: () => az };
}

const metricsLog = {};
function recordMetric(key, extra) {
  metricsLog[key] = { ...(metricsLog[key] || {}), ...extra, at: new Date().toISOString() };
  renderMetrics();
}

function renderMetrics() {
  const fp = OBJ.storageFootprint || {};
  const lines = [
    "Fair comparison notes (no silent winner):",
    "- AR: Direct 3D may offer Scene Viewer / Quick Look via model-viewer; image sets have no equivalent AR (capability difference).",
    "- Intermediate angles: Direct 3D continuous; image sets snap to nearest captured azimuth.",
    "",
    "Storage footprint (server-reported):",
    "  original GLB:  " + fmt(fp.originalGlbBytes),
    "  optimized GLB: " + fmt(fp.optimizedGlbBytes),
    "  mobile GLB:    " + fmt(fp.mobileGlbBytes),
    "  16-view set:   " + fmt(fp.views16Bytes),
    "  72-view set:   " + fmt(fp.views72Bytes),
    "",
    "Client timings (this browser session):",
    JSON.stringify(metricsLog, null, 2),
  ];
  document.getElementById("metrics").textContent = lines.join("\\n");
}
function fmt(n) {
  if (n == null) return "n/a";
  if (n < 1024) return n + " B";
  if (n < 1024*1024) return (n/1024).toFixed(1) + " KB";
  return (n/1024/1024).toFixed(2) + " MB";
}

async function measureDownload(url, label) {
  const t0 = performance.now();
  const res = await fetch(url, { cache: "no-store" });
  const buf = await res.arrayBuffer();
  recordMetric(label, {
    downloadMs: Math.round(performance.now() - t0),
    bytes: buf.byteLength,
  });
}

async function render() {
  const side = document.getElementById("sideBySide").checked && matchMedia("(min-width:900px)").matches;
  const grid = document.getElementById("grid");
  grid.classList.toggle("side", side);
  document.getElementById("paneB").hidden = !side;

  const slotA = document.getElementById("slotA");
  const slotB = document.getElementById("slotB");
  const labelA = document.getElementById("labelA");
  const labelB = document.getElementById("labelB");

  const mobile = BASE + "/api/objects/" + ID + "/model/optimized-mobile.glb";

  async function fill(slot, labelEl, m) {
    labelEl.textContent = m;
    if (m === "direct3d") {
      await measureDownload(mobile, "direct3d_download");
      mountMV(slot, mobile);
    } else if (m === "views16") {
      if (!views16.length) views16 = await loadViewManifest("16");
      if (views16[0]) await measureDownload(views16[0].src, "views16_first");
      mountSpin(slot, views16, "views16");
    } else {
      if (!views72.length) views72 = await loadViewManifest("72");
      if (views72[0]) await measureDownload(views72[0].src, "views72_first");
      mountSpin(slot, views72, "views72");
    }
  }

  await fill(slotA, labelA, mode);
  if (side) {
    const other = mode === "direct3d" ? "views16" : "direct3d";
    await fill(slotB, labelB, other);
  }
  renderMetrics();
}

document.getElementById("modes").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-mode]");
  if (!btn) return;
  mode = btn.dataset.mode;
  for (const b of document.querySelectorAll(".modes button")) b.classList.toggle("active", b === btn);
  // Keep start angle synchronized when switching modes
  render();
});
document.getElementById("sideBySide").addEventListener("change", render);

render();
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
