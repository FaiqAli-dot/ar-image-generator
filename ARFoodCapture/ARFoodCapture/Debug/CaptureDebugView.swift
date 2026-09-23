import SwiftUI

struct CaptureDebugView: View {
    @EnvironmentObject private var store: ObjectLibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = MotionCaptureGuide()
    @State private var selectedObjectID: String?
    @State private var selector: PhotographicViewSelector?
    @State private var apiOverride: String = APIConfig.overrideString ?? ""

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    Text("Objects: \(store.objects.count)")
                    ForEach(store.objects) { obj in
                        Button("\(obj.name) — \(obj.viewCount) views · \(obj.syncState.badgeTitle)") {
                            selectedObjectID = obj.id
                            let sel = PhotographicViewSelector(object: obj)
                            sel.preload(store: store)
                            selector = sel
                        }
                    }
                }

                Section("API base URL") {
                    Text("Resolved: \(APIConfig.baseURL?.absoluteString ?? "(none)")")
                        .font(.footnote.monospaced())
                    TextField("Override (e.g. https://…)", text: $apiOverride)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save override") {
                        APIConfig.setOverride(apiOverride)
                    }
                    Button("Clear override") {
                        apiOverride = ""
                        APIConfig.setOverride(nil)
                    }
                    if let capture = Optional(APIConfig.captureQRURL),
                       let qr = QRCodeGenerator.image(from: capture.absoluteString, dimension: 180) {
                        VStack {
                            Text("Capture QR → CAPTURE NEW FOOD")
                                .font(.caption)
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 120, height: 120)
                            Text(capture.absoluteString)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
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
