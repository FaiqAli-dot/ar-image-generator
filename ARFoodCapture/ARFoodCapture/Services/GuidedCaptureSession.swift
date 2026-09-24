import Foundation
import UIKit
import Combine

/// Guided capture session for **phone-stationary + object-on-turntable** workflow.
///
/// Azimuth stored on each frame is **object orientation** (from `ObjectRotationProviding`),
/// never phone yaw. CoreMotion still supplies elevation coaching and phone-stability gates.
@MainActor
final class GuidedCaptureSession: ObservableObject {
    @Published var pass: CapturePass = .horizontal
    @Published var capturedSlots: Set<Int> = []
    @Published var frames: [RawCaptureFrame] = []
    @Published var isCapturing = false
    @Published var isAutoArmed = false
    @Published var lastMessage: String = "Keep phone still — rotate the object slowly ↻"
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

    /// Next uncaptured slot ahead of the current **object** azimuth (rotate forward on the ring).
    var nextTargetSlot: Int? {
        let captured = capturedSlotsForCurrentPass
        guard captured.count < CaptureConstants.viewsPerPass else { return nil }
        let step = CaptureConstants.azimuthStepDegrees
        let current = Int((objectAzimuthDegrees / step).rounded()) % CaptureConstants.viewsPerPass
        for offset in 0..<CaptureConstants.viewsPerPass {
            let slot = (current + offset) % CaptureConstants.viewsPerPass
            if !captured.contains(slot) { return slot }
        }
        return nil
    }

    /// Signed object-azimuth delta to the next target (−180…180). Positive = rotate object clockwise (RIGHT / ↻).
    var azimuthDeltaToNextTarget: Double? {
        guard let target = nextTargetSlot else { return nil }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        var delta = CapturedView.normalizeAzimuth(targetAz - objectAzimuthDegrees)
        if delta > 180 { delta -= 360 }
        return delta
    }

    /// Elevation error vs the soft band for the current pass (degrees). Positive = need to raise/tilt down more.
    var elevationErrorDegrees: Double {
        let elev = motion.elevationDegrees
        switch pass {
        case .horizontal:
            if elev > 12 { return 12 - elev } // negative → lower
            if elev < -8 { return -8 - elev } // positive → raise a bit
            return 0
        case .elevated:
            if elev < 8 { return 8 - elev } // positive → raise
            if elev > 28 { return 28 - elev } // negative → lower
            let ideal = pass.targetElevationDegrees
            let soft = elev - ideal
            if abs(soft) < 6 { return 0 }
            return -soft
        }
    }

    /// 0 = far off (red), 1 = capture-ready (green). Object azimuth + elevation + phone stability.
    var alignmentScore: Double {
        guard isAutoArmed, nextTargetSlot != nil else { return 0 }
        let azErr = abs(azimuthDeltaToNextTarget ?? 180)
        let azScore = max(0, min(1, 1 - (azErr - CaptureConstants.azimuthCaptureTolerance) / 45))
        let elevScore = elevationAlignmentScore
        let stabilityScore = motion.isPhoneStable ? 1.0 : 0.25
        return min(azScore, elevScore, stabilityScore)
    }

    /// True when auto-capture gates for the next target would succeed.
    var isCaptureAligned: Bool {
        guard isAutoArmed, let target = nextTargetSlot else { return false }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        return rotation.isAligned(to: targetAz)
            && elevationBlockMessage() == nil
            && motion.isPhoneStable
    }

    var orbitGuidance: CaptureOrbitGuidance {
        guard let delta = azimuthDeltaToNextTarget else { return .hold }
        if abs(delta) <= CaptureConstants.azimuthCaptureTolerance { return .hold }
        return delta > 0 ? .right : .left
    }

    var elevationGuidance: CaptureElevationGuidance {
        let err = elevationErrorDegrees
        if abs(err) < 1.5 { return .hold }
        return err > 0 ? .raise : .lower
    }

