# AR Food Capture

Native iPhone app that captures a dish from ~72 guided photo angles, removes backgrounds, and places a **photographic** AR object using multi-view transparent images — not photogrammetry, not meshes, not AI 3D.

**Phase 2** adds: upload real views → Node backend persistence → permanent `arUrl` → QR → remote load in the same native photographic AR viewer.

## What’s in this repo

| Path | Purpose |
|------|---------|
| `ARFoodCapture/` | Xcode iOS app (SwiftUI + AVFoundation + Vision + ARKit/RealityKit) |
| `ARFoodCapture/.../Resources/DemoBurger/` | Preloaded DEMO BURGER (72 transparent views) |
| `backend/` | **Phase 2** Node/Express object API (real PNG storage + permanent AR URLs) |
| `optional-backend/` | Optional rembg background-removal helper (not the object API) |
| `docs/` | Deploy + iOS API configuration |

## Requirements

- Mac with **Xcode 15+**
- Physical **iPhone** with A12+ (ARKit) running **iOS 17+**
- Node 20+ for the object API (local or deployed)

Simulator can open UI screens, but **camera capture + AR placement must be tested on a real iPhone**.

## Open & build

```bash
open ARFoodCapture/ARFoodCapture.xcodeproj
```

Signing, Developer Mode, and trust steps: see [docs/ios-api-config.md](docs/ios-api-config.md).

### API base URL

Set `ARFoodAPIBaseURL` in `Info.plist` to your backend origin (empty + Debug → `http://127.0.0.1:3000`). Release builds require an explicit HTTPS URL — never ship hardcoded localhost.

## Local object API

```bash
cd backend && npm install && npm start
# tests: npm test
```

Deploy guide: [docs/deploy-backend.md](docs/deploy-backend.md).

## App flow (Phase 2)

1. **Home** — `CAPTURE NEW FOOD` / `MY OBJECTS`
2. Guided capture + Vision processing (unchanged from MVP)
3. **OBJECT READY** → **VIEW IN AR** or **UPLOAD OBJECT** (name, widthCm, description)
4. Upload shows progress → backend stores PNGs → returns permanent `arUrl` → real QR + copy/share
5. **MY OBJECTS** states: `LOCAL` / `UPLOADING` / `REMOTE` / `READY` / `FAILED`
6. Customer scans object QR (`/ar/{id}`) → deep link → native plane place + photographic view switching + `widthCm` scale
7. **DEMO BURGER** still works locally and can be uploaded to prove the remote path
8. Capture QR (`/capture` or `arfood://capture`) opens capture instructions

## Photographic AR (not 3D mesh)

Same MVP renderer: transparent images tagged with azimuth + elevation; billboard plane scaled from `widthCm`. Local and remote objects share `PhotographicImageProviding` → `PhotographicViewSelector`.

## Architecture

```
Home → Capture → Process → Library (local)
                 ↘ Upload → backend /api/objects → arUrl + QR
Customer → HTTPS /ar/{id} → arfood://object/{id} → download cache → same AR viewer
```

## Limitations (honest)

- This Linux/cloud agent environment **cannot** run Xcode, ARKit, or a physical iPhone. Backend tests run here; full capture/AR verification requires a Mac + device.
- Browser WebXR was intentionally **not** built — photographic billboard switching is more reliable in the native app.
- MVP backend has **no auth**; protect write endpoints in production networks if needed.
- Free-tier hosts sleep and need a **persistent disk** for uploads.

## License

MVP sample code for evaluation / prototype use.
