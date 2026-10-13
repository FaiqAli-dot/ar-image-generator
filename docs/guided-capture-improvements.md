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
- Docs: `docs/luma-guided-capture-research.md`, [`docs/research/rea-and-luma-findings.md`](research/rea-and-luma-findings.md), this file

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

---

## 8. KIRI Engine capture research (docs-only follow-up)

**Scope:** Public sources only. This agent did **not** install or manually test the KIRI Engine app.  
**Cross-link:** Luma/REA write-up — [`docs/research/rea-and-luma-findings.md`](research/rea-and-luma-findings.md).  
**Labeling:** each finding is **verified** or **assumption**, with confidence **high / medium / low**.

Official hub: https://www.kiriengine.app/

### 8.1 Android availability and capture modes

| Finding | Status | Confidence | Evidence |
| --- | --- | --- | --- |
| KIRI Engine is marketed for **iPhone, Android, and Web** | verified | high | Site homepage: https://www.kiriengine.app/ |
| Android app is publicly listed on Google Play (`com.kiriengine.app`) | verified | high | https://play.google.com/store/apps/details?id=com.kiriengine.app (listing observed via public page; **not** sideloaded/tested here) |
| **Photo Scan** = photogrammetry from photos (in-app capture or upload) | verified | high | FAQ https://www.kiriengine.app/faq/how-to-capture-with-photo-scan ; explained https://www.kiriengine.app/blog/explained/photo-scan-mode |
| Photo Scan capture is primarily **manual photo** orbit guidance (instructional), not a Luma-style projected loop coach | verified | medium | Tutorials describe “start taking photos… continuously shifting angles” / orbit advice; no official Photo Scan doc of projected orbital loops like Luma |
| **Featureless Object Scan** accepts **video or photos** (upload or in-app); recommended video orbit from ≥3 perspectives | verified | high | FAQ https://www.kiriengine.app/faq/how-to-capture-with-featureless-object-scan ; Play Store lists NSR/NeRF-integrated featureless video path |
| **3D Gaussian Splatting** capture is video-oriented for scenes/reflections | verified | high | Homepage + Play Store feature list |
| **LiDAR Scan** is **iOS LiDAR-device** only (not an Android capture mode) | verified | high | Features page https://www.kiriengine.app/features/photo-scan ; LiDAR FAQ https://www.kiriengine.app/faq/how-to-use-lidar-object-capture |
| Photo Scan recommends ~**70% overlap**, **3 height orbits**, often **50–60+** photos (also “at least 20” in older explained article) | verified | high | Tutorial https://www.kiriengine.app/tutorial/introduction-to-photo-scan ; explained article https://www.kiriengine.app/blog/explained/photo-scan-mode |
| **AR Mode** (Photo Scan, v4.0): each captured photo shown as a **3D camera icon** to track coverage / missing angles | verified | high | https://www.kiriengine.app/blog/kiri-engine-4.0-release |
| AR Mode is **coverage visualization of shots already taken**, not documented as “next target / reticle color / fading loops” | verified | medium | Same 4.0 post wording; absence of Luma-like next-target language in official Photo Scan docs (**not** proof it never exists in UI — **assumption** that undocumented = not the primary Photo Scan coach) |
| Live blur/framing auto-reject during shutter is **not** documented for Photo Scan | assumption | medium | Official quality guidance is instructional (“avoid shaking…”); recovery is delete-before-upload (below). Could exist undocumented — untested |
| Users can **preview and delete** blurry/out-of-focus photos before processing | verified | high | FAQ https://www.kiriengine.app/faq/delete-photos-before-uploading |
| **Auto Object Masking** isolates subject; important when object moved or **turntable** used | verified | high | FAQ https://www.kiriengine.app/faq/what-is-auto-object-masking |
| Official **turntable** workflow: Photo Scan / 3DGS; built-in **timer** auto-shoots; ≥3 full rotations; vary height/distance; enable Auto Object Masking | verified | high | https://www.kiriengine.app/tutorial/how-to-scan-with-a-turntable |
| Advanced camera controls (shutter/EV/etc.) exist for scan quality | verified | medium | Homepage “Adv. Camera Control”; Play Store Pro “Advanced Camera System” — platform/mode matrix not fully specified in fetched pages |
| Adaptive “enough coverage → Finish early” like Luma is **not** documented for Photo Scan | assumption | medium | Docs emphasize more photos / more angles → better mesh; completion is user-ended upload, not a published coverage-% finish gate |
| Exact Android UI parity with iOS for AR Mode / timer / every Pro control | assumption | low | Store + site claim Android support; per-screen parity not verified without device testing |

