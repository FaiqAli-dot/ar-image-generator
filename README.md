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

Phone stays roughly **stationary**; the food rotates on a **turntable / lazy Susan**. Stored azimuth is **object orientation**, not phone yaw. Phone gyro is never used as the object angle.

1. Place food on a turntable with even light; prop the phone ~40–50 cm away with the whole dish in frame, then keep it still.
2. **Pass 1 (sides):** phone upright at food height; rotate the object a slow full circle (~36 views at 10°). Ring ticks fill when the frame is green (**READY TO CAPTURE**).
3. **Pass 2 (slightly above):** raise/tilt the phone once, hold still, rotate the object through 360° again.
4. White needle = **object** angle; filled ticks = captured; bright tick = next target. Edge arrows say **ROTATE OBJECT** ↻/↺.
5. Optional lightweight Vision optical-flow assist estimates object rotation for auto-capture. **CAPTURE NEXT** is the reliable manual fallback (does not invent angles from phone yaw).
6. **Phone stable ✓** / **PHONE MOVING** uses CoreMotion so photos don’t fire while the hand-held phone is shaking.

Elevation coaching still uses phone pitch for pass height bands. DEMO BURGER, processing, upload, and photographic AR are unchanged.

### Mac / iPhone test procedure

This Linux cloud environment **cannot** run Xcode or a physical device. On a Mac:

1. `git checkout` this branch → `open ARFoodCapture/ARFoodCapture.xcodeproj`
2. Select a physical iPhone (iOS 17+), set signing team, build & run
3. Confirm **DEMO BURGER** still opens in MY OBJECTS → VIEW IN AR
4. CAPTURE NEW FOOD → instructions mention turntable / rotate object
5. Place a burger (or stand-in) on a lazy Susan; prop phone; Pass 1 rotate 360°; Pass 2 raise once and rotate again
6. Verify ~72 frames process; AR view switching still works; optional upload still works
7. Long-press the `n / 72` progress label during capture to open hidden rotation debug (phone yaw vs object estimate vs Vision quality)
8. Confirm CAPTURE NEXT works with Vision assist disabled/noisy (cover/move object irregularly)

### Honest limitations

- Vision rotation assist is **approximate** (center-crop optical flow) — not a calibrated encoder. Uneven lighting, plain turntables, or motion blur reduce quality; prefer **CAPTURE NEXT**.
- Phone stability is a practical CoreMotion heuristic, not a tripod lock.
- `MotorizedRotationProvider` is a **stub only** — no Bluetooth / motor control in this phase.
- No claim of “gyro senses object angle.”

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
