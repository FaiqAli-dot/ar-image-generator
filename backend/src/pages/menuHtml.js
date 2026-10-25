/**
 * Customer QR menu page — model-viewer when a 3D asset exists;
 * photographic / deep-link fallback otherwise.
 * Google <model-viewer> chosen: AR modes (Scene Viewer / Quick Look),
 * built-in framing, meshopt decoder, poster, camera controls — without
 * custom Three.js scene code. No accounts/payments.
 */

export function menuHtml({ obj, urls, base }) {
  const hasModel = Boolean(obj.model3d?.optimizedGlb || obj.model3d?.mobileGlb);
  const hasViews = Array.isArray(obj.views) && obj.views.length > 0;
  const publishedDefault = obj.publishedDefault || (hasModel ? "direct3d" : "photographic");
  const mobileUrl = hasModel
    ? `${base}/api/objects/${obj.id}/model/optimized-mobile.glb`
    : "";
  const hqUrl = hasModel ? `${base}/api/objects/${obj.id}/model/optimized.glb` : "";
  const poster =
    obj.views?.[0]?.image != null
      ? `${base}/api/objects/${obj.id}/images/${encodeURIComponent(obj.views[0].image)}`
      : `${base}/api/objects/${obj.id}/thumbnail`;
  const thumbUrl = `${base}/api/objects/${obj.id}/thumbnail`;

  const title = escapeHtml(obj.name || "Dish");
  const desc = escapeHtml(obj.description || obj.notes || "");
  const width = Number(obj.widthCm) || 12;

  const preferDirect = publishedDefault === "direct3d" && hasModel;
  const imageViewsJson = JSON.stringify(
    (obj.views || []).map((v) => ({
      azimuth: v.azimuth,
      elevation: v.elevation,
      src: `${base}/api/objects/${obj.id}/images/${encodeURIComponent(v.image)}`,
    }))
  );

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <title>${title} · Menu</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;700&family=Source+Sans+3:wght@400;600&display=swap" rel="stylesheet" />
  <script type="module" src="https://ajax.googleapis.com/ajax/libs/model-viewer/4.0.0/model-viewer.min.js"></script>
  <style>
    :root {
      --bg0: #1a1410;
      --bg1: #2c2118;
      --ink: #f7f0e6;
      --muted: #c4b5a4;
      --accent: #e8a045;
      --line: rgba(247,240,230,0.12);
    }
    * { box-sizing: border-box; }
    html, body { margin:0; min-height:100%; background:
      radial-gradient(900px 500px at 10% -10%, #3d2a1a 0%, transparent 55%),
      radial-gradient(700px 400px at 100% 20%, #1e2a22 0%, transparent 50%),
      linear-gradient(165deg, var(--bg1), var(--bg0));
      color: var(--ink); font-family: "Source Sans 3", system-ui, sans-serif; }
    .shell { max-width: 720px; margin: 0 auto; padding: 20px 18px 48px; }
    header.brand { margin-bottom: 8px; }
    .brand-mark { font-family: Fraunces, Georgia, serif; font-weight: 700; font-size: clamp(2rem, 7vw, 2.75rem);
      letter-spacing: 0.02em; line-height: 1.05; margin: 0; }
    .sub { color: var(--muted); margin: 10px 0 0; font-size: 1.05rem; max-width: 36ch; }
    .viewer-wrap { margin-top: 22px; position: relative; width: 100%;
      aspect-ratio: 1 / 1.05; max-height: 72vh; border-radius: 0;
      background:
        linear-gradient(180deg, rgba(255,255,255,0.04), transparent 40%),
        repeating-linear-gradient(-12deg, transparent, transparent 11px, rgba(255,255,255,0.015) 11px, rgba(255,255,255,0.015) 12px);
      border-top: 1px solid var(--line); border-bottom: 1px solid var(--line);
      overflow: hidden; }
    model-viewer { width: 100%; height: 100%; --poster-color: transparent; background: transparent; }
    .photo-stage { width:100%; height:100%; display:flex; align-items:center; justify-content:center; touch-action: none; }
    .photo-stage img { max-width: 92%; max-height: 92%; object-fit: contain; user-select:none; pointer-events:none;
      filter: drop-shadow(0 18px 28px rgba(0,0,0,0.45)); transition: opacity 120ms ease; }
    .meta-row { display:flex; flex-wrap:wrap; gap:12px 20px; align-items:baseline; margin-top: 18px; }
    .width { font-variant-numeric: tabular-nums; color: var(--muted); }
    .actions { display:flex; flex-wrap:wrap; gap:10px; margin-top: 18px; }
    button, a.btn { appearance:none; border:0; cursor:pointer; font: inherit; font-weight:600;
      padding: 12px 18px; border-radius: 10px; text-decoration:none; color: #1a120a;
      background: linear-gradient(135deg, #f0c27a, var(--accent)); }
    button.ghost, a.ghost { background: transparent; color: var(--ink); border: 1px solid var(--line); }
    .hint { margin-top: 14px; font-size: 0.85rem; color: var(--muted); }
    .err { color: #ffb4a8; margin-top: 12px; }
    .sr-only { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); }
    @media (prefers-reduced-motion: reduce) {
      .photo-stage img { transition: none; }
      model-viewer { --progress-bar-color: var(--accent); }
    }
    @media (orientation: landscape) and (max-height: 520px) {
      .shell { display:grid; grid-template-columns: 1fr 1.1fr; gap: 16px; align-items:center; max-width: 960px; }
      .viewer-wrap { margin-top: 0; max-height: 85vh; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header class="brand">
      <h1 class="brand-mark">${title}</h1>
      ${desc ? `<p class="sub">${desc}</p>` : `<p class="sub">Turn the dish with your finger. Camera is only used if you start AR.</p>`}
    </header>

    <div class="viewer-wrap" id="stage">
      ${
        preferDirect
          ? `<model-viewer
              id="mv"
              src="${escapeHtml(mobileUrl)}"
              ${hqUrl ? `data-hq="${escapeHtml(hqUrl)}"` : ""}
              poster="${escapeHtml(poster)}"
              alt="${title}"
              shadow-intensity="0.6"
              exposure="1.05"
              environment-image="neutral"
              interaction-prompt="auto"
              camera-controls
              touch-action="pan-y"
              min-camera-orbit="auto 5deg auto"
              max-camera-orbit="auto 85deg auto"
              min-field-of-view="18deg"
              max-field-of-view="45deg"
              camera-orbit="0deg 65deg 105%"
              field-of-view="30deg"
              auto-rotate-delay="999999"
              ar
              ar-modes="webxr scene-viewer quick-look"
              loading="lazy"
            >
              <div slot="poster" class="sr-only">Loading 3D dish…</div>
              <button slot="ar-button" class="btn" id="arBtn" style="position:absolute;left:12px;bottom:12px;">View in AR</button>
            </model-viewer>`
          : hasViews
            ? `<div class="photo-stage" id="photoStage"><img id="photoImg" alt="${title}" src="${escapeHtml(poster)}" /></div>`
            : `<div class="photo-stage"><p class="err">No 3D or photo views for this item yet.</p></div>`
      }
    </div>

    <div class="meta-row">
      <span class="width">${width} cm wide</span>
      <span class="width">${hasModel ? "3D model" : hasViews ? `${obj.viewCount || obj.views.length} views` : "—"}</span>
    </div>

    <div class="actions">
      ${hasModel && !preferDirect ? `<button type="button" id="show3d">Show 3D</button>` : ""}
      ${hasViews && preferDirect ? `<button type="button" class="ghost" id="showPhotos">Show photo spin</button>` : ""}
      <a class="ghost btn" href="${escapeHtml(urls.deepLink)}">Open in iPhone app</a>
    </div>
    <p class="hint" id="arHint">AR uses Scene Viewer (Android) or Quick Look (iOS) via model-viewer when the device supports it. Unsupported browsers keep the interactive 3D view. Camera permission is requested only when you tap View in AR — not to open this menu.</p>
    <p class="err" id="err" hidden></p>
  </div>
  <script>
    const VIEWS = ${imageViewsJson};
    const HAS_MODEL = ${hasModel ? "true" : "false"};
    const MOBILE_URL = ${JSON.stringify(mobileUrl)};
    const HQ_URL = ${JSON.stringify(hqUrl)};
    const TITLE = ${JSON.stringify(obj.name || "Dish")};
    const POSTER = ${JSON.stringify(poster)};

    // Photo spin: nearest azimuth by drag (consistent with comparison UI)
    (function photoSpin() {
      const stage = document.getElementById("photoStage");
      const img = document.getElementById("photoImg");
      if (!stage || !img || !VIEWS.length) return;
      let az = 0;
      const elev = VIEWS.some(v => v.elevation >= 10) ? 15 : 0;
      function nearest(a, e) {
        let best = VIEWS[0], bestScore = 1e9;
        for (const v of VIEWS) {
          let da = Math.abs(((v.azimuth - a + 540) % 360) - 180);
          const de = Math.abs((v.elevation || 0) - e) * 2;
          const score = da + de;
          if (score < bestScore) { bestScore = score; best = v; }
        }
        return best;
      }
      function show(a) {
        az = ((a % 360) + 360) % 360;
        const v = nearest(az, elev);
        if (img.dataset.src !== v.src) {
          img.dataset.src = v.src;
          img.src = v.src;
        }
      }
      show(0);
      let dragging = false, lastX = 0;
      const onDown = (x) => { dragging = true; lastX = x; };
      const onMove = (x) => {
        if (!dragging) return;
        const dx = x - lastX;
        lastX = x;
        show(az - dx * 0.45);
      };
      const onUp = () => { dragging = false; };
      stage.addEventListener("pointerdown", (e) => { stage.setPointerCapture(e.pointerId); onDown(e.clientX); });
      stage.addEventListener("pointermove", (e) => onMove(e.clientX));
      stage.addEventListener("pointerup", onUp);
      stage.addEventListener("pointercancel", onUp);
    })();

    function mountModelViewer() {
      const stage = document.getElementById("stage");
      if (!HAS_MODEL || !stage) return;
      stage.innerHTML = "";
      const mv = document.createElement("model-viewer");
      mv.id = "mv";
      mv.src = MOBILE_URL || HQ_URL;
      mv.setAttribute("poster", POSTER);
      mv.setAttribute("alt", TITLE);
      mv.setAttribute("shadow-intensity", "0.6");
      mv.setAttribute("exposure", "1.05");
      mv.setAttribute("environment-image", "neutral");
      mv.setAttribute("camera-controls", "");
      mv.setAttribute("touch-action", "pan-y");
      mv.setAttribute("min-camera-orbit", "auto 5deg auto");
      mv.setAttribute("max-camera-orbit", "auto 85deg auto");
      mv.setAttribute("camera-orbit", "0deg 65deg 105%");
      mv.setAttribute("field-of-view", "30deg");
      mv.setAttribute("ar", "");
      mv.setAttribute("ar-modes", "webxr scene-viewer quick-look");
      mv.setAttribute("loading", "eager");
      const arBtn = document.createElement("button");
      arBtn.slot = "ar-button";
      arBtn.className = "btn";
      arBtn.textContent = "View in AR";
      arBtn.style.cssText = "position:absolute;left:12px;bottom:12px;";
      mv.appendChild(arBtn);
      stage.appendChild(mv);
      mv.addEventListener("error", () => {
        const err = document.getElementById("err");
        err.hidden = false;
        err.textContent = "Could not load the 3D model. Photo views or the iPhone app still work if available.";
      });
      // Pause rendering when tab hidden
      document.addEventListener("visibilitychange", () => {
        if (document.hidden) mv.removeAttribute("camera-controls");
        else mv.setAttribute("camera-controls", "");
      });
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        mv.removeAttribute("auto-rotate");
      }
    }

    document.getElementById("show3d")?.addEventListener("click", mountModelViewer);
    document.getElementById("showPhotos")?.addEventListener("click", () => {
      location.reload();
    });

    const mv = document.getElementById("mv");
    if (mv) {
      mv.addEventListener("error", () => {
        const err = document.getElementById("err");
        err.hidden = false;
        err.textContent = "Could not load the 3D model.";
      });
      document.addEventListener("visibilitychange", () => {
        if (document.hidden) mv.pause?.();
      });
    }
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
