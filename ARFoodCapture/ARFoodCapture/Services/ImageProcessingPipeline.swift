import Foundation
import UIKit

struct RawCaptureFrame {
    let image: UIImage
    let azimuth: Double
    let elevation: Double
    let distance: Double?
    let capturedAt: Date
}

struct ProcessingProgress: Sendable {
    let processed: Int
    let total: Int
    let stage: String
}

enum ImageProcessingPipeline {
    static let maxProcessedDimension: CGFloat = 1024

    static func process(
        frames: [RawCaptureFrame],
        name: String,
        widthCm: Double,
        onProgress: @MainActor @escaping (ProcessingProgress) -> Void
    ) async throws -> (FoodObject, [String: Data], Data) {
        var views: [CapturedView] = []
        var images: [String: Data] = [:]
        let total = frames.count

        for (index, frame) in frames.enumerated() {
            await onProgress(ProcessingProgress(processed: index, total: total, stage: "Removing background…"))
            let normalized = normalize(frame.image)
            let cutout = try await BackgroundRemovalService.shared.removeBackground(from: normalized)
            let fileName = String(format: "view_%03d.png", index)
            guard let png = cutout.pngData() else {
                throw PipelineError.encodeFailed
            }
            images[fileName] = png
            views.append(
                CapturedView(
                    azimuth: frame.azimuth,
                    elevation: frame.elevation,
                    image: fileName,
                    distance: frame.distance,
                    capturedAt: frame.capturedAt
                )
            )
            await onProgress(ProcessingProgress(processed: index + 1, total: total, stage: "Processing views…"))
        }

        await onProgress(ProcessingProgress(processed: total, total: total, stage: "Building thumbnail…"))
        let firstKey = String(format: "view_%03d.png", 0)
        let thumbSource = images[firstKey].flatMap { UIImage(data: $0) } ?? frames.first?.image
        let thumbnail = makeThumbnail(thumbSource)
        let thumbData = thumbnail?.pngData() ?? Data()

        let object = FoodObject(
            name: name,
            widthCm: widthCm,
            views: views,
            notes: "Photographic multi-view object"
        )
        return (object, images, thumbData)
    }

    static func qualityWarnings(for frames: [RawCaptureFrame]) -> [QualityWarning] {
        var warnings: [QualityWarning] = []
        let expected = CaptureConstants.totalViews
        if frames.count < expected {
            warnings.append(QualityWarning(message: "Missing \(expected - frames.count) of \(expected) expected views."))
        }

        let azBins = Set(frames.map { Int(($0.azimuth / CaptureConstants.azimuthStepDegrees).rounded()) % 36 })
        if azBins.count < 30 {
            warnings.append(QualityWarning(message: "Some angles around the object may be missing."))
        }

        let brightness = frames.prefix(12).compactMap { averageLuma($0.image) }
        if let minB = brightness.min(), let maxB = brightness.max(), maxB - minB > 0.35 {
            warnings.append(QualityWarning(message: "Lighting varied during capture — results may look uneven."))
        }

        let far = frames.filter { ($0.distance ?? CaptureConstants.recommendedDistanceMeters) > CaptureConstants.recommendedDistanceMeters + CaptureConstants.distanceToleranceMeters }.count
        let near = frames.filter { ($0.distance ?? CaptureConstants.recommendedDistanceMeters) < CaptureConstants.recommendedDistanceMeters - CaptureConstants.distanceToleranceMeters }.count
        if far + near > frames.count / 3 {
            warnings.append(QualityWarning(message: "Camera distance drifted often — keep the phone steadier next time."))
        }
        return warnings
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > maxProcessedDimension else { return image.normalizedUp() }
        let scale = maxProcessedDimension / maxDim
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }.normalizedUp()
    }

    private static func makeThumbnail(_ image: UIImage?) -> UIImage? {
        guard let image else { return nil }
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let aspect = image.size.width / max(image.size.height, 1)
            var rect = CGRect(origin: .zero, size: size)
            if aspect > 1 {
                rect.size.height = size.width / aspect
                rect.origin.y = (size.height - rect.size.height) / 2
            } else {
                rect.size.width = size.height * aspect
                rect.origin.x = (size.width - rect.size.width) / 2
            }
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: rect)
        }
    }

    private static func averageLuma(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let w = 16, h = 16
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: data.count, by: 4) {
            sum += 0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])
        }
        return (sum / Double(w * h)) / 255.0
    }
}

enum PipelineError: LocalizedError {
    case encodeFailed
    var errorDescription: String? { "Failed to encode transparent PNG" }
}

extension UIImage {
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
