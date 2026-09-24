import Foundation
import Combine
import CoreVideo
import Vision
import UIKit

// MARK: - Semantics
/// Object azimuth = **orientation of the food on the turntable**, not phone heading.
/// Phone gyro / CoreMotion yaw must never be assigned as object angle.
/// Prefer Vision-assisted estimates when available; otherwise ManualRotationProvider
/// advances on CAPTURE NEXT / post-capture re-anchor. MotorizedRotationProvider is a future stub.

enum RotationTrackingQuality: String {
    case unavailable
    case manualOnly
    case low
    case medium
    case high

    var debugLabel: String {
        switch self {
        case .unavailable: return "unavailable"
        case .manualOnly: return "manual"
        case .low: return "vision-low"
        case .medium: return "vision-med"
        case .high: return "vision-high"
        }
    }
}

@MainActor
protocol ObjectRotationProviding: AnyObject {
    /// Object orientation degrees in [0, 360). Never phone yaw.
    var objectAzimuthDegrees: Double { get }
    var trackingQuality: RotationTrackingQuality { get }
    var sourceDescription: String { get }
    /// True when Vision assist is actively refining the estimate.
    var visionAssistActive: Bool { get }

    func start()
    func stop()
    func resetObjectReference()
    /// Re-anchor after a discrete capture so the next rotate starts from this slot.
    func didCapture(atAzimuth: Double)
    /// CAPTURE NEXT / manual path: snap estimate to the captured slot.
    func noteManualAdvance(toAzimuth: Double)
    /// Optional live preview frames for Vision assist (no-op for providers that ignore video).
    func ingestVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval)

    func nearestCaptureSlot(step: Double) -> Double
    func isAligned(to targetAzimuth: Double, tolerance: Double) -> Bool
}

// MARK: - Manual (active)

/// Guided turntable capture: phone stays put; user rotates the object.
/// Object angle comes from Vision assist when practical, else CAPTURE NEXT / post-capture anchors.
@MainActor
final class ManualRotationProvider: NSObject, ObjectRotationProviding, ObservableObject {
    @Published private(set) var objectAzimuthDegrees: Double = 0
    @Published private(set) var trackingQuality: RotationTrackingQuality = .manualOnly
    @Published private(set) var visionAssistActive: Bool = false
    /// Cumulative Vision-estimated delta since last re-anchor (debug; may be signed).
    @Published private(set) var visionDeltaSinceAnchor: Double = 0

    let sourceDescription = "ManualRotationProvider (turntable + optional Vision)"

    private let vision = VisionObjectRotationAssist()
    private var lastIngestTime: TimeInterval = 0
    private var running = false
    /// Last discrete snap (capture / CAPTURE NEXT / reset). Vision delta is added on top.
    private var anchorAzimuth: Double = 0

    func start() {
        running = true
        visionAssistActive = true
        trackingQuality = .manualOnly
    }

    func stop() {
        running = false
        visionAssistActive = false
        vision.reset()
        trackingQuality = .manualOnly
    }

    func resetObjectReference() {
        anchorAzimuth = 0
        objectAzimuthDegrees = 0
        visionDeltaSinceAnchor = 0
        vision.reset()
        trackingQuality = .manualOnly
    }

    func didCapture(atAzimuth: Double) {
        let snap = CapturedView.normalizeAzimuth(atAzimuth)
        anchorAzimuth = snap
        objectAzimuthDegrees = snap
        visionDeltaSinceAnchor = 0
        vision.reset()
        trackingQuality = .manualOnly
    }

    func noteManualAdvance(toAzimuth: Double) {
        didCapture(atAzimuth: toAzimuth)
    }

    func ingestVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard running, visionAssistActive else { return }
        // Throttle Vision work (~8 Hz) to keep capture UI responsive.
        guard timestamp - lastIngestTime >= 0.12 else { return }
        lastIngestTime = timestamp

        let result = vision.estimateDeltaDegrees(from: pixelBuffer)
        guard let result else {
            trackingQuality = .manualOnly
            return
        }

        visionDeltaSinceAnchor += result.deltaDegrees
        objectAzimuthDegrees = CapturedView.normalizeAzimuth(anchorAzimuth + visionDeltaSinceAnchor)
        trackingQuality = result.quality
    }

    func nearestCaptureSlot(step: Double = CaptureConstants.azimuthStepDegrees) -> Double {
        let slot = (objectAzimuthDegrees / step).rounded() * step
        return CapturedView.normalizeAzimuth(slot)
    }

    func isAligned(to targetAzimuth: Double, tolerance: Double = CaptureConstants.azimuthCaptureTolerance) -> Bool {
        angularDistance(objectAzimuthDegrees, targetAzimuth) <= tolerance
    }

    func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(CapturedView.normalizeAzimuth(a) - CapturedView.normalizeAzimuth(b))
        return min(d, 360 - d)
    }
}

// MARK: - Motorized (stub only)

/// Future Bluetooth / motorized turntable. Not implemented — do not call hardware APIs.
@MainActor
final class MotorizedRotationProvider: ObjectRotationProviding, ObservableObject {
    @Published private(set) var objectAzimuthDegrees: Double = 0
    @Published private(set) var trackingQuality: RotationTrackingQuality = .unavailable
    var visionAssistActive: Bool { false }
    let sourceDescription = "MotorizedRotationProvider (stub — not implemented)"