### 8.2 KIRI vs Luma comparison (cited)

Luma evidence summarized from [`docs/research/rea-and-luma-findings.md`](research/rea-and-luma-findings.md) (public walkthroughs). KIRI from sources above. Neither app was device-tested in this research pass.

| Dimension | KIRI Engine (public) | Luma AI guided capture (public) | Notes / confidence |
| --- | --- | --- | --- |
| **Initial object selection / setup** | Mode pick (Photo / Featureless / 3DGS / LiDAR on capable iOS); Photo Scan = place textured object, good light, walk-around or turntable. Auto Object Masking for subject isolation. LiDAR Object Capture uses on-screen **cubic guide**. | Crosshair taps ~90° apart → adjustable **bounding box** (rotate/height/size) → confirm. | Both verified (high) from official FAQs/tutorials. KIRI Photo Scan setup is lighter/instructional; Luma’s box is more explicit spatial framing. |
| **Camera movement guidance** | Instructional: orbit, shift angles, ~70% overlap. Turntable: timer interval auto-capture. No public Photo Scan doc of projected path loops / orange-blue reticle. | Projected **orbital loops**, inward lines, reticle **orange** (too fast/mis-aimed) vs **blue** (good); auto-capture along path. | Luma verified high (YouTube walkthrough). KIRI “no loop coach” verified medium (docs describe free orbit + AR camera icons, not next-path loops). |
| **Horizontal & vertical coverage** | Explicitly teach **three heights** (top/middle/lower) + many azimuths; turntable: ≥3 rotations + height/distance changes. | Multiple elevation **loops/layers**; complete then fade to next. | Both verified high. KIRI states numeric photo/overlap heuristics more plainly in tutorials. |
| **Capture automation** | Manual shutter and/or **timer** (turntable); video modes for Featureless/3DGS. Upload then cloud process. | Auto-capture while user walks the loop when pose is good. | Both verified high from official tutorials. Different automation: interval timer vs pose-gated path capture. |
| **Blur / framing / movement feedback** | Prep tips: keep object large in frame, in focus, don’t shake. **Post-capture** delete bad frames before upload. Advanced exposure controls marketed. Live reject UI undocumented. | Live reticle color for speed/aim; “too close” reported in third-party guides. | KIRI delete-before-upload verified high. Live KIRI reject = assumption medium (undocumented). Luma live reticle verified high; “too close” medium (secondary). |
| **Coverage visualization & progress** | **AR Mode**: 3D camera icons per shot to see gaps. Photo count / more-is-better messaging. | Loops fade when done; progress is spatial layers; Finish may appear before 100%. | Both verified high for their stated UIs. Different metaphors: shot poses in space (KIRI) vs path layers (Luma). |
| **Recovery / retakes / early completion** | Delete weak photos before process; choose which photos to process (store copy). Early “enough data” finish for Photo Scan not documented. | May Finish before full coverage if enough data. Loop redo = walk remaining loops (internals unknown). | KIRI photo culling verified high. Luma early finish verified high. Neither publishes full retake FSM internals (assumption). |
| **Usability for restaurant staff photographing food** | Photo Scan wants **rich texture**; shiny/uniform food is a known photogrammetry failure mode → Featureless/3DGS paths, but those are **3D reconstruction**, not photo billboards. Turntable + timer is staff-friendly in principle. Learning curve acknowledged in tutorials. | Guided loops reduce “where do I stand?” for walk-around 3D capture; still a reconstruction product, needs space to orbit, not turntable-native in public docs. | Both verified medium for food-specific fit: neither is a restaurant menu-photo product; food texture/specular issues called out more clearly in KIRI failure docs. |

### 8.3 Relevance to our turntable + photo-billboard setup

Our architecture (phone still, dish rotates, ordered transparent views by azimuth/elevation, no mesh) can reuse **interaction principles** only:

