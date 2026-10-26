/** Owner workflow UI — same Express app (no disconnected SPA). */

export function ownerHtml({ base }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Owner · GLB import</title>
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&family=Source+Sans+3:wght@400;600&display=swap" rel="stylesheet" />
  <script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/4.0.0/model-viewer.min.js"></script>
  <style>
    :root { --bg:#14110e; --panel:#221c16; --ink:#f6efe6; --muted:#b9a995; --accent:#e2a04a; --line:rgba(255,255,255,.1); }
    *{box-sizing:border-box} body{margin:0;font-family:"Source Sans 3",system-ui,sans-serif;background:
      radial-gradient(800px 400px at 0% 0%, #3a2818, transparent), var(--bg); color:var(--ink);}
    main{max-width:880px;margin:0 auto;padding:28px 18px 64px}
    h1{font-family:Fraunces,Georgia,serif;font-size:clamp(1.8rem,5vw,2.4rem);margin:0 0 8px}
    p{color:var(--muted);line-height:1.45}
    .panel{background:var(--panel);border:1px solid var(--line);padding:18px;margin-top:18px;border-radius:12px}
    label{display:block;font-weight:600;margin:12px 0 6px}
    input,textarea,select{width:100%;padding:10px 12px;border-radius:8px;border:1px solid var(--line);background:#120e0b;color:var(--ink);font:inherit}
    button{margin-top:12px;margin-right:8px;padding:11px 16px;border:0;border-radius:10px;font:inherit;font-weight:600;cursor:pointer;background:linear-gradient(135deg,#f0c27a,var(--accent));color:#1a120a}
    button.ghost{background:transparent;color:var(--ink);border:1px solid var(--line)}
    button:disabled{opacity:.45;cursor:not-allowed}
    .row{display:grid;gap:12px;grid-template-columns:1fr 1fr}
    @media(max-width:700px){.row{grid-template-columns:1fr}}
    model-viewer{width:100%;height:360px;background:transparent}
    .sug{border-top:1px solid var(--line);padding:10px 0}
    .sug label{font-weight:500;display:flex;gap:10px;align-items:flex-start}
    .progress{height:8px;background:#0003;border-radius:99px;overflow:hidden;margin-top:10px}
    .progress>i{display:block;height:100%;width:0;background:var(--accent);transition:width .2s}
    .err{color:#ffb4a8} .ok{color:#b7e3b0}
    .mono{font-family:ui-monospace,monospace;font-size:.85rem;word-break:break-all}
    a{color:var(--accent)}
  </style>
</head>
<body>
<main>
  <h1>GLB import</h1>
  <p>Owner workflow in the existing backend web app. Photo uploads via the iPhone app still work. No Luma API — file stays on this server.</p>

  <section class="panel" id="step-create">
    <h2>1. Item + file</h2>
    <div class="row">
      <div>
        <label for="name">Dish name</label>
        <input id="name" value="Imported dish" />
      </div>
      <div>
        <label for="widthCm">Width (cm)</label>
        <input id="widthCm" type="number" min="1" max="200" value="12" />
      </div>
    </div>
    <label for="description">Description</label>
    <textarea id="description" rows="2" placeholder="Optional menu copy"></textarea>
    <label for="file">Select .glb</label>
    <input id="file" type="file" accept=".glb,model/gltf-binary,application/octet-stream" />
    <div class="progress" hidden id="upProg"><i></i></div>
    <p id="upStatus" class="mono"></p>
    <button id="btnImport" type="button">Validate &amp; preview</button>
  </section>

  <section class="panel" id="step-preview" hidden>
    <h2>2. Preview &amp; cleanup review</h2>
    <p id="inspectSummary"></p>
    <model-viewer id="previewMv" camera-controls touch-action="pan-y" exposure="1.05" shadow-intensity="0.5" environment-image="neutral"></model-viewer>
    <div id="suggestions"></div>
    <button id="btnProcess" type="button">Accept selected &amp; process (optimize + 16/72 renders)</button>
    <button id="btnDiscard" type="button" class="ghost">Discard — keep photo workflow</button>
    <p id="procStatus" class="mono"></p>
  </section>

  <section class="panel" id="step-publish" hidden>
    <h2>3. Publish</h2>
    <p id="procSummary"></p>
    <label for="publishedDefault">Customer menu default</label>
    <select id="publishedDefault">
      <option value="direct3d">Direct 3D (model-viewer)</option>
      <option value="views16">16-view photographic spin</option>
      <option value="views72">72-view photographic spin</option>
    </select>
    <button id="btnPublish" type="button">Publish to menu</button>
    <p id="pubStatus"></p>
    <p id="pubLinks" class="mono"></p>
  </section>
</main>
<script>
const BASE = ${JSON.stringify(base)};
let draftId = null;
let draft = null;

const $ = (id) => document.getElementById(id);

$("btnImport").onclick = async () => {
  const file = $("file").files?.[0];
  if (!file) { $("upStatus").textContent = "Choose a .glb file first."; return; }
  $("btnImport").disabled = true;
  $("upProg").hidden = false;
  $("upProg").querySelector("i").style.width = "15%";
  $("upStatus").textContent = "Uploading & validating…";
  try {
    const fd = new FormData();
    fd.append("glb", file, file.name);
    fd.append("name", $("name").value);
    fd.append("widthCm", $("widthCm").value);
    fd.append("description", $("description").value);
    const res = await fetch(BASE + "/api/glb/import", { method: "POST", body: fd });
    $("upProg").querySelector("i").style.width = "100%";
    const json = await res.json();
    if (!res.ok) throw new Error(json.error || res.statusText);
    draftId = json.draftId;
    draft = json;
    showPreview(json);
    $("upStatus").innerHTML = '<span class="ok">Validated.</span> Draft ' + draftId;
  } catch (e) {
    $("upStatus").innerHTML = '<span class="err">' + e.message + '</span>';
  } finally {
    $("btnImport").disabled = false;
  }
};

function showPreview(d) {
  $("step-preview").hidden = false;
  const ins = d.inspection || {};
  $("inspectSummary").textContent =
    (ins.triangleEstimate||0).toLocaleString() + " tris · " +
    (ins.meshCount||0) + " meshes · " + (ins.materialCount||0) + " materials · " +
    (ins.imageCount||0) + " images · " + ((ins.byteLength||0)/1024/1024).toFixed(2) + " MB";
  $("previewMv").src = BASE + "/api/glb/drafts/" + d.draftId + "/original.glb";
  const box = $("suggestions");
  box.innerHTML = "<h3>Cleanup suggestions (review — nothing auto-deleted)</h3>";
  for (const s of (d.suggestions || [])) {
    const div = document.createElement("div");
    div.className = "sug";
    div.innerHTML = '<label><input type="checkbox" data-sid="' + s.id + '" ' +
      (s.type === "decimation" || s.type === "texture_resize" ? "checked" : "") +
      '/> <span><strong>' + s.type + '</strong> — ' + s.reason + '</span></label>';
    box.appendChild(div);
  }
  if (!(d.suggestions||[]).length) {
    box.innerHTML += "<p>No cleanup suggestions. You can still process for optimize + renders.</p>";
  }
}

$("btnDiscard").onclick = async () => {
  if (!draftId) return;
  await fetch(BASE + "/api/glb/drafts/" + draftId, { method: "DELETE" });
  location.reload();
};

$("btnProcess").onclick = async () => {
  if (!draftId) return;
  $("btnProcess").disabled = true;
  $("procStatus").textContent = "Processing (optimize + render 16 & 72). First run may take a few minutes…";
  const acceptedSuggestionIds = [...document.querySelectorAll("#suggestions input[type=checkbox]:checked")].map(el => el.dataset.sid);
  try {
    const res = await fetch(BASE + "/api/glb/drafts/" + draftId + "/process", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ acceptedSuggestionIds }),
    });
    const json = await res.json();
    if (!res.ok) throw new Error(json.error || res.statusText);
    draft = json;
    $("step-publish").hidden = false;
    const s = json.model3d?.sizes || {};
    const r16 = json.renderSets?.["16"];
    const r72 = json.renderSets?.["72"];
    $("procSummary").textContent =
      "Optimized " + ((s.originalBytes||0)/1024/1024).toFixed(2) + " MB → HQ " +
      ((s.optimizedBytes||0)/1024/1024).toFixed(2) + " MB / mobile " +
      ((s.mobileBytes||0)/1024/1024).toFixed(2) + " MB. Renders: 16=" +
      (r16?.viewCount||0) + " (" + (r16?.engine||"?") + "), 72=" + (r72?.viewCount||0) + ".";
    $("previewMv").src = BASE + "/api/glb/drafts/" + draftId + "/optimized-mobile.glb";
    $("procStatus").innerHTML = '<span class="ok">Ready to publish.</span>';
  } catch (e) {
    $("procStatus").innerHTML = '<span class="err">' + e.message + '</span>';
  } finally {
    $("btnProcess").disabled = false;
  }
};

$("btnPublish").onclick = async () => {
  if (!draftId) return;
  $("btnPublish").disabled = true;
  try {
    const res = await fetch(BASE + "/api/glb/drafts/" + draftId + "/publish", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        publishedDefault: $("publishedDefault").value,
        name: $("name").value,
        widthCm: Number($("widthCm").value),
        description: $("description").value,
      }),
    });
    const json = await res.json();
    if (!res.ok) throw new Error(json.error || res.statusText);
    const menu = json.arUrl;
    const cmp = BASE + "/dev/compare/" + json.id;
    $("pubStatus").innerHTML = '<span class="ok">Published.</span>';
    $("pubLinks").innerHTML =
      'Menu: <a target="_blank" href="' + menu + '">' + menu + '</a><br/>' +
      'Compare (dev): <a target="_blank" href="' + cmp + '">' + cmp + '</a><br/>' +
      'API: <a target="_blank" href="' + json.apiUrl + '">' + json.apiUrl + '</a>';
  } catch (e) {
    $("pubStatus").innerHTML = '<span class="err">' + e.message + '</span>';
  } finally {
    $("btnPublish").disabled = false;
  }
};
</script>
</body>
</html>`;
}
