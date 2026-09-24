# AR Food Capture — MVP Specification

Build a fully working iPhone MVP of an app that captures a real food item from multiple guided camera angles and turns those photographs into a photographic AR object that can be placed in the real world.

## CRITICAL — WHAT THIS APP IS NOT

Do NOT build a conventional 3D scanning / photogrammetry application.

Do NOT create:
- .obj / .fbx / .glb models from photogrammetry
- mesh reconstruction
- polygon/vertex editing
- traditional textured 3D models
- AI-generated 3D objects

Core concept: Capture many photographs of the actual object from controlled viewpoints, remove the background, and use those photographs as the visual representation of the object inside AR. The food itself should remain photographic and realistic.

Purpose: Prove that a restaurant could photograph a dish once and later allow a customer to place that actual dish into their environment through AR.

## Platform

Native iOS application:
- Swift
- SwiftUI
- ARKit
- RealityKit where useful
- AVFoundation / Vision where useful
- Photos framework where useful

Target physical iPhone. Must be installable and runnable on a physical iPhone. Do not build only a simulator prototype.

## Home screen

AR FOOD
[ CAPTURE NEW FOOD ]
[ MY OBJECTS ]

Clean, premium, dark UI.

## Capture flow

CAPTURE NEW FOOD → instructions:
Place the food on a flat surface.
For best results:
• Keep the food still
• Use good lighting
• Keep the camera at a consistent distance
• Make sure the entire food item is visible
[ START CAPTURE ]

## Guided 360° capture

**Phase 3:** Keep the phone roughly stationary; rotate the food on a turntable. Stored azimuth is **object orientation**, not phone yaw.
Guide the user to rotate the object. Do NOT require manual shutter for every photo (CAPTURE NEXT is the reliable fallback).
Optional lightweight Vision optical-flow assist may estimate object rotation; never invent object angle from phone gyro.
Show a circular capture guide (needle = object angle).
Auto-capture when object orientation reaches next capture position (~every 10°) and the phone is stable.
Approximately 36 horizontal viewpoints (one every 10 degrees).

Phone-stability (CoreMotion) blocks auto-capture when the handset is moving significantly. Distance hint is soft only.

## Multiple elevations (2 passes)

Level A — horizontal: Camera ~level with food, 36 images.
Level B — slightly above: Camera slightly upward, another 36 images.
Total ~72 images per food object.

UI:
PASS 1 OF 2 — Keep phone still; rotate object for side views. [ START ]
Then: SIDE VIEW COMPLETE — Raise phone slightly once; rotate object again. [ START TOP PASS ]
Then: 72 / 72 CAPTURE COMPLETE [ PROCESS OBJECT ]

## Image processing pipeline

Captured photograph → Crop/normalize → Background segmentation → Transparent RGBA → Store angle + elevation metadata.

Each image metadata example:
{ "azimuth": 80, "elevation": 0, "image": "view_008.webp" }
{ "azimuth": 80, "elevation": 15, "image": "view_044.webp" }

Also store: alpha mask, capture timestamp, optional camera distance.

## Background removal

Prefer Apple Vision / on-device segmentation.
If not sufficient: simple backend with open-source segmentation (free/cheap tier). Do NOT require a paid AI API unless absolutely necessary.
Final images must have transparency around the food.

## The AR object (CORE)

Create AR representation using captured transparent photographs.
Do NOT replace photographs with textures on a conventional 3D mesh.

Renderer selects photograph(s) corresponding to viewer's current angle.
For angles between captures, interpolate/blend neighboring views if helpful.

Fallback if RealityKit is hard: transparent image planes / billboards switched by camera/object viewing angle. NEVER fall back to photogrammetry mesh.

## AR placement

OBJECT READY [ VIEW IN AR ]
Open camera, detect horizontal plane, show placement indicator, TAP TO PLACE.

## Real-world scale

Ask for food width (cm) during capture. Use to scale AR representation to approximate real size.

## AR interaction

Once placed: rotate, move, scale, remove, place again.
Scaling should initially preserve original real-world scale.
UI: [ ↻ Rotate ] [ Reset ] [ Remove ]

## Viewing from different angles

User physically walks around AR object; app chooses appropriate captured image based on viewpoint. This is NOT a 3D model — illusion from photograph collection.

## Object library

MY OBJECTS — thumbnail, name, date, capture count.
Tap: [ VIEW IN AR ] [ RECENTRE ] [ DELETE ]

## Local storage first

Work offline after processing. Store: metadata, transparent images, angle info, thumbnail. Efficient formats. Don't keep enormous originals after processing.

## Optional backend

Only if on-device background removal insufficient. Deploy to Render/Railway/Fly/Cloudflare/Supabase/Firebase free tier. Provide deployment instructions, env vars, API docs, one-command local dev.

## Demo mode

Preload one DEMO BURGER (or similar) sample object so AR can be tested without capture first.

## Capture quality check

Before processing, check for missing views / lighting issues. Simple warnings. Don't over-engineer.

## Image consistency

Lock exposure, white balance, focus during capture session once object detected.

## UX

Polished commercial prototype: dark/clean, large buttons, smooth transitions, minimal text, progress, loading states. No unnecessary settings.

## Debug mode

Tap app version 5 times → CAPTURE DEBUG screen with image counts, azimuth, elevation, selected view, nearest views, FPS.

## Save / Export

Share Object package: object.json + images/ + thumbnail/

## Future (DO NOT BUILD)

Architect for Restaurant → Dish → AR Object → QR → Customer Web Viewer later. NO subscriptions, payments, accounts, analytics, QR in this MVP.

## Success criteria (physical iPhone)

1. Open app → CAPTURE NEW FOOD
2. Place real food, guided circular capture ~72 photos auto
3. Background removed
4. Photographic AR object created
5. VIEW IN AR
6. Place on real table
7. Walk around — views change with captured photos, looks like real food
8. Approximate real physical size
9. Persist after app reopen

## Deliverables

1. Complete Xcode project
2. Builds successfully
3. Installable on physical iPhone
4–10. Working capture, guided 360, background removal, photo AR, placement, library, demo object
11. README
12–13. Backend + deploy docs if needed
14. Clear iPhone install instructions
15. No fake/placeholder main-flow buttons

Test the complete flow as far as the environment allows. If a feature cannot be exact, closest functional version preserving: REAL PHOTOGRAPHS → MULTI-ANGLE VIEWS → TRANSPARENT OBJECT → AR

## Final product goal

Hand phone to someone: put burger on table → walk around with phone → capture → process → place in AR → walk around AR burger → looks like the actual photographed burger.
