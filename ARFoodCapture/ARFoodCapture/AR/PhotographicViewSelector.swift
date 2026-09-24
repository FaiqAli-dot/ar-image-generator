import Foundation
import UIKit
import RealityKit
import ARKit
import Combine
import QuartzCore

/// Selects photographic views from viewer azimuth/elevation — NOT a 3D mesh.
@MainActor
final class PhotographicViewSelector: ObservableObject {
    @Published var selectedIndex: Int = 0
    @Published var blendIndex: Int?
    @Published var blendFactor: Float = 0
    @Published var viewerAzimuth: Double = 0
    @Published var viewerElevation: Double = 0
    @Published var fps: Double = 0

    let object: FoodObject
    private var textures: [String: TextureResource] = [:]
    private var images: [String: CGImage] = [:]
    /// Opaque content bounds in image space (origin top-left, 0…1) for upright placement.
    private var contentBounds: [String: CutoutContentBounds] = [:]
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount = 0

    init(object: FoodObject) {
        self.object = object
    }

    func preload(store: ObjectLibraryStore) {
        preload(provider: LocalPhotographicImageProvider(object: object, store: store))
    }

    func preload(provider: PhotographicImageProviding) {
        for view in object.views {
            guard let ui = provider.loadUIImage(named: view.image) else { continue }
            let upright = ui.normalizedUp()
            guard let cg = upright.cgImage else { continue }
            // RealityKit UnlitMaterial on generatePlane often samples CGImage with V flipped
            // relative to UIKit — flip vertically so food is right-side-up in AR.
            let forTexture = PhotographicARMath.flipVertically(cg) ?? cg
            images[view.image] = forTexture
            contentBounds[view.image] = CutoutContentBounds.analyze(cg)
            if let tex = try? TextureResource.generate(
                from: forTexture,
                options: TextureResource.CreateOptions(semantic: .color)
            ) {
                textures[view.image] = tex
            }
        }
    }

    func texture(named name: String) -> TextureResource? { textures[name] }

    func cutoutBounds(named name: String) -> CutoutContentBounds {
        contentBounds[name] ?? .fullFrame
    }

    func updateViewer(relativeAzimuth: Double, elevation: Double) {
        viewerAzimuth = CapturedView.normalizeAzimuth(relativeAzimuth)
        viewerElevation = elevation
        let (primary, secondary, factor) = nearestViews(azimuth: viewerAzimuth, elevation: viewerElevation)
        selectedIndex = primary
        blendIndex = secondary
        blendFactor = Float(factor)

        let now = CACurrentMediaTime()
        frameCount += 1
        if lastFrameTime == 0 { lastFrameTime = now }
        let dt = now - lastFrameTime
        if dt >= 0.5 {
            fps = Double(frameCount) / dt
            frameCount = 0
            lastFrameTime = now
        }
    }

    func nearestViews(azimuth: Double, elevation: Double) -> (Int, Int?, Double) {
        guard !object.views.isEmpty else { return (0, nil, 0) }

        // Prefer same elevation band, then closest azimuth
        let scored: [(Int, Double)] = object.views.enumerated().map { idx, view in
            let azDist = min(
                abs(CapturedView.normalizeAzimuth(view.azimuth) - CapturedView.normalizeAzimuth(azimuth)),
                360 - abs(CapturedView.normalizeAzimuth(view.azimuth) - CapturedView.normalizeAzimuth(azimuth))
            )
            let elDist = abs(view.elevation - elevation) * 2.5
            return (idx, azDist + elDist)
        }.sorted { $0.1 < $1.1 }

        let primary = scored[0].0
        guard scored.count > 1 else { return (primary, nil, 0) }
        let secondary = scored[1].0
        let a = object.views[primary]
        let b = object.views[secondary]
        let azA = CapturedView.normalizeAzimuth(a.azimuth)
        let azB = CapturedView.normalizeAzimuth(b.azimuth)
        var span = abs(azB - azA)
        if span > 180 { span = 360 - span }
        let distPrimary = min(
            abs(azA - CapturedView.normalizeAzimuth(azimuth)),
            360 - abs(azA - CapturedView.normalizeAzimuth(azimuth))
        )
        let factor = span > 0.1 ? min(0.5, distPrimary / span) : 0
        // Only blend neighbors within ~15° and similar elevation
        if span <= 15, abs(a.elevation - b.elevation) < 8 {
            return (primary, secondary, factor)
        }
        return (primary, nil, 0)
    }

