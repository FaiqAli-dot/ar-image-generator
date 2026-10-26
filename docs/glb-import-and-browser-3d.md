# Luma GLB import, browser 3D/AR menu, dual output

See also: [glb-import-audit.md](./glb-import-audit.md) (Phase 1).

## Owner flow

1. Start backend: `cd backend && npm install && npm start`
2. Open `http://localhost:3000/owner`
3. Name the dish → select `.glb` → **Validate & preview**
4. Review cleanup suggestions (nothing auto-deletes meshes) → **Process**
5. Choose customer default (Direct 3D / 16-view / 72-view) → **Publish**
6. Open menu URL `/ar/{id}` and (dev) compare URL `/dev/compare/{id}`

Original GLB is kept under `data/objects/{id}/models/original.glb` for re-runs. Renders are cached under `data/glb-cache/` keyed by source hash + config.

## Customer menu

`/ar/{id}` serves an in-browser menu page:

- **Direct 3D:** Google `<model-viewer>` (chosen over custom Three.js for AR modes, framing, meshopt decoder, poster, camera limits).
- **Photo spin:** azimuth/elevation nearest-view scrub when published default is 16/72 or when no model.
- **AR:** `ar-modes="webxr scene-viewer quick-look"`. Camera is not required to open the menu. iPhone app deep link remains available.
- **USDZ:** Not generated server-side on Linux. Quick Look may use model-viewer’s client-side path — **not verified on a physical iPhone here**.

## Dual output

One import produces:

| Asset | Path |
| --- | --- |
| Original GLB | `models/original.glb` |
| HQ optimized | `models/optimized.glb` |
| Mobile optimized | `models/optimized-mobile.glb` |
| 16-view set | `renders/views_16/` (45° × elev meta 0/15) |
| 72-view set | `renders/views_72/` (10° × elev meta 0/15) |

Renderer: **headless Chromium + three.js** (Playwright) by default — matches the attached Blender orbit math (1–99% vertex bounds, unlit, transparent). If `BLENDER` points at Blender 4.2+, `backend/scripts/blender/render_views.py` is used instead. Default resolution **512²** (`RENDER_RES`); justified for mobile billboards vs 72×1024 storage cost.

## Dev comparison

`/dev/compare/{id}` — not the customer menu. Switch Direct 3D / 16 / 72 without reimport; optional side-by-side; records download size + time-to-visible in-page. Does not silently pick a winner.

## Honest AR / device matrix (this environment)

| Capability | Status here |
| --- | --- |
| Browser 3D (model-viewer) | Implemented; exercised via HTML + API tests |
| Android Scene Viewer | Wired via model-viewer; **not device-tested** |
| iOS Quick Look / USDZ | No server USDZ; client path untested on device |
| Native iOS photographic AR | Unchanged; **not runnable on Linux** |
| Real Luma ~41 MB GLB | Not attached; use owner UI with your file |

## Env

| Var | Meaning |
| --- | --- |
| `MAX_GLB_BYTES` | Default 80 MB |
| `RENDER_RES` | Square render px (default 512) |
| `BLENDER` | Optional path to Blender binary |
| `DATA_DIR` / `OBJECTS_DIR` | Persistence |