    /// Short arrow hint: which way to rotate the object toward the next empty tick.
    var nextTargetDirectionHint: String? {
        guard nextTargetSlot != nil else { return nil }
        if !motion.isPhoneStable {
            return "PHONE MOVING — keep still"
        }
        if isCaptureAligned {
            return "READY TO CAPTURE — hold still"
        }
        var parts: [String] = []
        if let delta = azimuthDeltaToNextTarget, abs(delta) > CaptureConstants.azimuthCaptureTolerance {
            let amount = Int(abs(delta).rounded())
            switch orbitGuidance {
            case .left: parts.append("Rotate object ↺ \(amount)° more")
            case .right: parts.append("Rotate object ↻ \(amount)° more")
            case .hold: break
            }
        }
        switch elevationGuidance {
        case .raise: parts.append(pass == .elevated ? "Raise / tilt down" : "Raise slightly")
        case .lower: parts.append("Lower phone")
        case .hold: break
        }
        if parts.isEmpty { return "Keep food centered" }
        return parts.joined(separator: " · ")
    }

    var phoneStabilityLabel: String {
        motion.isPhoneStable ? "Phone stable ✓" : "PHONE MOVING — keep still"
    }

    private var elevationAlignmentScore: Double {
        let elev = motion.elevationDegrees
        switch pass {
        case .horizontal:
            if elev <= 12 && elev >= -8 { return 1 }
            if elev > 12 { return max(0, 1 - (elev - 12) / 22) }
            return max(0, 1 - ((-8) - elev) / 22)
        case .elevated:
            if elev >= 8 && elev <= 28 {
                let drift = abs(elev - pass.targetElevationDegrees)
                return max(0.55, 1 - drift / 30)
            }
            if elev < 8 { return max(0, elev / 8) }
            return max(0, 1 - (elev - 28) / 20)
        }
    }

    func prepare() async {
        await camera.configure()
        camera.onVideoFrame = { [weak self] buffer, timestamp in
            self?.rotation.ingestVideoFrame(buffer, timestamp: timestamp)
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
            ? "Keep phone still — rotate the object slowly ↻"
            : "Raise / tilt once, then keep phone still and rotate again ↻"
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

        // Never auto-capture while the phone is moving significantly.
        guard motion.isPhoneStable else { return }

        let step = CaptureConstants.azimuthStepDegrees
        let slot = Int((rotation.nearestCaptureSlot(step: step) / step).rounded()) % CaptureConstants.viewsPerPass
        let elev = pass.targetElevationDegrees
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else { return }
        guard rotation.isAligned(to: Double(slot) * step) else { return }

        if let block = elevationBlockMessage() {
            lastMessage = block
            return
        }

        Task { await captureCurrent(slot: slot, elevation: elev, key: key, manual: false) }
    }

    /// Reliable MVP fallback: capture the next uncaptured object-orientation slot.
    /// Does not use phone yaw. Still respects phone-stability soft coaching (does not hard-block).
    func captureNearestManually() {
        guard isAutoArmed, !isBusyPhoto, !passComplete else { return }
        guard let slot = nextTargetSlot else {
            lastMessage = "All angles in this pass are captured"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else {
            lastMessage = "This angle is already captured — rotate further"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        if !motion.isPhoneStable {
            lastMessage = "PHONE MOVING — steady the phone, then CAPTURE NEXT"
            holdMessageUntil = Date().addingTimeInterval(1.0)
            return
        }
        if let block = elevationBlockMessage() {
            lastMessage = block
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        Task { await captureCurrent(slot: slot, elevation: pass.targetElevationDegrees, key: key, manual: true) }
    }

    private func elevationBlockMessage() -> String? {
        if pass == .elevated && motion.elevationDegrees < 8 {
            return "Raise phone and look slightly down at the food"
        }
        if pass == .horizontal && motion.elevationDegrees > 12 {
            return "Lower the phone to table height"
        }
        return nil
    }

    private func refreshCoachingMessage() {
        guard Date() > holdMessageUntil, !isBusyPhoto else { return }
        if !motion.isPhoneStable {
            lastMessage = "PHONE MOVING — keep still"
            return
        }
        if let block = elevationBlockMessage() {
            lastMessage = block
            return
        }
        if let hint = nextTargetDirectionHint {
            lastMessage = hint
            return
        }
        lastMessage = pass == .horizontal
            ? "Keep phone still — rotate the object slowly ↻"
            : "Keep phone still — rotate the object ↻"
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
            lastMessage = "Captured \(slot * 10)° — rotate to the next angle"
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
            lastMessage = "Capture failed — try CAPTURE NEXT or keep rotating"
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
