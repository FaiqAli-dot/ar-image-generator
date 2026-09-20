import Foundation
import CoreMotion
import Combine
import UIKit

/// Derives capture azimuth / elevation from device motion for guided auto-capture.
@MainActor
final class MotionCaptureGuide: NSObject, ObservableObject {
    @Published var azimuthDegrees: Double = 0
    @Published var elevationDegrees: Double = 0
    @Published var isAvailable = true

    private let motion = CMMotionManager()
    private var referenceYaw: Double?
    private var displayLink: CADisplayLink?
    private var baselineUserAcceleration: Double?

    /// Soft distance band (~recommended). Uses motion energy as a proxy when LiDAR is unavailable.
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
    }

    func resetOrbitReference() {
        referenceYaw = nil
    }

    @objc private func tick() {
        guard let dm = motion.deviceMotion else { return }
        // Attitude: pitch ≈ elevation of camera, yaw ≈ orbit around object
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
        // Soft hint only — does not block capture.
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
