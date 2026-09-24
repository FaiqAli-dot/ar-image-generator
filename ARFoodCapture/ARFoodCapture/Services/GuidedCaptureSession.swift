import Foundation
import UIKit
import Combine

/// Guided capture session for **phone-stationary + object-on-turntable** workflow.
///
/// Azimuth stored on each frame is **object orientation** (from `ObjectRotationProviding`),
/// never phone yaw. CoreMotion supplies soft elevation coaching + phone-stability only.
///
/// Primary path: sequential **CAPTURE NEXT** (always works). Vision assist is optional and
/// only advances when the phone is stable — phone motion must never fake object rotation.
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

    let camera = CameraCaptureController()
    let motion = MotionCaptureGuide()
    /// Active provider: Manual (Vision-assisted). MotorizedRotationProvider remains a stub only.
    let rotation = ManualRotationProvider()
    /// Future extension point — constructed so the type stays linked; not started.
    let motorizedStub = MotorizedRotationProvider()

    private var capturedKeys = Set<String>()
    private var cooldownUntil: Date = .distantPast
    /// Suppresses coaching overwrite right after a successful capture flash.
    private var holdMessageUntil: Date = .distantPast

    var capturedCount: Int { frames.count }
    var progressText: String { "\(capturedCount) / \(CaptureConstants.totalViews)" }

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

    /// Next uncaptured slot in order (0→35). Sequential turntable UX — do not hunt via phone yaw.
    var nextTargetSlot: Int? {
        let captured = capturedSlotsForCurrentPass
        guard captured.count < CaptureConstants.viewsPerPass else { return nil }
        for slot in 0..<CaptureConstants.viewsPerPass {
            if !captured.contains(slot) { return slot }
        }
        return nil
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
            // Modest look-down band — not a flip. Ideal ~15°.
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
        guard isAutoArmed, nextTargetSlot != nil else { return 0 }
        let elevScore = elevationAlignmentScore
        let stabilityScore = motion.isPhoneStable ? 1.0 : 0.2
        return min(elevScore, stabilityScore)
    }

    /// Ready for the primary path: CAPTURE NEXT (phone still + soft elevation OK).
    var isCaptureAligned: Bool {
        guard isAutoArmed, nextTargetSlot != nil else { return false }
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
        guard nextTargetSlot != nil else { return .hold }
        if isVisionAutoReady { return .hold }
        return .right
    }

    var elevationGuidance: CaptureElevationGuidance {
        // Only nudge when clearly out of a soft band — never demand a 180° flip.
        let err = elevationErrorDegrees
        if abs(err) < 2.5 { return .hold }
        return err > 0 ? .raise : .lower
    }

    var nextTargetDirectionHint: String? {
        guard let target = nextTargetSlot else { return nil }
        if !motion.isPhoneStable {
            return "Do NOT rotate the phone — hold it still"
        }
        if isVisionAutoReady {
            return "READY — auto-capturing this dish angle"
        }
        if isCaptureAligned {
            return "READY — tap CAPTURE NEXT (or rotate dish ↻ ~10°)"
        }
        var parts: [String] = ["Rotate the DISH ↻ — not the phone"]
        if pass == .elevated, elevationGuidance == .raise {
            parts.append("tilt down a little once")
        } else if elevationGuidance == .lower {
            parts.append("lower phone slightly")
        }
        parts.append("then CAPTURE NEXT → \(target * 10)°")
        return parts.joined(separator: " · ")
    }

    var phoneStabilityLabel: String {
        motion.isPhoneStable ? "Phone still ✓ — rotate the dish only" : "PHONE MOVING — freeze the phone"
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

    func prepare() async {
        await camera.configure()
        camera.onVideoFrame = { [weak self] buffer, timestamp in
            guard let self else { return }
            // Critical: never feed Vision while the phone is moving — that taught “spin phone.”
            guard self.motion.isPhoneStable else { return }
            self.rotation.ingestVideoFrame(buffer, timestamp: timestamp)
        }
        camera.start()
        motion.start()
        motion.resetOrbitReference()
        rotation.start()
        rotation.resetObjectReference()
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
        isAutoArmed = true
        lastMessage = pass == .horizontal
            ? "PHONE STILL — rotate the DISH ↻, then tap CAPTURE NEXT"
            : "Raise ~15 cm + slight tilt down ONCE, freeze phone, rotate DISH ↻, CAPTURE NEXT"
        holdMessageUntil = .distantPast
        rotation.resetObjectReference()
        if pass == .horizontal {
            camera.lockExposureWhiteBalanceAndFocus()
        }
    }

    func tickAutoCapture() {
        guard isAutoArmed, !passComplete else { return }
        refreshCoachingMessage()
        guard !isBusyPhoto, Date() > cooldownUntil else { return }

        // Secondary path only: Vision must be confident AND phone still.
        // Never auto-fire from phone yaw.
        guard isVisionAutoReady, let slot = nextTargetSlot else { return }
        let elev = pass.targetElevationDegrees
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else { return }

        Task { await captureCurrent(slot: slot, elevation: elev, key: key, manual: false) }
    }

    /// Primary capture path: next sequential object-orientation slot.
    /// Never blocked by Vision, phone yaw, elevation soft-gates, or brief hand tremor.
    func captureNearestManually() {
        guard isAutoArmed, !isBusyPhoto, !passComplete else { return }
        guard let slot = nextTargetSlot else {
            lastMessage = "All angles in this pass are captured"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else {
            lastMessage = "This angle is already captured — rotate the dish further"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        // Soft coaching only — still capture.
        if !motion.isPhoneStable {
            lastMessage = "Capturing — try to keep the phone still next time"
            holdMessageUntil = Date().addingTimeInterval(0.6)
        } else if let warn = elevationSoftWarning() {
            lastMessage = warn
            holdMessageUntil = Date().addingTimeInterval(0.6)
        }
        Task { await captureCurrent(slot: slot, elevation: pass.targetElevationDegrees, key: key, manual: true) }
    }

    /// Soft coaching strings only — CAPTURE NEXT ignores these.
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
        guard Date() > holdMessageUntil, !isBusyPhoto else { return }
        if !motion.isPhoneStable {
            lastMessage = "Do NOT spin the phone — hold still and rotate the DISH"
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
            capturedSlots.insert(slot + pass.rawValue * 100)
            cooldownUntil = Date().addingTimeInterval(0.35)
            if manual {
                rotation.noteManualAdvance(toAzimuth: azimuth)
            } else {
                rotation.didCapture(atAzimuth: azimuth)
            }
            lastMessage = "Captured \(slot * 10)° — rotate DISH ↻ ~10°, tap CAPTURE NEXT"
            holdMessageUntil = Date().addingTimeInterval(0.9)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            let passCount = frames.filter { abs($0.elevation - elevation) < 1 }.count
            if passCount >= CaptureConstants.viewsPerPass {
                passComplete = true
                isAutoArmed = false
                if pass == .elevated {
                    allComplete = true
                    lastMessage = "72 / 72 CAPTURE COMPLETE"
                } else {
                    lastMessage = "SIDE VIEW COMPLETE"
                }
            }
        } catch {
            lastMessage = "Capture failed — tap CAPTURE NEXT again"
            holdMessageUntil = Date().addingTimeInterval(1.5)
        }
    }

    func beginElevatedPass() {
        pass = .elevated
        passComplete = false
        capturedSlots = Set(capturedSlots.filter { $0 >= 100 })
        startPass(.elevated)
    }
}

enum CaptureOrbitGuidance {
    case left, right, hold
}

enum CaptureElevationGuidance {
    case raise, lower, hold
}