| KIRI pattern (public) | Adaptable without 3D? | How it maps to us |
| --- | --- | --- |
| Explicit multi-height orbits (3 bands in tutorials) | Yes (principle) | We already use 2 elevation passes; a third band is optional and only if AR A/B shows benefit |
| ~70% overlap / dense azimuth advice | Partial | Billboard AR needs viewpoint density, not feature-point overlap for SfM; prefer sector completeness over copy-paste “70%” |
| AR Mode camera-icons for **where shots already are** | Yes (principle) | Strengthen our ring/sector “captured vs missing” viz; do **not** require world-tracked AR camera frustums |
| Turntable + **interval timer** | Yes (optional) | Could complement CAPTURE NEXT for motorized/lazy-Susan rhythm; keep manual primary |
| Auto Object Masking when object moves / turntable | Already analogous | We already run Vision background removal in processing; capture-time mask not required for billboards |
| Delete blurry frames before commit/process | Yes | Aligns with our per-photo quality reject + retake; also suggests a **review strip before Process** |
| Advanced EV/shutter controls | Low priority | We already AE/WB/focus lock; manual camera pro controls add staff complexity |
| Featureless / NeRF / 3DGS / LiDAR pipelines | **No** | Out of scope — reconstruction outputs |

### 8.4 Recommendation vs PR #6 implementation

Compare current PR #6 flow (named next viewpoint, sector adaptive + classic 72, per-photo quality, pause/retake/resume) to verified Luma + KIRI findings.

| Problem | Already addressed in PR #6? | Further change worth doing? |
| --- | --- | --- |
| Unclear next useful photo | Yes — Front/Left/… labels | Keep; polish copy only after device A/B |
| Coverage gaps invisible | Partial — sector text + ring | **Worth:** clearer captured-vs-missing sector map (KIRI AR Mode principle) without world AR icons |
| Blurry / bad frames | Partial — live heuristics | **Worth:** optional pre-process **review & discard** strip (KIRI delete-before-upload), especially for adaptive |
| Too many redundant photos | Partial — adaptive 8×2 | Keep Classic 72 for A/B; don’t raise minimum toward KIRI’s 50–60 photogrammetry count |
| Hard recovery | Yes — pause/resume/retake | Keep; add review-strip retake entry if we add gallery |
| Turntable rhythm | CAPTURE NEXT primary | **Optional later:** interval timer (KIRI turntable tip) behind a flag — only if staff testing asks for it |
| Fake precision / 3D | Avoided | Do **not** add loops-in-world, NeRF, 3DGS, or LiDAR mesh paths |

**Do not implement** (no identified UX win for our renderer): copying KIRI photo-count minima, photogrammetry overlap meters as hard gates, Featureless/3DGS modes, LiDAR cubic guides, or Luma walk-around loops.

---

## 9. Decision (KIRI follow-up)

### What KIRI teaches that Luma doesn’t

- **Turntable-native guidance** is first-class in KIRI docs (timer auto-shoot, Auto Object Masking when the dish moves, ≥3 rotations + height changes) — Luma’s public guided mode is walk-around loops.
- **Post-capture photo culling** before processing (delete blurry/out-of-focus frames) is an explicit, staff-simple recovery pattern.
- **Coverage as “where did I already shoot?”** (AR Mode camera icons) complements Luma’s “follow the remaining path” metaphor; for a stationary phone, a 2D sector/ring gap map is the honest analogue.
- Clearer public teaching of **failure modes** (texture/feature points, shiny food-like surfaces) and numeric heuristics (overlap, multi-height, photo counts) — useful as operator education, not as our architecture.

### What neither app establishes (for our product)

- Optimal photo count for **view-dependent billboards** (their optima optimize mesh/NeRF/3DGS, not azimuth-indexed cutouts).
- A verified, open algorithm for live blur/framing thresholds that works on restaurant food.
- That projected AR loops or world-tracked camera icons are necessary when the phone is fixed and the dish rotates.
- Android/iOS UI parity details or proprietary scoring internals (**assumptions** without device testing).

### Improvements worth implementing

1. **Keep** PR #6: named next viewpoint, measurable readiness (phone still), sector adaptive + **Classic 72**, live quality reject/warn, pause/retake/resume.  
2. **Add next (docs-approved, code later):** stronger missing-coverage visualization + optional **review-and-discard** before Process (KIRI-inspired).  
3. **Optional later:** turntable interval timer behind a flag.  
4. **Do not add:** 3D reconstruction modes, walk-around loop projection, photogrammetry “50–60 photo” quotas, or fake distance precision.

No device testing of KIRI or Luma was performed for this write-up; recommendations are principle-level only.
