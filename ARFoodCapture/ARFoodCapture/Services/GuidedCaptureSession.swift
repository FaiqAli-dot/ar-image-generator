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

    /// Short arrow hint: which way to turn toward the next empty tick.
    var nextTargetDirectionHint: String? {
        guard let target = nextTargetSlot else { return nil }
        let targetAz = Double(target) * CaptureConstants.azimuthStepDegrees
        var delta = CapturedView.normalizeAzimuth(targetAz - motion.azimuthDegrees)
        if delta > 180 { delta -= 360 }
        if abs(delta) <= CaptureConstants.azimuthCaptureTolerance {
            return "Hold steady — capturing this angle"
        }
        return delta > 0 ? "Turn right toward the bright tick →" : "← Turn left toward the bright tick"
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
        if let hint = nextTargetDirectionHint, hint.hasPrefix("Hold") {
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
