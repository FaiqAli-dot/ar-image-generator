import SwiftUI

struct CaptureDebugView: View {
    @EnvironmentObject private var store: ObjectLibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = MotionCaptureGuide()
    @State private var selectedObjectID: String?
    @State private var selector: PhotographicViewSelector?

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Text("Objects: \(store.objects.count)")
                    ForEach(store.objects) { obj in
                        Button("\(obj.name) — \(obj.viewCount) views") {
                            selectedObjectID = obj.id
                            let sel = PhotographicViewSelector(object: obj)
                            sel.preload(store: store)
                            selector = sel
                        }
                    }
                }

                Section("Live motion") {
                    Text("Azimuth: \(motion.azimuthDegrees, specifier: "%.1f")°")
                    Text("Elevation: \(motion.elevationDegrees, specifier: "%.1f")°")
                    Text("Distance hint: \(motion.estimatedDistanceMeters, specifier: "%.2f") m")
                }

                if let selector {
                    Section("Selected photographic view") {
                        Text("Index: \(selector.selectedIndex)")
                        Text("Viewer az/el: \(selector.viewerAzimuth, specifier: "%.1f") / \(selector.viewerElevation, specifier: "%.1f")")
                        if let v = selector.selectedView {
                            Text("View az/el: \(v.azimuth, specifier: "%.0f") / \(v.elevation, specifier: "%.0f")")
                            Text("File: \(v.image)")
                        }
                        if let n = selector.neighborView {
                            Text("Nearest neighbor: \(n.image) blend \(selector.blendFactor, specifier: "%.2f")")
                        }
                        Text("FPS (AR): \(selector.fps, specifier: "%.0f")")
                        Button("Simulate +10° azimuth") {
                            selector.updateViewer(
                                relativeAzimuth: selector.viewerAzimuth + 10,
                                elevation: selector.viewerElevation
                            )
                        }
                    }
                }

                Section("Architecture") {
                    Text(FutureArchitecture.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CAPTURE DEBUG")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { motion.start() }
            .onDisappear { motion.stop() }
        }
    }
}
