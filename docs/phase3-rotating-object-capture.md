# Phase 3 — Rotating Object Capture

## Semantic change

| | Phase 2 / walk-around | Phase 3 |
|---|---|---|
| Phone | Walks around object | Roughly **stationary** |
| Object | Fixed on table | Rotates on **turntable / lazy Susan** |
| Stored `azimuth` | Approximated from **phone yaw** | **Object orientation** from `ObjectRotationProviding` |
| Phone yaw | Treated as orbit angle | Debug + **phone-stability** only — **never** written as object angle |

## Architecture

- `ObjectRotationProviding` — object azimuth API
- `ManualRotationProvider` (**active**) — CAPTURE NEXT anchors + optional Vision optical-flow assist
- `MotorizedRotationProvider` (**stub only**) — no Bluetooth / motor
- `MotionCaptureGuide` — elevation (pitch) + phone stable / moving
- `GuidedCaptureSession` — same ~36+36 / 10° slot FSM; azimuth source swapped
- Photographic pipeline / DEMO BURGER / upload / AR — unchanged

## UI (reuses PR #3 frame / arrows / ring)

- ROTATE OBJECT ↻/↺ (was walk left/right)
- Green frame = **READY TO CAPTURE** (next object orientation)
- **CAPTURE NEXT** fallback
- Current / Next angle · rotate X° more · Phone stable ✓
- Long-press `n / 72` → hidden rotation debug HUD

## Limitations (honest)

Vision assist is approximate; CAPTURE NEXT is the reliable path. No gyro-as-object-angle. Motorized provider not implemented. Device testing requires Mac + iPhone (see README).
