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
    @State private var warnings: [QualityWarning] = []

    private var showLiveGuides: Bool {
        session.isAutoArmed && !showPassIntro && !showElevatedIntro && !showComplete
    }

    var body: some View {
        ZStack {
            CameraPreview(controller: session.camera)
                .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if showLiveGuides {
                AlignmentFrameOverlay(
                    color: alignmentBorderColor,
                    pulse: session.isCaptureAligned
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                DirectionalGuidanceOverlay(
                    orbit: session.orbitGuidance,
                    elevation: session.elevationGuidance,
                    tint: alignmentBorderColor,
                    label: session.nextTargetDirectionHint
                )
                .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
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
                    nextTargetSlot: session.nextTargetSlot,
                    currentAzimuth: session.motion.azimuthDegrees,
                    targetElevation: session.pass.targetElevationDegrees,
                    currentElevation: session.motion.elevationDegrees
                )
                .frame(width: 220, height: 220)
                .padding(.top, 4)

                ringLegend
                    .padding(.top, 2)

                Text(session.motion.distanceStatus().message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.motion.distanceStatus() == .good ? Color.green.opacity(0.9) : AppTheme.accent)

                Text("Stand ~\(Int(CaptureConstants.recommendedDistanceMeters * 100)) cm away · keep food centered")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                Text(session.lastMessage)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)

                Text("Photos capture automatically — no shutter")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                if showLiveGuides {
                    Button("CAPTURE NOW") {
                        session.captureNearestManually()
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 4)
                    Text("Use if a tick won’t fill while you hold that angle")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 6)
                }

                if session.camera.lockedSettings {
                    Text("AE / WB / FOCUS LOCKED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 8)
                }
            }

            if showPassIntro {
                passOverlay(
                    title: "PASS 1 OF 2 — SIDES",
                    bullets: CapturePass.horizontal.introBullets,
                    footer: "No shutter. Move slowly until every tick lights up.",
                    button: "START"
                ) {
                    showPassIntro = false
                    session.startPass(.horizontal)
                }
            }

            if showElevatedIntro {
                passOverlay(
                    title: "PASS 2 OF 2 — SLIGHTLY ABOVE",
                    bullets: CapturePass.elevated.introBullets,
                    footer: "Same slow orbit. Photos still auto-capture.",
                    button: "START TOP PASS"
                ) {
                    showElevatedIntro = false
                    session.beginElevatedPass()
                }
            }

            if showComplete {
                passOverlay(
                    title: "72 / 72 CAPTURE COMPLETE",
                    bullets: warnings.isEmpty
                        ? ["Ready to process photographic views."]
                        : warnings.map(\.message),
                    footer: warnings.isEmpty ? nil : "You can still process — review notes above.",
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

    /// Soft red → orange → yellow → lime → green based on alignment score.
    private var alignmentBorderColor: Color {
        if session.isCaptureAligned {
            return Color(red: 0.25, green: 0.88, blue: 0.42)
        }
        let t = max(0, min(1, session.alignmentScore))
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (0.92, 0.22, 0.22)), // red
            (0.28, (0.95, 0.48, 0.18)), // orange
            (0.55, (0.95, 0.82, 0.22)), // yellow
            (0.78, (0.72, 0.92, 0.28)), // lime
            (1.00, (0.25, 0.88, 0.42))  // green
        ]
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if t <= b.0 {
                let local = (t - a.0) / (b.0 - a.0)
                let r = a.1.0 + (b.1.0 - a.1.0) * local
                let g = a.1.1 + (b.1.1 - a.1.1) * local
                let bl = a.1.2 + (b.1.2 - a.1.2) * local
                return Color(red: r, green: g, blue: bl)
            }
        }
        return Color(red: 0.25, green: 0.88, blue: 0.42)
    }

    private var ringLegend: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                legendItem(color: AppTheme.accent, label: "Filled = captured")
                legendItem(color: .white, label: "Needle = you")
            }
            Text("Walk until all ticks light up · bright tick = next target")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Text("Frame color: red = off · green = ready to capture")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func passOverlay(
        title: String,
        bullets: [String],
        footer: String?,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 22, alignment: .leading)
                            Text(line)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

                if let footer {
                    Text(footer)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
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

/// Near-full-screen colored frame reflecting capture alignment.
struct AlignmentFrameOverlay: View {
    let color: Color
    var pulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 10
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(color.opacity(pulse ? 0.95 : 0.72), lineWidth: pulse ? 8 : 6)
                .shadow(color: color.opacity(0.45), radius: pulse ? 14 : 8)
                .padding(inset)
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeInOut(duration: 0.22), value: color.description)
        }
    }
}

/// Edge arrows so the food center stays clear.
struct DirectionalGuidanceOverlay: View {
    let orbit: CaptureOrbitGuidance
    let elevation: CaptureElevationGuidance
    let tint: Color
    let label: String?

    var body: some View {
        ZStack {
            if orbit == .left {
                guidanceChevron(systemName: "chevron.left.circle.fill", label: "LEFT")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
            if orbit == .right {
                guidanceChevron(systemName: "chevron.right.circle.fill", label: "RIGHT")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
            }
            if elevation == .raise {
                guidanceChevron(systemName: "chevron.up.circle.fill", label: "RAISE")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 110)
            }
            if elevation == .lower {
                guidanceChevron(systemName: "chevron.down.circle.fill", label: "LOWER")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 150)
            }

            if let label, orbit != .hold || elevation != .hold {
                VStack {
                    Spacer()
                    Text(label)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(tint.opacity(0.7), lineWidth: 1.2))
                        .padding(.bottom, 210)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: orbit)
        .animation(.easeOut(duration: 0.2), value: elevation)
    }

    private func guidanceChevron(systemName: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(tint.opacity(0.95))
                .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
    }
}

struct CircularCaptureGuide: View {
    let capturedSlots: Set<Int>
    var nextTargetSlot: Int? = nil
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
                    let isCaptured = capturedSlots.contains(i)
                    let isNext = nextTargetSlot == i && !isCaptured
                    ZStack {
                        if isNext {
                            Circle()
                                .stroke(AppTheme.accent, lineWidth: 2)
                                .frame(width: 16, height: 16)
                        }
                        Circle()
                            .fill(isCaptured ? AppTheme.accent : (isNext ? Color.white : Color.white.opacity(0.25)))
                            .frame(
                                width: isCaptured || isNext ? 10 : 7,
                                height: isCaptured || isNext ? 10 : 7
                            )
                    }
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
