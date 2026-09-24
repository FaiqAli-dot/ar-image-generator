import Foundation
import CoreMotion
import Combine
import UIKit

/// Phone attitude for **elevation coaching** and **phone-stability** only.
///
/// Phase 3 semantic change: phone yaw is NOT object azimuth. Object orientation comes from
/// `ObjectRotationProviding` (ManualRotationProvider / future motorized). `phoneYawDegrees`
/// (also published as `azimuthDegrees` for debug compatibility) is for the hidden rotation
/// debug HUD and stability detection — never write it into CapturedView.azimuth.
@MainActor
final class MotionCaptureGuide: NSObject, ObservableObject {
    /// Phone yaw relative to session reference (debug / stability). NOT object angle.
    @Published var azimuthDegrees: Double = 0
    /// Alias clarity for Phase 3 callers.
    var phoneYawDegrees: Double { azimuthDegrees }
    @Published var elevationDegrees: Double = 0
    @Published var isAvailable = true
    /// True when recent attitude/accel change stays within practical capture tolerance.
    @Published var isPhoneStable = true
    @Published var phoneMotionMagnitude: Double = 0

    private let motion = CMMotionManager()
    private var referenceYaw: Double?
    private var displayLink: CADisplayLink?
    private var baselineUserAcceleration: Double?

    private var lastYaw: Double?
    private var lastPitch: Double?
    private var recentMotionEnergy: Double = 0

    /// Soft distance band (~recommended). Uses motion energy as a proxy when LiDAR is unavailable.
    /// Less meaningful when the phone is intentionally stationary (Phase 3); UI de-emphasizes it.
    @Published var estimatedDistanceMeters: Double = CaptureConstants.recommendedDistanceMeters

    override init() {
        super.init()
    }

    func start() {
        guard motion.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        displayLink?.invalidate()
        displayLink = nil
        referenceYaw = nil
        baselineUserAcceleration = nil
        lastYaw = nil
        lastPitch = nil
        recentMotionEnergy = 0
    }

    /// Resets phone-yaw reference for debug/stability. Does not define object orientation.
    func resetOrbitReference() {
        referenceYaw = nil
        lastYaw = nil
        lastPitch = nil
        recentMotionEnergy = 0
        isPhoneStable = true
    }

    @objc private func tick() {
        guard let dm = motion.deviceMotion else { return }
        // Attitude: pitch ≈ camera elevation; yaw = phone heading only (NOT object azimuth).
        let yaw = dm.attitude.yaw * 180 / .pi
        let pitch = dm.attitude.pitch * 180 / .pi

        if referenceYaw == nil {
            referenceYaw = yaw
        }
        let rel = CapturedView.normalizeAzimuth(yaw - (referenceYaw ?? 0))
        azimuthDegrees = rel
        // Map pitch so holding phone roughly upright → elevation ~0;
        // tilting to look down slightly → positive elevation for top pass.
        elevationDegrees = max(-20, min(45, -pitch))

        let ua = dm.userAcceleration
        let mag = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
        if baselineUserAcceleration == nil { baselineUserAcceleration = mag }

        // Phone stability: attitude deltas + user acceleration (practical tolerance for hand-held).
        var attitudeDelta = 0.0
        if let ly = lastYaw, let lp = lastPitch {
            let dyaw = min(abs(yaw - ly), 360 - abs(yaw - ly))
            let dpitch = abs(pitch - lp)
            attitudeDelta = dyaw + dpitch
        }
        lastYaw = yaw
        lastPitch = pitch

        let frameEnergy = attitudeDelta * 4 + mag * 10
        recentMotionEnergy = recentMotionEnergy * 0.85 + frameEnergy * 0.15
        phoneMotionMagnitude = recentMotionEnergy
        isPhoneStable = recentMotionEnergy < CaptureConstants.phoneStableMotionThreshold

        // Soft hint only — does not block capture. Less useful when phone is stationary.
        let recommended = CaptureConstants.recommendedDistanceMeters
        if mag > 0.45 {
            estimatedDistanceMeters = recommended - CaptureConstants.distanceToleranceMeters * 0.8
        } else if mag < 0.02 {
            estimatedDistanceMeters = recommended + CaptureConstants.distanceToleranceMeters * 0.5
        } else {
            estimatedDistanceMeters = recommended
        }
    }

    func nearestCaptureSlot(step: Double = CaptureConstants.azimuthStepDegrees) -> Double {
        let slot = (azimuthDegrees / step).rounded() * step
        return CapturedView.normalizeAzimuth(slot)
    }

    func isAligned(to targetAzimuth: Double, tolerance: Double = CaptureConstants.azimuthCaptureTolerance) -> Bool {
        angularDistance(azimuthDegrees, targetAzimuth) <= tolerance
    }

    func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(CapturedView.normalizeAzimuth(a) - CapturedView.normalizeAzimuth(b))
        return min(d, 360 - d)
    }

    func distanceStatus(recommended: Double = CaptureConstants.recommendedDistanceMeters,
                        tolerance: Double = CaptureConstants.distanceToleranceMeters) -> DistanceHint {
        let d = estimatedDistanceMeters
        if d < recommended - tolerance { return .tooClose }
        if d > recommended + tolerance { return .tooFar }
        return .good
    }
}

enum DistanceHint {
    case tooClose, tooFar, good

    var message: String {
        switch self {
        case .tooClose: return "Too close — step back a little"
        case .tooFar: return "Too far — move closer"
        case .good: return "Good distance"
        }
    }
}
