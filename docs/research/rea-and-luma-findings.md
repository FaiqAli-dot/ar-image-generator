# REA and Luma AI guided-capture findings

Standalone research report for the AR Food Capture guided-capture work.  
**Method:** public documentation, public tutorials/videos, and public repository inspection only. No App Store binary was reverse-engineered, no access controls were bypassed, and no proprietary Luma algorithms were extracted.

Unverified items are labeled **assumption**.

---

## Part 1 — REA (`morluto/rea`)

### What REA is

REA (“Reverse Engineer Anything”) is an open-source local analysis toolkit that exposes reverse-engineering workflows to coding agents via MCP and a CLI (`rea-agents` / `rea`). Analysis is intended to run locally and return findings with evidence and limitations.

Primary sources:

- Repository: https://github.com/morluto/rea
- README (raw): https://raw.githubusercontent.com/morluto/rea/main/README.md
- Website: https://rea.tools/
- npm package: https://www.npmjs.com/package/rea-agents
- Skill description: https://github.com/morluto/rea/blob/main/skill-src/reverse-engineer-anything/SKILL.md

### What REA supports (verified from public docs)

| Target | What REA returns (public claim) | Required tools / adapters |
| --- | --- | --- |
| Native binaries | Pseudocode, assembly, strings, symbols, calls/references | Hopper, Ghidra, or IDA (caller-supplied; setup may optionally install Hopper with approval) |
| Offline ELF layout / diagnostics | Sections, symbols, static mitigation candidates | Caller-supplied pwntools on Linux x64 (for some lanes) |
| Go / Rust binaries | Embedded build metadata, crate graphs (static) | Built-in static inspection for supported formats |
| WASM | Validation, sections, WAT forms | Caller-supplied WABT |
| EVM bytecode | Dispatch selectors, inferred arguments | Local carrier on Linux x64 |
| SQLite DBs | Schema + selected rows | Local DB/WAL; Node version constraints |
| JavaScript / Electron | Modules, imports, source maps, routes, IPC relationships | Node.js + npm (no native decompiler required) |
| Websites | Page structure, scripts, network observations, screenshots | Chrome-family browser |
| Saved network captures | Requests/responses from HAR/SAZ; mitmproxy on Linux | Caller-supplied tools as documented |
| .NET assemblies | Metadata, CIL, declared native deps | Static only; no extra engine |
| Android APKs | Manifest, classes, decompiled methods, references | Headless JADX + full JDK (caller-supplied) |
| Android devices | Packages, logs, dumps, pulls, screenshots | Caller-supplied `adb` |
| Android resources | Decoded manifest/strings via Apktool | Caller-supplied Apktool launcher |
| Flutter apps (APK) | Dart snapshot hash, engine library digests | Static APK parsing |
| JEB projects | Engine-backed units / pseudo-code | Caller-started JEB MCP |
| Firmware | Regions, extraction, native handoffs | Binwalk / Unblob on Linux |
| Packet / signal recordings | Protocol summaries, decoder annotations | tshark / sigrok as documented |
| Packages & Apple apps | File inventories, digests, plists, **Apple bundle anatomy**, dylib resolution | Inventory + Apple projection tools; optional `inspect_plist` / `inspect_signature` |
| Process behavior | PTY capture / run comparisons | Linux/macOS native PTY |

Runtime note from REA’s own skill: use REA for shipped binaries/packages/runtime evidence; for ordinary analysis of a complete source repository, prefer normal repository tools.

Android docs (examples):

- https://github.com/morluto/rea/blob/main/docs/android-analysis.md
- https://github.com/morluto/rea/blob/main/docs/apktool-resource-analysis.md
- Public guide: https://rea-reverse.com/en/android-apk-analysis-rea/

Apple inventory docs:

- https://raw.githubusercontent.com/morluto/rea/main/docs/apple-application-analysis.md

### Required host / toolchain (high level)

- Node.js 22.x (≥22.19), 24.x (≥24.11), or 26+ plus npm (per README).
- Adapters are **bring-your-own** for most deep analysis engines (JADX/JDK, Apktool, Hopper/Ghidra/IDA, adb, browser, etc.). REA does not silently install those prerequisites.
- Setup path advertised publicly: `npx rea-agents setup` (registers MCP + workflow instructions for supported agents).

