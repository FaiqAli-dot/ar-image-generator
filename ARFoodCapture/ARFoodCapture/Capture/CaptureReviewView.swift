import SwiftUI

/// Optional review step after capture, before processing.
/// Discard/retake update coverage immediately; process stays blocked until required coverage is met.
struct CaptureReviewView: View {
    @ObservedObject var session: GuidedCaptureSession
    let widthCm: Double
    let objectName: String
    var onProcess: () -> Void
    var onRetake: (Int) -> Void
    var onClose: () -> Void

    @State private var selected: CaptureReviewLogic.ReviewItem?
    @State private var confirmDiscard: CaptureReviewLogic.ReviewItem?

    private var maps: (horizontal: CaptureCoverageMapSnapshot, elevated: CaptureCoverageMapSnapshot) {
        session.coverageMapsBothPasses
    }

    private var items: [CaptureReviewLogic.ReviewItem] {
        session.reviewItems
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 12) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    Spacer()
                    Text("REVIEW PHOTOS")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text(session.sequenceMode.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                DualCoverageMapsView(
                    horizontal: maps.horizontal,
                    elevated: maps.elevated,
                    currentAzimuth: session.objectAzimuthDegrees
                )
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    legend(color: AppTheme.accent, "Done")
                    legend(color: .white, "Next / retake")
                    legend(color: Color.white.opacity(0.28), "Missing")
                }

                if let warning = session.reviewDiscardWarning {
                    Text(warning)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Text("\(items.count) photos · ordered by angle")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in
                            thumbnail(item)
                                .onTapGesture { selected = item }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                VStack(spacing: 8) {
                    if !session.canProceedToProcessing {
                        Text("Capture missing required angles before processing.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Button("PROCESS OBJECT") {
                        guard session.canProceedToProcessing else { return }
                        onProcess()
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: session.canProceedToProcessing))
                    .disabled(!session.canProceedToProcessing)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                    .opacity(session.canProceedToProcessing ? 1 : 0.45)
                }
            }

            if let item = selected {
                previewSheet(item)
            }
        }
        .confirmationDialog(
            "Discard this photo?",
            isPresented: Binding(
                get: { confirmDiscard != nil },
                set: { if !$0 { confirmDiscard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                if let item = confirmDiscard {
                    session.discardAcceptedPhoto(slotKey: item.slotKey, queueRetake: false)
                }
                confirmDiscard = nil
                selected = nil
            }
            Button("Discard & retake") {
                if let item = confirmDiscard {
                    onRetake(item.slotKey)
                }
                confirmDiscard = nil
                selected = nil
            }
            Button("Cancel", role: .cancel) { confirmDiscard = nil }
        } message: {
            if let item = confirmDiscard {
                let warn = CaptureReviewLogic.discardWarning(
                    mode: session.sequenceMode,
                    slotKey: item.slotKey,
                    remainingSlotKeys: session.capturedSlots.subtracting([item.slotKey])
                )
                Text(warn ?? "You can retake this angle without restarting.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func thumbnail(_ item: CaptureReviewLogic.ReviewItem) -> some View {
        let frame = session.frames.first { $0.slotKey == item.slotKey }
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = frame?.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 96, height: 96)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if item.hasQualityFlag {
                    Text("FLAG")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                        .padding(5)
                }
            }
            Text(item.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 96)
        }
    }

    private func previewSheet(_ item: CaptureReviewLogic.ReviewItem) -> some View {
        let frame = session.frames.first { $0.slotKey == item.slotKey }
        return ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture { selected = nil }
            VStack(spacing: 14) {
                if let image = frame?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(item.label)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let flag = item.qualityFlag {
                    Text(flag.message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                HStack(spacing: 12) {
                    Button("DISCARD") { confirmDiscard = item }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    Button("RETAKE") { onRetake(item.slotKey); selected = nil }
                        .buttonStyle(PrimaryButtonStyle(filled: true))
                }
                .padding(.horizontal, 24)
                Button("Close") { selected = nil }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 8)
            }
            .padding(20)
        }
    }

    private func legend(color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
