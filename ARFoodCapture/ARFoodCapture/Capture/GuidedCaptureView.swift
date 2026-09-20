import SwiftUI
import AVFoundation

struct GuidedCaptureView: View {
    @Binding var path: NavigationPath
    let widthCm: Double
    let objectName: String

    @StateObject private var session = GuidedCaptureSession()
    @State private var showPassIntro = true
    @State private var showElevatedIntro = false
    @State private var showComplete = false
    @State private var showWarnings = false
    @State private var warnings: [QualityWarning] = []

    var body: some View {
        ZStack {
            CameraPreview(controller: session.camera)
                .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                HStack {
                    Button {
                        session.teardown()
                        path.removeLast()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Text(session.progressText)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text(session.pass.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(AppTheme.accent)

                CircularCaptureGuide(
                    capturedSlots: session.capturedSlotsForCurrentPass,
                    currentAzimuth: session.motion.azimuthDegrees,
                    targetElevation: session.pass.targetElevationDegrees,
                    currentElevation: session.motion.elevationDegrees
                )
                .frame(width: 220, height: 220)
                .padding(.top, 8)

                Text(session.motion.distanceStatus().message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.motion.distanceStatus() == .good ? Color.green.opacity(0.9) : AppTheme.accent)

                Text("Recommended ~\(Int(CaptureConstants.recommendedDistanceMeters * 100)) cm")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                Text(session.lastMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                if session.camera.lockedSettings {
                    Text("AE / WB / FOCUS LOCKED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)
                }
            }

            if showPassIntro {
                passOverlay(
                    title: "PASS 1 OF 2",
                    message: "Capture from around the sides.",
                    button: "START"
                ) {
                    showPassIntro = false
                    session.startPass(.horizontal)
                }
            }

            if showElevatedIntro {
                passOverlay(
                    title: "SIDE VIEW COMPLETE",
                    message: "Raise phone slightly. Capture from above.",
                    button: "START TOP PASS"
                ) {
                    showElevatedIntro = false
                    session.beginElevatedPass()
                }
            }

            if showComplete {
                passOverlay(
                    title: "72 / 72 CAPTURE COMPLETE",
                    message: warnings.isEmpty ? "Ready to process photographic views." : "Review quality notes, then process.",
                    button: "PROCESS OBJECT"
                ) {
                    CaptureDraftStore.shared.frames = session.frames
                    CaptureDraftStore.shared.widthCm = widthCm
                    CaptureDraftStore.shared.name = objectName
                    CaptureDraftStore.shared.warnings = warnings
                    session.teardown()
                    path.append(Route.processing(frames: [RawCaptureFrameProxy(id: UUID())], widthCm: widthCm, name: objectName))
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await session.prepare()
        }
        .onDisappear { session.teardown() }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            session.tickAutoCapture()
            if session.passComplete && session.pass == .horizontal && !showElevatedIntro && !showComplete {
                showElevatedIntro = true
            }
            if session.allComplete && !showComplete {
                warnings = ImageProcessingPipeline.qualityWarnings(for: session.frames)
                showComplete = true
            }
        }
        .preferredColorScheme(.dark)
    }

    private func passOverlay(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                if showComplete && !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings) { w in
                            Text("• \(w.message)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.horizontal)
                }
                Button(button, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }
            .padding(28)
        }
    }
}

extension GuidedCaptureSession {
    var capturedSlotsForCurrentPass: Set<Int> {
        let offset = pass.rawValue * 100
        return Set(capturedSlots.compactMap { slot in
            let v = slot - offset
            return (0..<36).contains(v) ? v : nil
        })
    }
}

struct CircularCaptureGuide: View {
    let capturedSlots: Set<Int>
    let currentAzimuth: Double
    let targetElevation: Double
    let currentElevation: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size * 0.42
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                ForEach(0..<36, id: \.self) { i in
                    let angle = Double(i) * 10 - 90
                    let rad = angle * .pi / 180
                    let pt = CGPoint(
                        x: center.x + CGFloat(cos(rad)) * radius,
                        y: center.y + CGFloat(sin(rad)) * radius
                    )
                    Circle()
                        .fill(capturedSlots.contains(i) ? AppTheme.accent : Color.white.opacity(0.25))
                        .frame(width: capturedSlots.contains(i) ? 10 : 7, height: capturedSlots.contains(i) ? 10 : 7)
                        .position(pt)
                }
                // Camera needle
                let camAngle = (currentAzimuth - 90) * .pi / 180
                Path { path in
                    path.move(to: center)
                    path.addLine(to: CGPoint(
                        x: center.x + CGFloat(cos(camAngle)) * (radius - 8),
                        y: center.y + CGFloat(sin(camAngle)) * (radius - 8)
                    ))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                VStack(spacing: 2) {
                    Text("\(Int(currentAzimuth))°")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("el \(Int(currentElevation))° / \(Int(targetElevation))°")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var controller: CameraCaptureController

    func makeUIView(context: Context) -> PreviewHostView {
        let v = PreviewHostView()
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.attach(controller.previewLayer)
    }

    final class PreviewHostView: UIView {
        private weak var preview: AVCaptureVideoPreviewLayer?
        func attach(_ layer: AVCaptureVideoPreviewLayer?) {
            guard let layer else { return }
            if preview !== layer {
                preview?.removeFromSuperlayer()
                self.layer.addSublayer(layer)
                preview = layer
            }
            preview?.frame = bounds
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            preview?.frame = bounds
        }
    }
}