    func start() { /* stub */ }
    func stop() { /* stub */ }
    func resetObjectReference() { objectAzimuthDegrees = 0 }

    func didCapture(atAzimuth: Double) {
        objectAzimuthDegrees = CapturedView.normalizeAzimuth(atAzimuth)
    }

    func noteManualAdvance(toAzimuth: Double) {
        didCapture(atAzimuth: toAzimuth)
    }

    func ingestVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) { /* stub */ }

    func nearestCaptureSlot(step: Double = CaptureConstants.azimuthStepDegrees) -> Double {
        CapturedView.normalizeAzimuth((objectAzimuthDegrees / step).rounded() * step)
    }

    func isAligned(to targetAzimuth: Double, tolerance: Double = CaptureConstants.azimuthCaptureTolerance) -> Bool {
        let d = abs(CapturedView.normalizeAzimuth(objectAzimuthDegrees) - CapturedView.normalizeAzimuth(targetAzimuth))
        return min(d, 360 - d) <= tolerance
    }
}

// MARK: - Lightweight Vision assist

/// Estimates incremental object rotation from center-crop optical flow (Apple Vision only).
/// Approximate — not a calibrated turntable encoder. CAPTURE NEXT remains the reliable path.
final class VisionObjectRotationAssist {
    struct Estimate {
        let deltaDegrees: Double
        let quality: RotationTrackingQuality
    }

    private var previousBuffer: CVPixelBuffer?

    func reset() {
        previousBuffer = nil
    }

    /// Synchronous-ish estimate on a background-prepared copy; returns nil when Vision cannot help.
    func estimateDeltaDegrees(from pixelBuffer: CVPixelBuffer) -> Estimate? {
        let current = Self.centerCropCopy(pixelBuffer)
        defer { previousBuffer = current }
        guard let previous = previousBuffer, let current else { return nil }

        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current, completionHandler: nil)
        request.computationAccuracy = .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float

        let handler = VNImageRequestHandler(cvPixelBuffer: previous, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            return Estimate(deltaDegrees: 0, quality: .low)
        }

        let flow = Self.meanTangentialRotationDegrees(flowBuffer: observation.pixelBuffer)
        guard let flow else {
            return Estimate(deltaDegrees: 0, quality: .low)
        }

        // Clamp per-frame so noise cannot jump multiple slots.
        let clamped = max(-8, min(8, flow.degrees))
        let quality: RotationTrackingQuality
        if flow.sampleCount < 40 || flow.meanMagnitude < 0.15 {
            quality = .low
        } else if flow.meanMagnitude < 0.8 {
            quality = .medium
        } else {
            quality = .high
        }
        // Ignore tiny jitter when nearly still.
        if abs(clamped) < 0.15 {
            return Estimate(deltaDegrees: 0, quality: quality == .high ? .medium : quality)
        }
        return Estimate(deltaDegrees: clamped, quality: quality)
    }

    private struct FlowStats {
        let degrees: Double
        let meanMagnitude: Double
        let sampleCount: Int
    }

    /// Interprets optical flow as approximate in-plane rotation around the crop center.
    private static func meanTangentialRotationDegrees(flowBuffer: CVPixelBuffer) -> FlowStats? {
        CVPixelBufferLockBaseAddress(flowBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flowBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(flowBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(flowBuffer)
        let height = CVPixelBufferGetHeight(flowBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(flowBuffer)
        guard width > 8, height > 8 else { return nil }

        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let minR = Double(min(width, height)) * 0.18
        let maxR = Double(min(width, height)) * 0.46

        var sumTheta = 0.0
        var sumMag = 0.0
        var count = 0

        // Sparse sample grid for speed.
        let step = max(2, min(width, height) / 24)
        let ptr = base.assumingMemoryBound(to: Float.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float>.size

        var y = step
        while y < height - step {
            var x = step
            while x < width - step {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                let r = sqrt(dx * dx + dy * dy)
                if r >= minR && r <= maxR {
                    let offset = y * floatsPerRow + x * 2
                    let fx = Double(ptr[offset])
                    let fy = Double(ptr[offset + 1])
                    let mag = sqrt(fx * fx + fy * fy)
                    // Tangential unit (−sin, cos) for CCW; signed projection ≈ r * dθ (radians in pixel space).
                    let tx = -dy / r
                    let ty = dx / r
                    let tangential = fx * tx + fy * ty
                    let dTheta = tangential / r
                    sumTheta += dTheta
                    sumMag += mag
                    count += 1
                }
                x += step
            }
            y += step
        }

        guard count > 0 else { return nil }
        let meanTheta = sumTheta / Double(count)
        let degrees = meanTheta * 180 / .pi
        return FlowStats(degrees: degrees, meanMagnitude: sumMag / Double(count), sampleCount: count)
    }

    private static func centerCropCopy(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let side = min(w, h)
        let outSide = min(160, side)
        let ci = CIImage(cvPixelBuffer: buffer)
        let crop = CGRect(
            x: (w - side) / 2,
            y: (h - side) / 2,
            width: side,
            height: side
        )
        let cropped = ci.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))
        let scale = CGFloat(outSide) / CGFloat(side)
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, outSide, outSide, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let out else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        context.render(scaled, to: out)
        return out
    }
}
