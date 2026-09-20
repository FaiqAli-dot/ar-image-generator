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
    @Published var lastMessage: String = "Align with the next tick"
    @Published var passComplete = false
    @Published var allComplete = false
    @Published var isBusyPhoto = false

    let camera = CameraCaptureController()
    let motion = MotionCaptureGuide()

    private var capturedKeys = Set<String>()
    private var cooldownUntil: Date = .distantPast

    var capturedCount: Int { frames.count }
    var progressText: String { "\(capturedCount) / \(CaptureConstants.totalViews)" }

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
            ? "Walk around the food. Photos capture automatically."
            : "Raise the phone slightly and walk around again."
        if pass == .horizontal {
            camera.lockExposureWhiteBalanceAndFocus()
        }
        // Keep slots for elevated pass separate via key
    }

    func tickAutoCapture() {
        guard isAutoArmed, !isBusyPhoto, !passComplete, Date() > cooldownUntil else { return }
        let step = CaptureConstants.azimuthStepDegrees
        let slot = Int((motion.nearestCaptureSlot(step: step) / step).rounded()) % CaptureConstants.viewsPerPass
        let elev = pass.targetElevationDegrees
        let key = "\(pass.rawValue)-\(slot)"
        guard !capturedKeys.contains(key) else { return }
        guard motion.isAligned(to: Double(slot) * step) else { return }

        // Soft elevation gate for elevated pass
        if pass == .elevated && motion.elevationDegrees < 8 {
            lastMessage = "Tilt / raise phone to look slightly down at the food"
            return
        }
        if pass == .horizontal && motion.elevationDegrees > 12 {
            lastMessage = "Lower phone to side-level for this pass"
            return
        }

        Task { await captureCurrent(slot: slot, elevation: elev, key: key) }
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
            lastMessage = "Captured \(slot * 10)°"
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
            lastMessage = "Capture failed — try again"
        }
    }

    func beginElevatedPass() {
        pass = .elevated
        passComplete = false
        capturedSlots = Set(capturedSlots.filter { $0 >= 100 })
        startPass(.elevated)
    }
}
