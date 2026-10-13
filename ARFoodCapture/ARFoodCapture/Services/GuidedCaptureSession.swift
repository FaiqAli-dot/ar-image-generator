import Foundation
import UIKit
import Combine

/// Guided capture session for **phone-stationary + object-on-turntable** workflow.
///
/// Azimuth stored on each frame is **object orientation** (from `ObjectRotationProviding`),
/// never phone yaw. CoreMotion supplies soft elevation coaching + phone-stability only.
///
/// Primary path: sequential **CAPTURE NEXT** (always works for soft elevation). Optional
/// per-photo quality checks can offer retake. Adaptive coverage can finish with fewer than 72
/// photos; classic72 keeps the original full sequence.
@MainActor
final class GuidedCaptureSession: ObservableObject {
    @Published var pass: CapturePass = .horizontal
    @Published var capturedSlots: Set<Int> = []
    @Published var frames: [RawCaptureFrame] = []
    @Published var isCapturing = false
    @Published var isAutoArmed = false
    @Published var lastMessage: String = "PHONE STILL — rotate the DISH ↻, then tap CAPTURE NEXT"
    @Published var passComplete = false
    @Published var allComplete = false
    @Published var isBusyPhoto = false
    @Published var sequenceMode: CaptureSequenceMode = .adaptiveCoverage
    @Published var isPaused = false
    @Published var lastQualityIssue: CaptureQualityIssue?
    @Published var offerRetake = false
    @Published var nextViewpointLabel: String = ""

    let camera = CameraCaptureController()
    let motion = MotionCaptureGuide()
    /// Active provider: Manual (Vision-assisted). MotorizedRotationProvider remains a stub only.
    let rotation = ManualRotationProvider()
    /// Future extension point — constructed so the type stays linked; not started.
    let motorizedStub = MotorizedRotationProvider()

    private var planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
    private var capturedKeys = Set<String>()
    private var slotKeysInOrder: [Int] = []
    private var cooldownUntil: Date = .distantPast
    /// Suppresses coaching overwrite right after a successful capture flash.
    private var holdMessageUntil: Date = .distantPast
    private var lastFingerprint: [UInt8]?
    private var pendingFillViewpoint: CaptureViewpoint?
    private var widthCm: Double = 12
    private var objectName: String = "My Food"
    private var lastCapturedSlotKey: Int?

    var capturedCount: Int { frames.count }

    var progressText: String {
        switch sequenceMode {
        case .classic72:
            return "\(capturedCount) / \(CaptureConstants.totalViews)"
        case .adaptiveCoverage:
            let minT = planner.expectedMinimumTotal
            return "\(capturedCount) / \(minT)+ · sectors"
        }
    }

    var coveredSectorCount: Int {
        planner.coveredSectorIndices(pass: pass, capturedSlots: capturedSlots).count
    }

    var missingSectorsText: String {
        let missing = planner.missingSectorIndices(pass: pass, capturedSlots: capturedSlots)
        if missing.isEmpty { return "All sectors covered for this pass" }
        let names = missing.prefix(3).map { idx -> String in
            let slot = idx * CaptureCoveragePlanner.adaptiveSectorStepSlots
            return ViewpointGuidance.compassName(azimuth: slot * Int(CaptureConstants.azimuthStepDegrees))
        }
        return "Missing: " + names.joined(separator: ", ")
    }

    /// Object orientation from the rotation provider — never phone yaw.
    var objectAzimuthDegrees: Double { rotation.objectAzimuthDegrees }

    /// Slots captured in the active pass (0…35).
    var capturedSlotsForCurrentPass: Set<Int> {
        let offset = pass.rawValue * 100
        return Set(capturedSlots.compactMap { slot in
            let v = slot - offset
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })
    }

    /// Next uncaptured planned viewpoint (required before optional fills).
    var nextTargetSlot: Int? {
        if let fill = pendingFillViewpoint, fill.pass == pass {
            return fill.slot
        }
        return planner.nextViewpoint(pass: pass, capturedSlots: capturedSlots)?.slot
    }

    var nextViewpoint: CaptureViewpoint? {
        if let fill = pendingFillViewpoint, fill.pass == pass { return fill }
        return planner.nextViewpoint(pass: pass, capturedSlots: capturedSlots)
    }

