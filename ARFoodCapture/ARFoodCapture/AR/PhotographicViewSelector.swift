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
            if let ui = provider.loadUIImage(named: view.image), let cg = ui.cgImage {
                images[view.image] = cg
                if let tex = try? TextureResource.generate(from: cg, options: TextureResource.CreateOptions(semantic: .color)) {
                    textures[view.image] = tex
                }
            }
        }
    }

    func texture(named name: String) -> TextureResource? { textures[name] }

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
}
