# Phase 1 audit — Luma GLB import + browser 3D/AR menu

**Repo:** `FaiqAli-dot/ar-image-generator` · audited from latest `main` (PR #6 guided capture **merged**).  
**Date:** 2026-10-25 · environment: Linux cloud agent (no Xcode / no physical iPhone).

## What exists today

| Area | Finding |
| --- | --- |
| **Backend** | Node/Express in `backend/`: `/health`, `POST /api/objects` (multipart PNG views), `GET /api/objects/:id`, images, thumbnail, `/ar/:id`, `/capture`. Filesystem store under `data/objects/{id}/`. |
| **QR / menu** | `/ar/{id}` is an HTML **deep-link landing** (`arfood://object/{id}`) — requires the iOS app. **No browser 3D menu.** No restaurant “menu” multi-item page. |
| **Hosting / storage** | Local disk / Render-style persistent volume (`DATA_DIR`). No S3. No auth on writes. |
| **iOS app** | SwiftUI + AVFoundation + Vision + ARKit/RealityKit. Photographic multi-view billboards only (`kind: photographicARObject`). Guided capture: Classic 72 (36×10° × elev 0/15) + Adaptive 16 (8×45° × 2). |
| **Capture / BG** | On-device Vision cutouts; optional `optional-backend/` rembg helper. Not used for meshes. |
| **Owner UI** | **None on the web.** Upload is iOS `UploadObjectView` → `POST /api/objects`. |
| **3D / GLB** | **None.** README intentionally says browser WebXR was not built. |
| **PR #6 conventions** | Preserve azimuth/elevation slots: classic 10°, adaptive 45° × 2 elevations; metadata elevations **0 / 15** (DemoBurger + `CapturePass`). |

## Constraints for this work

1. **Preserve** photo upload, object IDs, image URLs, QR deep links, DEMO BURGER path.
2. **Add** GLB import + optimize + browser viewer **into** `/ar/{id}` (and owner pages in the same Express app).
3. **Dual output** from one import: optimized GLB + 16-view + 72-view synthetic sets readable by the existing `views[]` shape.
4. **No** Luma API; **no** unpaid/paid external upload service.
5. Blender 4.2 reference scripts are available as uploads; this host has **Chrome** + Playwright, **not** Blender by default → primary renderer = headless Chromium + three.js; optional `BLENDER=` path kept.

## Smallest viable plan

1. Extend storage + `object.json` with optional `model3d` / `renderSets` / `publishedDefault` without breaking photographic objects.
2. Server: validate → inspect → suggest cleanup (review, not auto-delete) → gltf-transform optimize (HQ + mobile) → cache by source hash + config → render 16/72 → write `views` when publishing image default.
3. Owner HTML at `/owner` (create/import/preview/publish) inside Express — not a separate app.
4. Customer `/ar/:id`: model-viewer when a 3D asset exists; else existing photo deep-link / image carousel fallback.
5. Dev `/dev/compare/:id`: Direct 3D / 16 / 72 switch + optional side-by-side.
6. Tests with a tiny generated GLB fixture (no 41 MB Luma file attached).

## Explicit non-goals this pass

- Rewriting the iOS capture engine or photographic AR billboard renderer.
- Claiming device AR / Quick Look verified without a physical device.
- Merging or deploying.