    /// Degrees of dish rotation still needed toward the next sequential slot (for coaching).
    var degreesToNextTarget: Double? {
        guard let target = nextTargetSlot else { return nil }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        var delta = CapturedView.normalizeAzimuth(targetAz - objectAzimuthDegrees)
        if delta > 180 { delta -= 360 }
        return delta
    }

    /// Soft elevation error for coaching only (never blocks CAPTURE NEXT).
    var elevationErrorDegrees: Double {
        let elev = motion.elevationDegrees
        switch pass {
        case .horizontal:
            if elev > 18 { return 18 - elev }
            if elev < -12 { return -12 - elev }
            return 0
        case .elevated:
            if elev < 3 { return 3 - elev }
            if elev > 35 { return 35 - elev }
            let ideal = pass.targetElevationDegrees
            let soft = elev - ideal
            if abs(soft) < 10 { return 0 }
            return -soft
        }
    }

    /// Green frame = phone still enough to shoot with CAPTURE NEXT (does NOT wait on Vision / phone yaw).
    var alignmentScore: Double {
        guard isAutoArmed, !isPaused, nextTargetSlot != nil else { return 0 }
        let elevScore = elevationAlignmentScore
        let stabilityScore = motion.isPhoneStable ? 1.0 : 0.2
        return min(elevScore, stabilityScore)
    }

    /// Ready for the primary path: CAPTURE NEXT (phone still + soft elevation OK).
    var isCaptureAligned: Bool {
        guard isAutoArmed, !isPaused, nextTargetSlot != nil else { return false }
        return motion.isPhoneStable && elevationSoftOK
    }

    /// Optional Vision auto-shutter readiness (secondary). Never uses phone yaw.
    var isVisionAutoReady: Bool {
        guard isCaptureAligned, let target = nextTargetSlot else { return false }
        let quality = rotation.trackingQuality
        guard quality == .medium || quality == .high else { return false }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        return rotation.isAligned(to: targetAz)
    }

    /// Always coach clockwise dish rotation for sequential slots (turntable mental model).
    var orbitGuidance: CaptureOrbitGuidance {
        guard nextTargetSlot != nil, !isPaused else { return .hold }
        if isVisionAutoReady { return .hold }
        return .right
    }

    var elevationGuidance: CaptureElevationGuidance {
        let err = elevationErrorDegrees
        if abs(err) < 2.5 { return .hold }
        return err > 0 ? .raise : .lower
    }

    var nextTargetDirectionHint: String? {
        guard !isPaused else { return CaptureTrackingMessages.backgroundedHint() }
        guard let vp = nextViewpoint else { return nil }
        if camera.permissionDenied {
            return CaptureTrackingMessages.cameraPermissionDenied()
        }
        if !motion.isAvailable {
            return CaptureTrackingMessages.motionUnavailable()
        }
        if !motion.isPhoneStable {
            return CaptureTrackingMessages.phoneMoving()
        }
        if isVisionAutoReady {
            return "READY — auto-capturing \(vp.label)"
        }
        if isCaptureAligned {
            return "READY — \(vp.label) · tap CAPTURE NEXT"
        }
        if let deg = degreesToNextTarget {
            return ViewpointGuidance.moveInstruction(degreesClockwise: deg, viewpoint: vp)
        }
        return "Rotate the DISH ↻ → \(vp.label)"
    }

    var phoneStabilityLabel: String {
        if isPaused { return "Paused — progress saved" }
        return motion.isPhoneStable ? "Phone still ✓ — rotate the dish only" : "PHONE MOVING — freeze the phone"
    }

    private var elevationSoftOK: Bool {
        elevationSoftWarning() == nil
    }

    private var elevationAlignmentScore: Double {
        let elev = motion.elevationDegrees
        switch pass {
        case .horizontal:
            if elev <= 18 && elev >= -12 { return 1 }
            if elev > 18 { return max(0, 1 - (elev - 18) / 25) }
            return max(0, 1 - ((-12) - elev) / 25)
        case .elevated:
            if elev >= 3 && elev <= 35 {
                let drift = abs(elev - pass.targetElevationDegrees)
                return max(0.55, 1 - drift / 40)
            }
            if elev < 3 { return max(0.15, elev / 3) }
            return max(0, 1 - (elev - 35) / 25)
        }
    }

