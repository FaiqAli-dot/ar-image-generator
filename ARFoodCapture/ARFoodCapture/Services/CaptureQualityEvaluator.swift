import Foundation
import UIKit

/// Decision returned by per-photo quality checks. Soft advice never invents object-relative precision.
enum CaptureQualityDecision: Equatable {
    case accept
    case warn(CaptureQualityIssue)
    case reject(CaptureQualityIssue)

    var issue: CaptureQualityIssue? {
        switch self {
        case .accept: return nil
        case .warn(let i), .reject(let i): return i
        }
    }

    var shouldOfferRetake: Bool {
        switch self {
        case .reject: return true
        case .warn(let issue): return issue.severity
        case .accept: return false
        }
    }
}

enum CaptureQualityIssue: String, Equatable {
    case blurry
    case tooDark
    case tooBright
    case nearDuplicate
    case framingUncertain
    case coverageGap

    var message: String {
        switch self {
        case .blurry:
            return "This shot looks blurry — hold still and retake."
        case .tooDark:
            return "Too dark — add even light on the dish, then retake."
        case .tooBright:
            return "Too bright / washed out — soften light and retake."
        case .nearDuplicate:
            return "Very similar to the last photo — rotate the dish a bit more."
        case .framingUncertain:
            return "Keep the whole dish centered and fully visible in the frame."
        case .coverageGap:
            return "A coverage sector is still missing — follow the next angle hint."
        }
    }

    var actionable: Bool {
        switch self {
        case .blurry, .tooDark, .tooBright, .nearDuplicate: return true
        case .framingUncertain, .coverageGap: return false
        }
    }
}

struct CaptureQualityMetrics: Equatable {
    var blurScore: Double       // higher = sharper (Laplacian variance proxy)
    var meanLuma: Double        // 0…1
    var duplicateDistance: Double // 0…1, lower = more similar to previous
}

/// Per-photo quality checks using Core Graphics only (no ML models, no fake LiDAR distance).
enum CaptureQualityEvaluator {
    /// Laplacian-variance-like sharpness on a downscaled luma grid. Tuned for soft reject.
    static let blurRejectThreshold: Double = 12
    static let blurWarnThreshold: Double = 28
    static let darkThreshold: Double = 0.12
    static let brightThreshold: Double = 0.88
    static let duplicateRejectDistance: Double = 0.04
    static let duplicateWarnDistance: Double = 0.09

    static func evaluate(
        image: UIImage,
        previousFingerprint: [UInt8]?,
        phoneStable: Bool
    ) -> (CaptureQualityDecision, CaptureQualityMetrics, [UInt8]) {
        let fingerprint = makeFingerprint(image)
        let blur = blurScore(image)
        let luma = meanLuma(image) ?? 0.5
        let dup = previousFingerprint.map { fingerprintDistance(fingerprint, $0) } ?? 1.0
        let metrics = CaptureQualityMetrics(blurScore: blur, meanLuma: luma, duplicateDistance: dup)

        if !phoneStable && blur < blurWarnThreshold {
            return (.reject(.blurry), metrics, fingerprint)
        }
        if blur < blurRejectThreshold {
            return (.reject(.blurry), metrics, fingerprint)
        }
        if luma < darkThreshold {
            return (.reject(.tooDark), metrics, fingerprint)
        }
        if luma > brightThreshold {
            return (.reject(.tooBright), metrics, fingerprint)
        }
        if dup < duplicateRejectDistance {
            return (.reject(.nearDuplicate), metrics, fingerprint)
        }
        if blur < blurWarnThreshold {
            return (.warn(.blurry), metrics, fingerprint)
        }
        if dup < duplicateWarnDistance {
            return (.warn(.nearDuplicate), metrics, fingerprint)
        }
        // Framing / object-in-frame is not reliably measurable without subject segmentation
        // on every shutter — surface a soft instruction rather than a fake reject.
        return (.accept, metrics, fingerprint)
    }

    /// Framing guidance when we cannot measure object bounds reliably.
    static func framingInstruction() -> String {
        CaptureQualityIssue.framingUncertain.message
    }

    // MARK: - Metrics

    static func blurScore(_ image: UIImage) -> Double {
        guard let pixels = lumaGrid(image, width: 64, height: 64) else { return blurWarnThreshold }
        let w = 64, h = 64
        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(pixels[y * w + x])
                let lap = Double(pixels[(y - 1) * w + x])
                    + Double(pixels[(y + 1) * w + x])
                    + Double(pixels[y * w + x - 1])
                    + Double(pixels[y * w + x + 1])
                    - 4 * c
                sum += lap
                sumSq += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, (sumSq / count) - mean * mean)
    }

    static func meanLuma(_ image: UIImage) -> Double? {
        guard let pixels = lumaGrid(image, width: 16, height: 16) else { return nil }
        let sum = pixels.reduce(0.0) { $0 + Double($1) }
        return (sum / Double(pixels.count)) / 255.0
    }

    /// Tiny average-hash style fingerprint for near-duplicate detection.
    static func makeFingerprint(_ image: UIImage) -> [UInt8] {
        guard let pixels = lumaGrid(image, width: 8, height: 8) else {
            return [UInt8](repeating: 0, count: 64)
        }
        return pixels
    }

    static func fingerprintDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var acc = 0.0
        for i in 0..<n {
            acc += abs(Double(a[i]) - Double(b[i]))
        }
        return (acc / Double(n)) / 255.0
    }

    private static func lumaGrid(_ image: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var luma = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            let y = 0.2126 * Double(data[o]) + 0.7152 * Double(data[o + 1]) + 0.0722 * Double(data[o + 2])
            luma[i] = UInt8(max(0, min(255, y.rounded())))
        }
        return luma
    }
}

/// Pure decision helper for unit tests without UIImage.
enum CaptureQualityRules {
    static func decide(
        blurScore: Double,
        meanLuma: Double,
        duplicateDistance: Double,
        phoneStable: Bool
    ) -> CaptureQualityDecision {
        if !phoneStable && blurScore < CaptureQualityEvaluator.blurWarnThreshold {
            return .reject(.blurry)
        }
        if blurScore < CaptureQualityEvaluator.blurRejectThreshold {
            return .reject(.blurry)
        }
        if meanLuma < CaptureQualityEvaluator.darkThreshold {
            return .reject(.tooDark)
        }
        if meanLuma > CaptureQualityEvaluator.brightThreshold {
            return .reject(.tooBright)
        }
        if duplicateDistance < CaptureQualityEvaluator.duplicateRejectDistance {
            return .reject(.nearDuplicate)
        }
        if blurScore < CaptureQualityEvaluator.blurWarnThreshold {
            return .warn(.blurry)
        }
        if duplicateDistance < CaptureQualityEvaluator.duplicateWarnDistance {
            return .warn(.nearDuplicate)
        }
        return .accept
    }
}
