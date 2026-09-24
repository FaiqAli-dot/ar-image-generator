import Foundation
import UIKit
import Vision
import CoreImage

/// On-device background removal. Prefers Vision foreground instance masks (iOS 17+).
/// Optional remote fallback can be enabled via BackgroundRemovalConfig.remoteURL.
actor BackgroundRemovalService {
    static let shared = BackgroundRemovalService()

    private let ciContext = CIContext(options: nil)

    func removeBackground(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw BackgroundRemovalError.invalidImage
        }

        if #available(iOS 17.0, *) {
            if let result = try? await visionForegroundMask(cgImage: cgImage, orientation: image.imageOrientation) {
                return result
            }
        }

        if let remote = try? await remoteFallback(image: image) {
            return remote
        }

        // Last-resort soft matte so capture flow still produces RGBA (center subject bias).
        return softCenterMatte(image)
    }

    @available(iOS 17.0, *)
    private func visionForegroundMask(cgImage: CGImage, orientation: UIImage.Orientation) async throws -> UIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(orientation), options: [:])
        try handler.perform([request])
        guard let result = request.results?.first else {
            throw BackgroundRemovalError.noMask
        }
        let maskPixelBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )
        return try apply(mask: maskPixelBuffer, to: cgImage)
    }

    private func apply(mask: CVPixelBuffer, to cgImage: CGImage) throws -> UIImage {
        let maskCI = CIImage(cvPixelBuffer: mask)
        let color = CIImage(cgImage: cgImage)
        let scaledMask = maskCI.transformed(by: CGAffineTransform(
            scaleX: color.extent.width / maskCI.extent.width,
            y: color.extent.height / maskCI.extent.height
        ))
        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            throw BackgroundRemovalError.filterUnavailable
        }
        filter.setValue(color, forKey: kCIInputImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: color.extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(scaledMask, forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage,
              let outCG = ciContext.createCGImage(output, from: color.extent) else {
            throw BackgroundRemovalError.renderFailed
        }
        // Always bake upright pixels — AR / PNG must not rely on UIImage.Orientation EXIF.
        return UIImage(cgImage: outCG, scale: 1, orientation: .up)
    }

    private func remoteFallback(image: UIImage) async throws -> UIImage {
        guard let base = BackgroundRemovalConfig.remoteURL else {
            throw BackgroundRemovalError.remoteDisabled
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw BackgroundRemovalError.invalidImage
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/remove-background"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let out = UIImage(data: data) else {
            throw BackgroundRemovalError.remoteFailed
        }
        return out
    }

    private func softCenterMatte(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let w = cgImage.width
        let h = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let cx = Double(w) / 2
        let cy = Double(h) / 2
        let rx = Double(w) * 0.38
        let ry = Double(h) * 0.42
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let nx = (Double(x) - cx) / rx
                let ny = (Double(y) - cy) / ry
                let d = sqrt(nx * nx + ny * ny)
                let alpha: UInt8
                if d < 0.75 {
                    alpha = 255
                } else if d > 1.15 {
                    alpha = 0
                } else {
                    alpha = UInt8(255.0 * (1.15 - d) / 0.4)
                }
                let a = Double(alpha) / 255.0
                pixels[i] = UInt8(Double(pixels[i]) * a)
                pixels[i + 1] = UInt8(Double(pixels[i + 1]) * a)
                pixels[i + 2] = UInt8(Double(pixels[i + 2]) * a)
                pixels[i + 3] = alpha
            }
        }
        guard let out = ctx.makeImage() else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }

    private func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

enum BackgroundRemovalError: LocalizedError {
    case invalidImage, noMask, filterUnavailable, renderFailed, remoteDisabled, remoteFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image"
        case .noMask: return "Could not generate foreground mask"
        case .filterUnavailable: return "Core Image filter unavailable"
        case .renderFailed: return "Failed to render transparent image"
        case .remoteDisabled: return "Remote background removal not configured"
        case .remoteFailed: return "Remote background removal failed"
        }
    }
}

enum BackgroundRemovalConfig {
    /// Set to a free-tier backend base URL if on-device Vision is insufficient.
    /// Example: https://ar-food-bg.example.com
    static var remoteURL: URL? = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BackgroundRemovalAPIBaseURL") as? String,
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return nil
    }()
}