    func configure(mode: CaptureSequenceMode, widthCm: Double, objectName: String) {
        sequenceMode = mode
        planner = CaptureCoveragePlanner(mode: mode)
        self.widthCm = widthCm
        self.objectName = objectName
    }

    func prepare() async {
        await camera.configure()
        if camera.permissionDenied {
            lastMessage = CaptureTrackingMessages.cameraPermissionDenied()
        }
        camera.onVideoFrame = { [weak self] buffer, timestamp in
            guard let self else { return }
            guard self.motion.isPhoneStable, !self.isPaused else { return }
            self.rotation.ingestVideoFrame(buffer, timestamp: timestamp)
        }
        camera.start()
        motion.start()
        motion.resetOrbitReference()
        rotation.start()
        rotation.resetObjectReference()
        if !motion.isAvailable {
            lastMessage = CaptureTrackingMessages.motionUnavailable()
        }
    }

    func teardown() {
        camera.onVideoFrame = nil
        camera.stop()
        motion.stop()
        rotation.stop()
        isAutoArmed = false
    }

    func startPass(_ pass: CapturePass) {
        self.pass = pass
        passComplete = false
        isPaused = false
        isAutoArmed = true
        pendingFillViewpoint = nil
        offerRetake = false
        lastQualityIssue = nil
        if let vp = nextViewpoint {
            nextViewpointLabel = vp.label
            lastMessage = pass == .horizontal
                ? "Next: \(vp.label) — freeze phone, rotate dish, CAPTURE NEXT"
                : "Raise ~15 cm + slight tilt once, freeze, then \(vp.label)"
        } else {
            lastMessage = pass == .horizontal
                ? "PHONE STILL — rotate the DISH ↻, then tap CAPTURE NEXT"
                : "Raise ~15 cm + slight tilt down ONCE, freeze phone, rotate DISH ↻, CAPTURE NEXT"
        }
        holdMessageUntil = .distantPast
        rotation.resetObjectReference()
        if pass == .horizontal {
            camera.lockExposureWhiteBalanceAndFocus()
        }
    }

    func tickAutoCapture() {
        guard isAutoArmed, !passComplete, !isPaused else { return }
        refreshCoachingMessage()
        if let vp = nextViewpoint {
            nextViewpointLabel = vp.label
        }
        guard !isBusyPhoto, Date() > cooldownUntil else { return }
        guard isVisionAutoReady, let slot = nextTargetSlot else { return }
        let elev = pass.targetElevationDegrees
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else { return }
        Task { await captureCurrent(slot: slot, elevation: elev, key: key, manual: false) }
    }