    var selectedView: CapturedView? {
        guard object.views.indices.contains(selectedIndex) else { return nil }
        return object.views[selectedIndex]
    }

    var neighborView: CapturedView? {
        guard let blendIndex, object.views.indices.contains(blendIndex) else { return nil }
        return object.views[blendIndex]
    }
}

/// Opaque cutout bounds in upright image space (origin top-left, normalized 0…1).
struct CutoutContentBounds: Equatable {
    var minX: CGFloat
    var minY: CGFloat
    var maxX: CGFloat
    var maxY: CGFloat

    static let fullFrame = CutoutContentBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)

    var midX: CGFloat { (minX + maxX) * 0.5 }

    static func analyze(_ cgImage: CGImage, alphaThreshold: UInt8 = 20) -> CutoutContentBounds {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 2, h > 2 else { return .fullFrame }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fullFrame }

        // Draw with UIKit-style top-left origin into this buffer.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = 0, maxY = 0
        var found = false
        // Sparse scan for speed.
        let step = max(1, min(w, h) / 128)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let a = pixels[(y * w + x) * 4 + 3]
                if a >= alphaThreshold {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                x += step
            }
            y += step
        }
        guard found else { return .fullFrame }
        // Pad slightly so we don't clip soft edges.
        let padX = CGFloat(step) / CGFloat(w)
        let padY = CGFloat(step) / CGFloat(h)
        return CutoutContentBounds(
            minX: max(0, CGFloat(minX) / CGFloat(w) - padX),
            minY: max(0, CGFloat(minY) / CGFloat(h) - padY),
            maxX: min(1, CGFloat(maxX) / CGFloat(w) + padX),
            maxY: min(1, CGFloat(maxY) / CGFloat(h) + padY)
        )
    }
}

enum PhotographicARMath {
    /// Azimuth of camera around object on horizontal plane (degrees).
    static func relativeAzimuth(cameraWorld: SIMD3<Float>, objectWorld: SIMD3<Float>, objectYaw: Float) -> Double {
        let delta = cameraWorld - objectWorld
        let worldAngle = atan2(Double(delta.x), Double(delta.z)) * 180 / .pi
        let relative = CapturedView.normalizeAzimuth(worldAngle - Double(objectYaw) * 180 / .pi)
        return relative
    }

    static func relativeElevation(cameraWorld: SIMD3<Float>, objectWorld: SIMD3<Float>) -> Double {
        let delta = cameraWorld - objectWorld
        let horizontal = sqrt(Double(delta.x * delta.x + delta.z * delta.z))
        guard horizontal > 0.001 else { return 90 }
        return atan2(Double(delta.y), horizontal) * 180 / .pi
    }

    static func metersFromWidthCm(_ cm: Double) -> Float {
        Float(cm / 100.0)
    }

    /// Vertical flip for RealityKit texture upload (CG ↔ Metal V).
    static func flipVertically(_ image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Billboard local position so opaque cutout sits upright, centered, resting on the placement point.
    /// Plane is 1×1 in XY before scale; +Y is up; texture is assumed upright after `flipVertically`.
    static func billboardPosition(widthM: Float, bounds: CutoutContentBounds) -> SIMD3<Float> {
        let x = Float(0.5 - bounds.midX) * widthM
        // Image top → plane +Y. Content bottom at normalized maxY from top → local Y = 0.5 - maxY.
        // Want content bottom at world y ≈ 0 → position.y + (0.5 - maxY) * widthM = 0
        let y = Float(bounds.maxY - 0.5) * widthM
        return SIMD3<Float>(x, y, 0)
    }
}
