import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ObjectLibraryStore
    @State private var path = NavigationPath()
    @State private var versionTapCount = 0
    @State private var showDebug = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScreenBackground()
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 14) {
                        Text("AR FOOD")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .shadow(color: AppTheme.accent.opacity(0.25), radius: 24, y: 8)

                        Text("Photograph a dish. Place it in AR.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)

                    Spacer()

                    VStack(spacing: 14) {
                        Button("CAPTURE NEW FOOD") {
                            path.append(Route.instructions)
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: true))

                        Button("MY OBJECTS") {
                            path.append(Route.library)
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)

                    Text("v1.0.0")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .padding(.bottom, 18)
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                versionTapCount = 0
                                showDebug = true
                            }
                        }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .instructions:
                    CaptureInstructionsView(path: $path)
                case .capture(let widthCm, let name):
                    GuidedCaptureView(path: $path, widthCm: widthCm, objectName: name)
                case .scale:
                    ScaleInputView(path: $path)
                case .processing(let frames, let widthCm, let name):
                    ProcessingView(path: $path, frames: frames, widthCm: widthCm, objectName: name)
                case .ready(let id):
                    ObjectReadyView(path: $path, objectID: id)
                case .library:
                    MyObjectsView(path: $path)
                case .detail(let id):
                    ObjectDetailView(path: $path, objectID: id)
                case .ar(let id):
                    if let obj = store.object(id: id) ?? store.reloadObject(id: id) {
                        PhotographicARScreen(object: obj)
                    } else {
                        Text("Object missing").foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showDebug) {
                CaptureDebugView()
                    .environmentObject(store)
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum Route: Hashable {
    case instructions
    case scale
    case capture(widthCm: Double, name: String)
    case processing(frames: [RawCaptureFrameProxy], widthCm: Double, name: String)
    case ready(id: String)
    case library
    case detail(id: String)
    case ar(id: String)
}

/// Navigation-safe proxy for raw frames (UIImages aren't Hashable).
struct RawCaptureFrameProxy: Hashable {
    let id: UUID
    static func == (lhs: RawCaptureFrameProxy, rhs: RawCaptureFrameProxy) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Holds large capture payloads outside NavigationPath hashing.
@MainActor
final class CaptureDraftStore: ObservableObject {
    static let shared = CaptureDraftStore()
    var frames: [RawCaptureFrame] = []
    var widthCm: Double = 12
    var name: String = "Food"
    var warnings: [QualityWarning] = []
}
