import SwiftUI
import RealityKit
import ARKit
import Combine

struct PhotographicARScreen: View {
    let object: FoodObject
    @EnvironmentObject private var store: ObjectLibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var selector: PhotographicViewSelector
    @State private var placed = false
    @State private var showDebugOverlay = false

    init(object: FoodObject) {
        self.object = object
        _selector = StateObject(wrappedValue: PhotographicViewSelector(object: object))
    }

    var body: some View {
        ZStack {
            PhotographicARViewContainer(
                object: object,
                store: store,
                selector: selector,
                placed: $placed
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Text(object.name.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                if !placed {
                    Text("TAP TO PLACE")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .padding(.bottom, 28)
                } else {
                    HStack(spacing: 16) {
                        ARControlButton(title: "↻ Rotate", action: { NotificationCenter.default.post(name: .arRotate, object: nil) })
                        ARControlButton(title: "Reset", action: { NotificationCenter.default.post(name: .arReset, object: nil) })
                        ARControlButton(title: "Remove", action: {
                            placed = false
                            NotificationCenter.default.post(name: .arRemove, object: nil)
                        })
                    }
                    .padding(.bottom, 28)
                }

                if showDebugOverlay {
                    debugPanel
                        .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { selector.preload(store: store) }
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG  fps \(String(format: "%.0f", selector.fps))")
            Text("az \(String(format: "%.1f", selector.viewerAzimuth))°  el \(String(format: "%.1f", selector.viewerElevation))°")
            if let v = selector.selectedView {
                Text("view #\(selector.selectedIndex)  az \(Int(v.azimuth)) el \(Int(v.elevation))")
            }
            if let n = selector.neighborView {
                Text("blend #\(selector.blendIndex ?? -1) factor \(String(format: "%.2f", selector.blendFactor))  (\(Int(n.azimuth))°)")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.green)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55))
    }
}

private struct ARControlButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
    }
}

extension Notification.Name {
    static let arRotate = Notification.Name("arfood.rotate")
    static let arReset = Notification.Name("arfood.reset")
    static let arRemove = Notification.Name("arfood.remove")
}

// MARK: - UIKit / RealityKit bridge

