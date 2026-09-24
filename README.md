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

## How to capture (rotating object — Phase 3)

Phone stays **stationary**; the food rotates on a **turntable / lazy Susan**. Stored azimuth is **object orientation**, not phone yaw. Phone gyro is never used as the object angle.

1. Place food on a turntable with even light; prop the phone ~40–50 cm away with the whole dish in frame, then **freeze** the phone.
2. **Pass 1 (sides):** phone upright at food height. Each step: rotate the **dish** ~10°, tap **CAPTURE NEXT** (primary). Do not walk or spin the phone.
3. **Pass 2 (slightly above):** raise ~15 cm and tilt down a little **once** (~15°) — never a 180° flip — freeze again, then rotate the dish with CAPTURE NEXT through 360°.
4. Green frame = phone still enough to shoot. White needle = object angle. Edge arrows say **DISH** ↻/↺.
5. Optional Vision assist may auto-capture only when the phone is still and Vision is confident. CAPTURE NEXT always works and does not wait on phone yaw.
6. Vision is **not** fed while the phone is moving (so spinning the phone cannot fake object rotation).

Elevation coaching is soft only. DEMO BURGER, processing, upload, and photographic AR are unchanged in pipeline; AR billboards are upright + cutout-centered on the placement point.

### Mac / iPhone retest (after UX + placement fix)

1. `git checkout` this branch → `open ARFoodCapture/ARFoodCapture.xcodeproj` → run on physical iPhone
2. **DEMO BURGER** → VIEW IN AR → tap to place: food should be **right-side-up** and sitting on the tap point (not floating offset / inverted)
3. CAPTURE NEW FOOD → instructions must say phone frozen / dish rotates / CAPTURE NEXT primary
4. Lazy Susan capture Pass 1: freeze phone, rotate dish, CAPTURE NEXT ×36 — must work **without** spinning the phone
5. Pass 2: small raise + slight tilt only; CAPTURE NEXT still works if tilt is imperfect
6. Process → place new object in AR: upright + centered like DEMO
7. Optional: long-press `n / 72` debug — phone yaw must not equal object angle; spinning phone must not advance Vision delta

### Honest limitations

- Vision rotation assist is **approximate** and secondary; CAPTURE NEXT is the reliable path.
- Phone stability is a practical CoreMotion heuristic, not a tripod lock.
- `MotorizedRotationProvider` is a **stub only**.
- AR upright fix assumes RealityKit samples CG textures with V inverted vs UIKit; cutout bounds are alpha-based and may be soft on heavy transparency.
- This Linux/cloud agent environment **cannot** run Xcode or a physical iPhone.

## App flow (Phase 2)

1. **Home** — `CAPTURE NEW FOOD` / `MY OBJECTS`
2. Guided capture + Vision processing (MVP capture engine; UX coaching improved)
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
