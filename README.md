# AR Food Capture

Native iPhone MVP that captures a real dish from ~72 guided photo angles, removes backgrounds, and places a **photographic** AR object in the room using multi-view transparent images — not photogrammetry, not `.glb` / `.obj` meshes, not AI 3D.

**Core pipeline:** real photographs → multi-angle views → transparent cutouts → ARKit/RealityKit view switching.

## What’s in this repo

| Path | Purpose |
|------|---------|
| `ARFoodCapture/` | Xcode iOS app (SwiftUI + AVFoundation + Vision + ARKit/RealityKit) |
| `ARFoodCapture/ARFoodCapture/Resources/DemoBurger/` | Preloaded DEMO BURGER (72 transparent views) |
| `optional-backend/` | Optional free-tier rembg API if on-device Vision isn’t enough |

## Requirements

- Mac with **Xcode 15+**
- Physical **iPhone** with A12+ (ARKit) running **iOS 17+**
- Apple ID (free) for device signing, or a paid Developer account

Simulator can open UI screens, but **camera capture + AR placement must be tested on a real iPhone**.

## Open & build

1. Clone this repo and open:

```bash
open ARFoodCapture/ARFoodCapture.xcodeproj
```

2. In Xcode, select the **ARFoodCapture** scheme and your connected iPhone as the run destination.
3. Select the **ARFoodCapture** target → **Signing & Capabilities**:
   - Enable **Automatically manage signing**
   - Choose your **Team** (personal Apple ID is fine)
   - Change **Bundle Identifier** if needed (default `com.arfood.capture`) to something unique
4. On the iPhone: **Settings → Privacy & Security → Developer Mode** (iOS 16+) → On, then reboot if prompted.
5. Trust the developer certificate on device: **Settings → General → VPN & Device Management** → trust your app developer.
6. Press **Run** (▶). Allow Camera and Motion when prompted.

### First-time cable install tips

- Unlock the phone and tap **Trust** when macOS asks.
- If Run fails with a signing error, pick a different bundle ID and re-select your Team.
- If the app won’t launch: Settings → General → VPN & Device Management → Trust.

## App flow

1. **Home** — `CAPTURE NEW FOOD` / `MY OBJECTS` (dark premium UI). Tap version `v1.0.0` five times for **CAPTURE DEBUG**.
2. **Instructions** → **width in cm** + name → guided capture.
3. **Pass 1** — walk around at side height; auto-captures every ~10° (36 views). AE/WB/focus lock after start.
4. **Pass 2** — raise phone slightly; another 36 views (~72 total).
5. Quality warnings (if any) → **PROCESS OBJECT** (Vision background removal → transparent PNGs).
6. **VIEW IN AR** — detect table plane, tap to place, walk around; photographs switch by viewing angle. Rotate / Reset / Remove.
7. **MY OBJECTS** — library with demo + your captures; Share package / Recentre / Delete.

## Photographic AR (not 3D mesh)

The renderer stores transparent images tagged with azimuth + elevation. At runtime it:

1. Measures camera position relative to the placed object
2. Picks the nearest captured view (optional neighbor blend)
3. Draws that photograph on a billboard plane at real-world width (cm → meters)

## Demo object

**DEMO BURGER** ships in the app bundle and is copied into local storage on launch so you can open **MY OBJECTS → DEMO BURGER → VIEW IN AR** immediately without capturing.

## Optional backend

On-device Vision is default. If you need open-source server-side cutouts, see [`optional-backend/README.md`](optional-backend/README.md). Set `BackgroundRemovalAPIBaseURL` in `Info.plist` to your base URL.

## Export package

**Share Package** builds `object.json` + `images/` + `thumbnail/` as a zip for handoff. Same layout is reserved for a future Restaurant → Dish → QR → web viewer path (not built in this MVP).

## Architecture notes

```
Home → Capture (AVFoundation + CoreMotion guide)
     → Process (Vision foreground mask → RGBA PNG)
     → Library (Application Support persistence)
     → AR (ARKit planes + RealityKit UnlitMaterial billboards)
```

`FutureArchitecture` in code documents the restaurant/QR extension point without implementing accounts, payments, or QR.

## Project layout (app)

```
ARFoodCapture/
  ARFoodCaptureApp.swift
  Models/           FoodObject, CapturedView metadata
  Services/         Camera, motion guide, Vision BG removal, pipeline, store, export
  Capture/          Instructions, guided capture UI, processing
  AR/               Photographic view selector + AR screen
  Library/          Home, My Objects, detail
  Debug/            Capture debug sheet
  Theme/            Dark premium styling
  Resources/DemoBurger/
```

## License

MVP sample code for evaluation / prototype use.
