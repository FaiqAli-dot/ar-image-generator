# REA + Luma guided capture research

Sources used: public REA repository docs ([morluto/rea](https://github.com/morluto/rea)), public Luma AI guided-capture walkthroughs (official YouTube “Getting Started with Luma AI: Guided Capture Mode”, Tom’s Guide how-to, SwiftXR public guides). No App Store binary was reverse-engineered. Unverified items are marked **assumption**.

## 1. What REA actually supports

Verified from REA’s public README and docs:

| Target | Support (verified) | Notes for this task |
| --- | --- | --- |
| Android APKs | JADX decompile, class/method inspect, Apktool resources, ADB device ops | Requires caller-supplied JDK/JADX/Apktool |
| Apple apps | **Inventory projection** of IPA/`.app`/ZIP/DMG (paths, hashes, bundle anatomy, dylib resolution) | Does **not** decode Swift/ObjC semantics or claim runtime behavior |
| Native binaries | Hopper / Ghidra / IDA when installed | Needs an authorized binary artifact |
| JS / Electron / websites / .NET / Flutter APK / firmware | Separate adapters | Not applicable to Luma iOS UX |

**Conclusion:** REA does **not** provide a turnkey “analyze this iOS App Store app’s guided capture UX” path. Luma AI’s capture app is publicly described as **iOS-only**; there is no official Android APK to feed into REA’s Android toolchain. Apple inventory tools could list bundle files if we had an authorized IPA, but that would not yield Luma’s capture algorithms or UI logic without native decompilation of proprietary code — which we intentionally did **not** do.

**Did REA help?** Yes for capability verification (avoided a false assumption that REA can inspect Luma’s iOS guided capture). No for extracting Luma internals — research used public UX documentation only.

## 2. Publicly observable Luma guided-capture behaviors

Verified from the official guided-capture walkthrough transcript and consistent secondary tutorials:

1. **Setup / bounding:** User aims crosshairs at object center, taps; moves ~90°; taps again; adjusts a 3D box (rotation dial, height dial, size arrows); confirms.
2. **Spatial loops:** App projects **orbital loops** at multiple heights around the object; user walks each loop while keeping the camera pointed inward.
3. **Reticle feedback:** Aiming reticle turns **orange** when too fast or mis-aimed; **blue** when positioning is good. Auto-capture of frames at “optimal” positions along the path.
4. **Progress:** Completed loops **fade**; user advances to the next elevation layer until loops are done.
5. **Early finish:** Finish may be available before 100% coverage if enough data was collected.
6. **Environment coaching (public tips):** Even lighting, avoid self-shadows, clean lenses, room to orbit; “too close” feedback reported in third-party walkthroughs.
7. **Output path:** Upload for **cloud 3D reconstruction** (photogrammetry / NeRF-class pipeline) — **not** our architecture.

### UX principles we can reuse (without 3D reconstruction)

- Show **where to go next** as a simple spatial target, not a wall of text.
- Use **color-state feedback** for good / adjust / hold.
- Communicate **coverage progress** as sectors/layers that complete and fade.
- Allow **finish when coverage is sufficient**, not only at a fixed photo count.
- Separate **setup** (what is the subject) from **capture** (orbit/rotate through angles).
- Coach **speed and centering**; reject or warn on motion that would blur.

### Not applicable / must not copy

- Projected AR loops in world space and automatic dense video sampling for reconstruction.
- Bounding-box volume for mesh generation.
- Any NeRF / Gaussian / mesh / third-party 3D service.

## 3. Assumptions (unverified)

- Exact internal scoring for “enough data,” blur detection, or loop spacing — **assumption**.
- Whether Luma uses LiDAR, ARKit world maps, or SLAM exclusively — **assumption**; public materials emphasize AR-style loops and reticle feedback.
- Precise number of loops / frames — varies by object size in public guides; not treated as a fixed constant.

## 4. Applicability to AR Food Capture

Our pipeline stores **processed photographic views** (azimuth + elevation + cutout PNG) for view-dependent billboards. Improvements inspired by Luma UX:

| Luma cue | Our adaptation |
| --- | --- |
| Loops / layers | Two elevation passes + named azimuth sectors |
| Reticle color | Existing green alignment frame + clearer next-viewpoint labels |
| Coverage fade | Sector completeness UI; adaptive mode can finish when required sectors are filled |
| Early finish | Adaptive coverage planner with classic 72-shot mode retained |
| Auto optimal capture | Keep CAPTURE NEXT primary (turntable); optional Vision assist unchanged |

No 3D reconstruction was added.