struct PhotographicARViewContainer: UIViewRepresentable {
    let object: FoodObject
    let store: ObjectLibraryStore
    @ObservedObject var selector: PhotographicViewSelector
    @Binding var placed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(object: object, store: store, selector: selector, placed: $placed)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            // keep default; food placement doesn't require people occlusion
        }
        arView.session.run(config)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        context.coordinator.attach(arView: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.placedBinding = $placed
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        let object: FoodObject
        let store: ObjectLibraryStore
        let selector: PhotographicViewSelector
        var placedBinding: Binding<Bool>
        weak var arView: ARView?
        private var objectAnchor: AnchorEntity?
        private var billboard: ModelEntity?
        private var blendBillboard: ModelEntity?
        private var displayLink: CADisplayLink?
        private var objectYaw: Float = 0
        private var baseScale: Float = 1
        private var placementIndicator: ModelEntity?
        private var cancellables = Set<AnyCancellable>()
        private var lastTextureName: String?
        private var lastBlendName: String?

        init(object: FoodObject, store: ObjectLibraryStore, selector: PhotographicViewSelector, placed: Binding<Bool>) {
            self.object = object
            self.store = store
            self.selector = selector
            self.placedBinding = placed
        }

        func attach(arView: ARView) {
            self.arView = arView
            arView.session.delegate = self
            let tap = UITapGestureRecognizer(target: self, selector: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tap)
            addPlacementIndicator(to: arView)

            NotificationCenter.default.addObserver(self, selector: #selector(rotate), name: .arRotate, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reset), name: .arReset, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(remove), name: .arRemove, object: nil)

            let link = CADisplayLink(target: self, selector: #selector(frameUpdate))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            NotificationCenter.default.removeObserver(self)
        }

        private func addPlacementIndicator(to arView: ARView) {
            let mesh = MeshResource.generatePlane(width: 0.18, depth: 0.18, cornerRadius: 0.09)
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor.white.withAlphaComponent(0.35), texture: nil)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "placementIndicator"
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.1, 0.1]))
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            placementIndicator = entity
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView, !placedBinding.wrappedValue else { return }
            let loc = gesture.location(in: arView)
            guard let result = arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
            place(at: result.worldTransform, in: arView)
        }

        private func place(at transform: simd_float4x4, in arView: ARView) {
            objectAnchor?.removeFromParent()
            let anchor = AnchorEntity(world: transform)
            let widthM = PhotographicARMath.metersFromWidthCm(object.widthCm)
            baseScale = widthM

            let plane = MeshResource.generatePlane(width: 1, height: 1)
            var mat = UnlitMaterial()
            mat.blending = .transparent(opacity: 1.0)
            if let first = object.views.first, let tex = selector.texture(named: first.image) {
                mat.color = .init(texture: .init(tex))
                lastTextureName = first.image
            }
            let entity = ModelEntity(mesh: plane, materials: [mat])
            entity.position = [0, widthM * 0.5, 0]
            entity.scale = [widthM, widthM, widthM]
            // generatePlane(width:height:) lies in XY (already upright in world space).
            entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            anchor.addChild(entity)

            // Optional blend plane (slightly offset)
            var blendMat = UnlitMaterial()
            blendMat.blending = .transparent(opacity: 0.0)
            let blend = ModelEntity(mesh: plane, materials: [blendMat])
            blend.position = [0, widthM * 0.5, 0.001]
            blend.scale = [widthM, widthM, widthM]
            blend.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            anchor.addChild(blend)

            arView.scene.addAnchor(anchor)
            objectAnchor = anchor
            billboard = entity
            blendBillboard = blend
            objectYaw = 0
            placedBinding.wrappedValue = true
            placementIndicator?.isEnabled = false
        }

        @objc private func rotate() {
            objectYaw += .pi / 8
            objectAnchor?.orientation = simd_quatf(angle: objectYaw, axis: [0, 1, 0])
        }

        @objc private func reset() {
            objectYaw = 0
            objectAnchor?.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            if let billboard {
                billboard.scale = [baseScale, baseScale, baseScale]
            }
            if let blendBillboard {
                blendBillboard.scale = [baseScale, baseScale, baseScale]
            }
        }

        @objc private func remove() {
            objectAnchor?.removeFromParent()
            objectAnchor = nil
            billboard = nil
            blendBillboard = nil
            placementIndicator?.isEnabled = true
            placedBinding.wrappedValue = false
        }

        @objc private func frameUpdate() {
            guard let arView, let anchor = objectAnchor, let billboard else { return }
            guard let frame = arView.session.currentFrame else { return }
            let cam = frame.camera.transform.columns.3
            let camPos = SIMD3<Float>(cam.x, cam.y, cam.z)
            let obj = anchor.position(relativeTo: nil)
            let az = PhotographicARMath.relativeAzimuth(cameraWorld: camPos, objectWorld: obj, objectYaw: objectYaw)
            let el = PhotographicARMath.relativeElevation(cameraWorld: camPos, objectWorld: obj)
            selector.updateViewer(relativeAzimuth: az, elevation: el)

            // Billboard yaw: face camera while staying upright (XY plane).
            let toCam = camPos - obj
            let face = atan2(toCam.x, toCam.z)
            let yaw = face - objectYaw
            billboard.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            blendBillboard?.orientation = billboard.orientation

            if let view = selector.selectedView, view.image != lastTextureName,
               let tex = selector.texture(named: view.image) {
                var mat = UnlitMaterial()
                mat.blending = .transparent(opacity: 1.0)
                mat.color = .init(texture: .init(tex))
                billboard.model?.materials = [mat]
                lastTextureName = view.image
            }

            if let blend = blendBillboard {
                if let neighbor = selector.neighborView,
                   let tex = selector.texture(named: neighbor.image) {
                    var mat = UnlitMaterial()
                    let opacity = selector.blendFactor
                    mat.blending = .transparent(opacity: opacity)
                    mat.color = .init(tint: UIColor.white.withAlphaComponent(CGFloat(opacity)), texture: .init(tex))
                    blend.model?.materials = [mat]
                    blend.isEnabled = selector.blendFactor > 0.02
                    lastBlendName = neighbor.image
                } else {
                    blend.isEnabled = false
                }
            }
        }
    }
}