    /// Primary capture path: next planned object-orientation slot.
    func captureNearestManually() {
        guard isAutoArmed, !isBusyPhoto, !passComplete, !isPaused else { return }
        guard let slot = nextTargetSlot else {
            lastMessage = "All planned angles in this pass are captured"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else {
            lastMessage = "This angle is already captured — rotate the dish further"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        if !motion.isPhoneStable {
            lastMessage = "Capturing — try to keep the phone still next time"
            holdMessageUntil = Date().addingTimeInterval(0.6)
        } else if let warn = elevationSoftWarning() {
            lastMessage = warn
            holdMessageUntil = Date().addingTimeInterval(0.6)
        }
        Task { await captureCurrent(slot: slot, elevation: pass.targetElevationDegrees, key: key, manual: true) }
    }

    /// Soft coaching strings only — CAPTURE NEXT ignores these for shutter.
    private func elevationSoftWarning() -> String? {
        let elev = motion.elevationDegrees
        if pass == .elevated && elev < 3 {
            return "Pass 2: raise ~15 cm and tilt down a little (not a flip), then freeze"
        }
        if pass == .horizontal && elev > 18 {
            return "Lower toward table height, then freeze — rotate the dish only"
        }
        if pass == .elevated && elev > 35 {
            return "Too steep — ease tilt back toward ~15°, then freeze"
        }
        return nil
    }

    private func refreshCoachingMessage() {
        guard Date() > holdMessageUntil, !isBusyPhoto, !isPaused else { return }
        if camera.permissionDenied {
            lastMessage = CaptureTrackingMessages.cameraPermissionDenied()
            return
        }
        if !motion.isPhoneStable {
            lastMessage = CaptureTrackingMessages.phoneMoving()
            return
        }
        if let warn = elevationSoftWarning() {
            lastMessage = warn
            return
        }
        if let hint = nextTargetDirectionHint {
            lastMessage = hint
            return
        }
        lastMessage = "PHONE STILL — rotate the DISH ↻, then tap CAPTURE NEXT"
    }

    private func captureCurrent(slot: Int, elevation: Double, key: String, manual: Bool) async {
        isBusyPhoto = true
        defer { isBusyPhoto = false }
        do {
            let image = try await camera.capturePhoto()
            let (decision, _, fingerprint) = CaptureQualityEvaluator.evaluate(
                image: image,
                previousFingerprint: lastFingerprint,
                phoneStable: motion.isPhoneStable
            )

            // Hard rejects: keep shutter available but do not commit the slot.
            if case .reject(let issue) = decision {
                lastQualityIssue = issue
                offerRetake = true
                lastMessage = issue.message
                holdMessageUntil = Date().addingTimeInterval(2.0)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            let azimuth = Double(slot) * CaptureConstants.azimuthStepDegrees
            let frame = RawCaptureFrame(
                image: image,
                azimuth: azimuth,
                elevation: elevation,
                distance: CaptureConstants.recommendedDistanceMeters,
                capturedAt: Date()
            )
            frames.append(frame)
            capturedKeys.insert(key)
            let slotKey = slot + pass.rawValue * 100
            capturedSlots.insert(slotKey)
            slotKeysInOrder.append(slotKey)
            lastCapturedSlotKey = slotKey
            lastFingerprint = fingerprint
            cooldownUntil = Date().addingTimeInterval(0.35)

            if case .warn(let issue) = decision {
                lastQualityIssue = issue
                offerRetake = true
                lastMessage = "Captured \(ViewpointGuidance.label(forSlot: slot, pass: pass)) — \(issue.message)"
            } else {
                lastQualityIssue = nil
                offerRetake = false
                lastMessage = "Captured \(ViewpointGuidance.label(forSlot: slot, pass: pass)) — rotate dish for next"
            }
            holdMessageUntil = Date().addingTimeInterval(0.9)

            if manual {
                rotation.noteManualAdvance(toAzimuth: azimuth)
            } else {
                rotation.didCapture(atAzimuth: azimuth)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // Adaptive: optionally queue a fill after a weak required shot.
            if let fill = planner.shouldRequestFill(
                afterRequiredSlot: slot,
                pass: pass,
                capturedSlots: capturedSlots,
                lastQualityAccepted: decision == .accept
            ) {
                pendingFillViewpoint = fill
            } else if pendingFillViewpoint?.slot == slot {
                pendingFillViewpoint = nil
            } else {
                pendingFillViewpoint = nil
            }

            evaluateCompletion()
            try? persistRecovery(isPaused: false)
        } catch {
            lastMessage = "Capture failed — tap CAPTURE NEXT again"
            holdMessageUntil = Date().addingTimeInterval(1.5)
        }
    }

    private func evaluateCompletion() {
        if planner.isPassComplete(pass: pass, capturedSlots: capturedSlots) {
            // In adaptive mode, skip remaining optional fills once required sectors are done
            // unless a fill was explicitly queued for quality.
            if sequenceMode == .adaptiveCoverage, pendingFillViewpoint == nil {
                passComplete = true
                isAutoArmed = false
                if pass == .elevated {
                    allComplete = true
                    lastMessage = "Coverage complete — \(capturedCount) photos"
                } else {
                    lastMessage = "SIDE COVERAGE COMPLETE"
                }
                return
            }
            if sequenceMode == .classic72 {
                passComplete = true
                isAutoArmed = false
                if pass == .elevated {
                    allComplete = true
                    lastMessage = "72 / 72 CAPTURE COMPLETE"
                } else {
                    lastMessage = "SIDE VIEW COMPLETE"
                }
            }
        }
        if planner.isSessionComplete(capturedSlots: capturedSlots) {
            allComplete = true
            passComplete = true
            isAutoArmed = false
            lastMessage = sequenceMode == .classic72
                ? "72 / 72 CAPTURE COMPLETE"
                : "Coverage complete — \(capturedCount) photos"
        }
    }

    func beginElevatedPass() {
        pass = .elevated
        passComplete = false
        // Keep horizontal slot keys so session completion / recovery stay consistent.
        // The ring UI reads `capturedSlotsForCurrentPass` and only shows this pass.
        pendingFillViewpoint = nil
        startPass(.elevated)
    }

    // MARK: - Recovery

    func retakeLast() {
        guard let key = lastCapturedSlotKey else { return }
        retake(slotKey: key)
    }

    func retake(slotKey: Int) {
        let result = CaptureRetakeLogic.retake(
            slotKey: slotKey,
            frames: frames,
            slotKeysInOrder: slotKeysInOrder
        )
        frames = result.frames
        slotKeysInOrder = result.slotKeys
        capturedSlots = result.capturedSlots
        capturedKeys = Set(slotKeysInOrder.map { key in
            let passIdx = key >= 100 ? 1 : 0
            let slot = key - passIdx * 100
            return "\(passIdx)-\(slot)"
        })
        lastFingerprint = nil
        lastCapturedSlotKey = slotKeysInOrder.last
        passComplete = false
        allComplete = false
        isAutoArmed = true
        offerRetake = false
        lastQualityIssue = nil
        pendingFillViewpoint = nil
        lastMessage = "Retake ready — \(nextViewpoint.map { $0.label } ?? "next angle")"
        holdMessageUntil = Date().addingTimeInterval(1.0)
        try? persistRecovery(isPaused: isPaused)
    }

    func pauseCapture() {
        isPaused = true
        isAutoArmed = false
        lastMessage = CaptureTrackingMessages.backgroundedHint()
        try? persistRecovery(isPaused: true)
    }

    func resumeCapture() {
        isPaused = false
        isAutoArmed = !passComplete && !allComplete
        lastMessage = nextTargetDirectionHint ?? "Resumed — rotate dish, tap CAPTURE NEXT"
        holdMessageUntil = Date().addingTimeInterval(0.8)
    }

    func clearProgress() {
        frames = []
        capturedSlots = []
        capturedKeys = []
        slotKeysInOrder = []
        lastFingerprint = nil
        lastCapturedSlotKey = nil
        pendingFillViewpoint = nil
        passComplete = false
        allComplete = false
        offerRetake = false
        lastQualityIssue = nil
        isPaused = false
        pass = .horizontal
        try? CaptureRecoveryStore.shared.clear()
        lastMessage = "Progress cleared — start Pass 1 when ready"
    }

    @discardableResult
    func restoreIfAvailable() -> Bool {
        guard let snap = try? CaptureRecoveryStore.shared.loadSnapshot() else { return false }
        let loaded = CaptureRecoveryStore.shared.loadFrames(from: snap)
        guard CaptureRetakeLogic.pauseSnapshotValid(
            mode: snap.mode,
            capturedSlots: Set(snap.capturedSlotKeys),
            frameCount: loaded.count
        ) else { return false }

        configure(mode: snap.mode, widthCm: snap.widthCm, objectName: snap.objectName)
        frames = loaded
        slotKeysInOrder = snap.frameRecords.map(\.slotKey)
        capturedSlots = Set(snap.capturedSlotKeys)
        capturedKeys = Set(slotKeysInOrder.map { key in
            let passIdx = key >= 100 ? 1 : 0
            let slot = key - passIdx * 100
            return "\(passIdx)-\(slot)"
        })
        pass = snap.pass
        isPaused = snap.isPaused
        passComplete = planner.isPassComplete(pass: pass, capturedSlots: capturedSlots)
        allComplete = planner.isSessionComplete(capturedSlots: capturedSlots)
        isAutoArmed = !isPaused && !passComplete && !allComplete
        lastMessage = CaptureTrackingMessages.sessionInterrupted()
        return true
    }

    private func persistRecovery(isPaused: Bool) throws {
        try CaptureRecoveryStore.shared.save(
            mode: sequenceMode,
            pass: pass,
            capturedSlots: capturedSlots,
            frames: frames,
            slotKeysInOrder: slotKeysInOrder,
            widthCm: widthCm,
            objectName: objectName,
            isPaused: isPaused
        )
    }
}

enum CaptureOrbitGuidance {
    case left, right, hold
}

enum CaptureElevationGuidance {
    case raise, lower, hold
}
