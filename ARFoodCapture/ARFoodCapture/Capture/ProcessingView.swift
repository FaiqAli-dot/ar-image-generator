import SwiftUI

struct ProcessingView: View {
    @Binding var path: NavigationPath
    let frames: [RawCaptureFrameProxy]
    let widthCm: Double
    let objectName: String

    @EnvironmentObject private var store: ObjectLibraryStore
    @State private var progress: ProcessingProgress = .init(processed: 0, total: 1, stage: "Starting…")
    @State private var errorMessage: String?
    @State private var didStart = false

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 22) {
                Text("PROCESSING")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text(progress.stage)
                    .foregroundStyle(AppTheme.textSecondary)

                ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 40)

                Text("\(progress.processed) / \(progress.total)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding()
                }

                Spacer()
            }
            .padding(.top, 80)
        }
        .navigationBarHidden(true)
        .task {
            guard !didStart else { return }
            didStart = true
            await run()
        }
    }

    private func run() async {
        let draft = CaptureDraftStore.shared
        let sourceFrames = draft.frames
        let width = draft.widthCm
        let name = draft.name
        guard !sourceFrames.isEmpty else {
            errorMessage = "No frames to process"
            return
        }
        do {
            let (object, images, thumb) = try await ImageProcessingPipeline.process(
                frames: sourceFrames,
                name: name,
                widthCm: width
            ) { p in
                progress = p
            }
            try store.save(object, images: images, thumbnail: thumb)
            draft.frames = []
            path.append(Route.ready(id: object.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ObjectReadyView: View {
    @Binding var path: NavigationPath
    let objectID: String
    @EnvironmentObject private var store: ObjectLibraryStore

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 24) {
                Spacer()
                if let obj = store.object(id: objectID), let thumb = store.loadThumbnail(for: obj) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                }
                Text("OBJECT READY")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Photographic multi-view AR object created.")
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("VIEW IN AR") {
                    path.append(Route.ar(id: objectID))
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("DONE") {
                    path = NavigationPath()
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }
            .padding(28)
        }
        .navigationBarHidden(true)
    }
}
