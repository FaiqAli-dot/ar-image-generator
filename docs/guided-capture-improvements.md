# Guided capture improvements

## 1. Existing capture audit (pre-change, code-backed)

| Area | Observation | Evidence |
| --- | --- | --- |
| Session | Turntable-only FSM; ~36×2 slots; CAPTURE NEXT primary | `GuidedCaptureSession.swift` |
| Motion | Pitch → elevation coaching; yaw is **not** object azimuth; stability gate | `MotionCaptureGuide.swift` |
| Camera | Photo + optional Vision video assist; AE/WB/focus lock | `CameraCaptureController.swift` |
| UI | Ring of 36 ticks, colored frame, dish ↻ arrows; dense duplicate coaching text | `GuidedCaptureView.swift` |
| Quality | Warnings only **after** full session (count / bins / luma / distance proxy) | `ImageProcessingPipeline.qualityWarnings` |
| Recovery | Leaving capture discarded in-progress work; no retake API | No pause/resume store before this change |
| Distance | “Too close/far” from motion-energy proxy — not measurable object distance | `MotionCaptureGuide.estimatedDistanceMeters` |
| Adaptive | Fixed 72 required; no sector completion early finish | `CaptureConstants.totalViews` |
| AR pipeline | Photographic views by azimuth/elevation; no mesh | `PhotographicViewSelector` / `FoodObject` |

Walk-around orbit capture was replaced in Phase 3 by turntable capture (documented in `docs/phase3-rotating-object-capture.md`). This work **preserves** turntable semantics and CAPTURE NEXT.

## 2. Improvements shipped

### A. Clear next-photo guidance
- Named viewpoints: Front / Front-right / Right / … + side vs slightly-above band (`ViewpointGuidance`).
- Large next-label in the live capture UI; move instruction uses dish ↻ degrees.

### B. Real-time guidance
- Kept measurable signals: phone stability (CoreMotion), soft elevation bands, object azimuth from rotation provider.
- Explicitly **does not** pretend object-relative distance/LiDAR precision; framing is a soft instruction.
- Sector / missing-coverage text under the ring.

### C. Per-photo quality checks
- Blur (Laplacian variance proxy), luma dark/bright, near-duplicate fingerprint (`CaptureQualityEvaluator`).
- Reject → do not commit slot; warn → commit but offer retake.
- Framing: instruction only when unreliable.

### D. Adaptive coverage (+ classic 72 flag)
- `CaptureSequenceMode.adaptiveCoverage`: 8 required 45° sectors × 2 elevations (16 min); optional 20° fills when a required shot is weak.
- `CaptureSequenceMode.classic72`: original 36×2 sequence retained for A/B.

### E. Recovery
- Retake last / retake slot; pause/resume; clear progress; disk snapshot via `CaptureRecoveryStore`.
- Permission / motion / interrupt copy via `CaptureTrackingMessages`.

## 3. Architecture / compatibility

- Output remains `RawCaptureFrame` → cutout PNGs → `CapturedView` (azimuth, elevation, image). **No** 3D reconstruction.
- Adaptive objects may have fewer views; `PhotographicViewSelector` already picks nearest azimuth/elevation.
- Saved objects: `schemaVersion` unchanged (1); fewer views are valid photographic objects.
- Upload / QR / library paths untouched.
- Indexing: slot keys still `pass*100 + slot`; recovery persists the same keys.

### Modified / added files
- Added: `CaptureCoveragePlanner.swift`, `CaptureQualityEvaluator.swift`, `CaptureRecoveryStore.swift`
- Updated: `GuidedCaptureSession.swift`, `GuidedCaptureView.swift`, `CaptureInstructionsView.swift`, `ImageProcessingPipeline.swift`, `FoodObjectModels.swift` (intro copy), `HomeView.swift` (`CaptureDraftStore` mode flags)
- Tests: `ARFoodCaptureTests/*`
- Docs: `docs/luma-guided-capture-research.md`, this file

## 4. Build / test results (honest)

Environment: Linux cloud agent **without Xcode / iOS SDK / `xcodebuild` / Swift toolchain**.

| Check | Result |
| --- | --- |
| `xcodebuild` build | **Not run** — no Xcode on this host |
| `xcodebuild test` | **Not run** — no Xcode on this host |
| XCTest sources | Added under `ARFoodCaptureTests` and wired into the Xcode project/scheme |

On a Mac with Xcode 15+:

```bash
cd ARFoodCapture
xcodebuild -scheme ARFoodCapture -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 5. iPhone device test steps

1. Build & run on a physical iPhone (camera + CoreMotion required).
2. Capture → choose **Adaptive coverage** → set scale → start.
3. Pass 1: freeze phone; rotate dish; confirm next labels cycle Front → … → Left; green frame when still.
4. Intentionally shake once → expect blur reject / retake offer.
5. Pause from ⋯ menu; force-quit; relaunch → **Resume saved capture**.
6. Finish Pass 2; process; place in AR; walk around — billboards should switch by viewer azimuth.
7. Repeat with **Classic 72** on the same dish for A/B.

## 6. A/B comparison protocol (no claims without data)

Same dish, lighting, device, operator skill.

| Metric | Classic 72 | Adaptive | Notes |
| --- | --- | --- | --- |
| Wall time (start→process) | | | |
| Photo count | | | |
| Retakes offered / accepted | | | |
| Missing sectors at finish | | | |
| Operator confusion events | | | |
| AR rotation consistency (1–5) | | | Walk 360° around placed object |
| Obvious flicker / wrong side | | | |

Run ≥3 captures per mode. Prefer adaptive only if AR consistency ≥ classic and time/retakes improve. Do **not** claim improvement without filling the table.

## 7. Limitations

- Blur/duplicate heuristics are proxies; may false-positive on uniform sauces or false-negative on motion blur with textured plates.
- No reliable on-device “object fully in frame” detector without heavier Vision segmentation each shutter.
- Adaptive 45° spacing can look steppier in AR than 10° classic — measure in A/B.
- Vision auto-capture remains secondary; CAPTURE NEXT is authoritative.
- Distance too-close/far UI remains de-emphasized (not trustworthy without depth).