### Could REA inspect anything Luma-related?

| Approach | Feasible with REA? | Why |
| --- | --- | --- |
| Analyze Luma as an Android APK | **No (for official app)** | Public materials describe Luma 3D Capture as **iOS-only** with no official Android app (e.g. SwiftXR guide: https://guide.swiftxr.io/3d-content-creation/3d-scanning-capture/luma-ai). REA’s strongest app decompile path is Android/JADX. |
| Inventory an authorized IPA / `.app` | **Partially, if we had a lawful artifact** | REA’s Apple projection can list paths, hashes, bundle anatomy, dylib edges. It does **not** decode Swift/ObjC semantics or claim observed runtime capture behavior. |
| Decompile Luma’s native capture logic | **Only with authorized binary + Hopper/Ghidra/IDA** | That would be proprietary reverse engineering of Luma internals. We did **not** obtain or analyze any Luma binary. |
| Observe Luma UX via REA browser tools | **Not applicable** | Guided capture is a native iPhone camera/AR flow, not a website feature we can drive here. |

**Conclusion:** For this task, REA could **not** legitimately deliver Luma’s guided-capture algorithms or UI implementation details. The correct research path was public observation and documentation.

### What REA actually contributed

1. **Capability verification** — Confirmed REA’s real adapters and limits, so we did not incorrectly assume “REA can reverse Luma’s iOS capture.”
2. **Scope discipline** — Clarified that Apple support is inventory/anatomy-oriented unless a native decompiler provider and authorized binary are present.
3. **No Luma internals** — Zero Luma capture code, scoring functions, or proprietary loop math came from REA.

REA’s contribution was **negative evidence / tooling honesty**, not a Luma feature dump.

---

## Part 2 — Luma AI guided object capture (publicly observable)

### Sources (legitimate / public)

1. Official walkthrough video — *Getting Started with Luma AI: Guided Capture Mode*  
   https://www.youtube.com/watch?v=JXb_a3ZIGnI
2. Tom’s Guide how-to — *This free AI camera app turns your iPhone into a 3D capture device*  
   https://www.tomsguide.com/how-to/how-to-take-3d-captures-smartphone-luma-ai
3. SwiftXR documentation — Luma AI capture → publish pipeline  
   https://guide.swiftxr.io/3d-content-creation/3d-scanning-capture/luma-ai
4. SwiftXR blog overview of Luma 3D Capture (secondary)  
   https://home.swiftxr.io/blog/luma-ai-3d-capture-the-complete-guide-to-scanning-exporting-and-publishing-3d-models-in-2026
5. Public video summary mirrors (secondary; used only where consistent with #1)  
   e.g. https://gist.ly/youtube-summarizer/mastering-luma-ai-creating-your-first-luma-capture

### Verified capture behaviors

From the official guided-capture walkthrough (and consistent secondary guides):

1. **Environment prep** — Well-lit space; room to move around the object; avoid casting your own shadow; clean lenses.
2. **Object definition** — Aim crosshairs at object center → tap; move about **90°** around the object → tap again.
3. **Bounding box adjustment** — Bottom dial rotates the box; side dial sets height above ground; blue arrows resize; user confirms when the box roughly encloses the subject.
4. **Projected orbital loops** — Capture shows **loops** around the object at multiple heights; these visualize where the phone should travel.
5. **Inward aiming aids** — Reticle + inward lines coach the camera to point toward the center of the scene/object.
6. **Automatic capture along the path** — As the user moves slowly around a loop, Luma captures data from “optimal” positions (video/frame sampling for reconstruction — not our photo-slot model).
7. **Reticle color feedback** — **Orange** when too fast or looking the wrong way; **blue** when positioning is good.
8. **Layer progress** — Completing a loop makes it **fade**; user advances to the next elevation layer.
9. **Early finish** — Finish may be available before 100% coverage if enough data was collected.
10. **Distance coaching (third-party consistent report)** — Tom’s Guide describes feedback when too close (reticle/warning to move away) and teal/purple path cues for height/distance/angle.
11. **Upload / cloud processing** — After capture, data is uploaded for Luma’s **3D reconstruction** pipeline (photogrammetry / NeRF-class output, exportable assets). This is Luma’s product goal, not ours.

### UX principles extracted (product-level, not internals)

| Principle | Why it helps operators |
| --- | --- |
| Separate setup from capture | Bounding/subject selection first reduces “what am I scanning?” confusion |
| Show the next place to be | Loops/targets beat long instructional paragraphs mid-capture |
| Color-state feedback | Instant good / adjust / hold without reading |
| Coverage as completable layers | Progress is spatial, not only “photo 37/72” |
| Allow “good enough” finish | Avoids forcing unreachable angles |
| Coach motion quality | Speed/aim warnings reduce blur and gaps |
| Keep subject centered | Inward aiming is the recurring rule |

### What we are adopting — and how

Our product stores **processed photographic views** (azimuth + elevation + transparent PNG) for view-dependent AR billboards. We adopt Luma **UX principles**, not Luma’s reconstruction stack.

| Luma cue (verified) | Adopted? | How we map it |
| --- | --- | --- |
| Clear next spatial target | **Yes** | Named viewpoints: Front / Front-right / Right / … plus side vs slightly-above band |
| Color-state readiness | **Yes** | Existing green alignment frame (phone still + soft elevation); coaching tint |
| Multi-height coverage layers | **Yes** | Pass 1 sides + Pass 2 slight elevation (already in product); sector UI for missing coverage |
| Coverage progress / fade metaphor | **Yes (adapted)** | Sector completeness + missing-sector labels; adaptive mode can finish when required sectors are filled |
| Early finish when enough data | **Yes (adapted)** | `CaptureSequenceMode.adaptiveCoverage` (8×2 required); Classic 72 retained for A/B |
| Warn on bad motion / aim | **Yes (adapted)** | Per-photo blur / luma / near-duplicate checks; reject does not commit the slot |
| Keep subject centered | **Yes (soft)** | Framing instruction when object-in-frame is not reliably measurable |
| Recovery from interruption | **Yes (our addition inspired by “don’t restart for small mistakes”)** | Pause/resume snapshot, retake, clear progress |

### What we are not adopting — and why

| Luma behavior / tech | Adopted? | Why not |
| --- | --- | --- |
| World-projected AR orbital loops while walking around | **No** | Our capture model is **phone-stationary + turntable** (Phase 3); walking orbit would conflict with object-azimuth semantics |
| Dense automatic video sampling for reconstruction | **No** | We need discrete ordered photographic views for billboard switching, not a reconstruction dataset |
| Bounding box for mesh volume | **No** | We do not generate meshes; scale is a simple width-cm input |
| Cloud NeRF / photogrammetry / Gaussian splats / third-party 3D | **No** | Explicit product constraint: photographic AR only |
| Finish driven by proprietary “enough data for a scene” scorer | **No** | We use explicit sector completeness we can test; no invented fake precision |
| LiDAR / world-map distance meters presented as truth | **No** | We lack a reliable object-distance signal in the turntable setup; prior motion-energy distance was de-emphasized as untrustworthy |

### Unverified items (**assumptions**)

These were **not** established from public materials and must not be treated as facts:

1. **Assumption:** Exact internal scoring for “enough data,” loop spacing, or auto-shutter optimality.
2. **Assumption:** Whether Luma primarily uses LiDAR, ARKit world tracking, visual SLAM, or a hybrid for loop projection.
3. **Assumption:** Exact blur / exposure / duplicate detectors inside Luma.
4. **Assumption:** Fixed loop count or fixed frame count (public guides imply it varies with object size / coverage).
5. **Assumption:** Any proprietary thresholds that turn the reticle orange vs blue beyond the publicly stated causes (too fast / wrong aim vs good pose).
6. **Assumption:** Server-side reconstruction model family and export pipeline internals beyond “upload for 3D processing.”

---

## Bottom line

- **REA:** Powerful multi-target reverse-engineering MCP/CLI; **not** a shortcut to Luma’s iOS guided-capture implementation. Contribution here = verifying that limitation.
- **Luma (public UX):** Strong operator guidance pattern — setup → spatial targets → color feedback → layered coverage → optional early finish.
- **Our product:** Reuses those **UX principles** inside a turntable, photo-slot, photographic-AR pipeline; rejects reconstruction tech and fake precision.

Related implementation notes: [`docs/guided-capture-improvements.md`](../guided-capture-improvements.md).
