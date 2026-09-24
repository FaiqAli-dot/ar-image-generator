import Foundation
import UIKit
import Combine

@MainActor
final class GuidedCaptureSession: ObservableObject {
    @Published var pass: CapturePass = .horizontal
    @Published var capturedSlots: Set<Int> = []
    @Published var frames: [RawCaptureFrame] = []
    @Published var isCapturing = false
    @Published var isAutoArmed = false
    @Published var lastMessage: String = "Walk slowly around the food →"
    @Published var passComplete = false
    @Published var allComplete = false
    @Published var isBusyPhoto = false

    let camera = CameraCaptureController()
    let motion = MotionCaptureGuide()

    private var capturedKeys = Set<String>()
    private var cooldownUntil: Date = .distantPast
    /// Suppresses coaching overwrite right after a successful capture flash.
    private var holdMessageUntil: Date = .distantPast

    var capturedCount: Int { frames.count }
    var progressText: String { "\(capturedCount) / \(CaptureConstants.totalViews)" }

    /// Slots captured in the active pass (0…35).
    var capturedSlotsForCurrentPass: Set<Int> {
        let offset = pass.rawValue * 100
        return Set(capturedSlots.compactMap { slot in
            let v = slot - offset
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })
    }

    /// Next uncaptured slot ahead of the current azimuth (walking forward on the ring).
    var nextTargetSlot: Int? {
        let captured = capturedSlotsForCurrentPass
        guard captured.count < CaptureConstants.viewsPerPass else { return nil }
        let step = CaptureConstants.azimuthStepDegrees
        let current = Int((motion.azimuthDegrees / step).rounded()) % CaptureConstants.viewsPerPass
        for offset in 0..<CaptureConstants.viewsPerPass {
            let slot = (current + offset) % CaptureConstants.viewsPerPass
            if !captured.contains(slot) { return slot }
        }
        return nil
    }

    /// Signed azimuth delta to the next target (−180…180). Positive = turn right / walk clockwise.
    var azimuthDeltaToNextTarget: Double? {
        guard let target = nextTargetSlot else { return nil }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        var delta = CapturedView.normalizeAzimuth(targetAz - motion.azimuthDegrees)
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

    /// 0 = far off (red), 1 = capture-ready (green). Uses azimuth + elevation vs next target.
    var alignmentScore: Double {
        guard isAutoArmed, nextTargetSlot != nil else { return 0 }
        let azErr = abs(azimuthDeltaToNextTarget ?? 180)
        // Within capture tolerance → full credit; falls to 0 by ~50°.
        let azScore = max(0, min(1, 1 - (azErr - CaptureConstants.azimuthCaptureTolerance) / 45))
        let elevScore = elevationAlignmentScore
        return min(azScore, elevScore)
    }

    /// True when auto-capture gates for the next target would succeed (azimuth + elevation).
    var isCaptureAligned: Bool {
        guard isAutoArmed, let target = nextTargetSlot else { return false }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        return motion.isAligned(to: targetAz) && elevationBlockMessage() == nil
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

    /// Short arrow hint: which way to turn toward the next empty tick.
    var nextTargetDirectionHint: String? {
        guard nextTargetSlot != nil else { return nil }
        if isCaptureAligned {
            return "Hold steady — capturing this angle"
        }
        var parts: [String] = []
        switch orbitGuidance {
        case .left: parts.append("Orbit left ←")
        case .right: parts.append("Orbit right →")
        case .hold: break
        }
        switch elevationGuidance {
        case .raise: parts.append(pass == .elevated ? "Raise / tilt down" : "Raise slightly")
        case .lower: parts.append("Lower phone")
        case .hold: break
        }
        if parts.isEmpty { return "Keep food centered" }
        return parts.joined(separator: " · ")
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
        camera.start()
        motion.start()
        motion.resetOrbitReference()
    }

    func teardown() {
        camera.stop()
        motion.stop()
        isAutoArmed = false
    }

    func startPass(_ pass: CapturePass) {
        self.pass = pass
        passComplete = false
        isAutoArmed = true
        lastMessage = pass == .horizontal
            ? "Walk slowly around the food →"
            : "Raise phone, look slightly down, walk the circle again →"
        holdMessageUntil = .distantPast
        if pass == .horizontal {
            camera.lockExposureWhiteBalanceAndFocus()
        }
    }

    func tickAutoCapture() {
        guard isAutoArmed, !passComplete else { return }
        refreshCoachingMessage()
        guard !isBusyPhoto, Date() > cooldownUntil else { return }

        let step = CaptureConstants.azimuthStepDegrees
        let slot = Int((motion.nearestCaptureSlot(step: step) / step).rounded()) % CaptureConstants.viewsPerPass
        let elev = pass.targetElevationDegrees
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else { return }
        guard motion.isAligned(to: Double(slot) * step) else { return }

        if let block = elevationBlockMessage() {
            lastMessage = block
            return
        }

        Task { await captureCurrent(slot: slot, elevation: elev, key: key) }
    }

    /// Manual fallback: capture the nearest uncaptured slot using the same photo path.
    func captureNearestManually() {
        guard isAutoArmed, !isBusyPhoto, !passComplete else { return }
        let step = CaptureConstants.azimuthStepDegrees
        let nearest = Int((motion.nearestCaptureSlot(step: step) / step).rounded()) % CaptureConstants.viewsPerPass
        let slot = capturedSlotsForCurrentPass.contains(nearest)
            ? (nextTargetSlot ?? nearest)
            : nearest
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else {
            lastMessage = "This angle is already captured — keep walking"
            holdMessageUntil = Date().addingTimeInterval(1.2)
            return
        }
        Task { await captureCurrent(slot: slot, elevation: pass.targetElevationDegrees, key: key) }
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
        if let block = elevationBlockMessage() {
            lastMessage = block
            return
        }
        if let hint = nextTargetDirectionHint {
            lastMessage = hint
            return
        }
        lastMessage = pass == .horizontal
            ? "Walk slowly around the food →"
            : "Walk slowly — keep looking slightly down →"
    }

    private func captureCurrent(slot: Int, elevation: Double, key: String) async {
        isBusyPhoto = true
        defer { isBusyPhoto = false }
        do {
            let image = try await camera.capturePhoto()
            let frame = RawCaptureFrame(
                image: image,
                azimuth: Double(slot) * CaptureConstants.azimuthStepDegrees,
                elevation: elevation,
                distance: motion.estimatedDistanceMeters,
                capturedAt: Date()
            )
            frames.append(frame)
            capturedKeys.insert(key)
            capturedSlots.insert(slot + pass.rawValue * 100)
            cooldownUntil = Date().addingTimeInterval(0.35)
            lastMessage = "Captured \(slot * 10)° — keep walking"
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
            lastMessage = "Capture failed — try Capture now or keep aligning"
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
