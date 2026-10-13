import SwiftUI

/// Compact ring / sector coverage map for stationary phone + turntable.
/// States come only from accepted photos + current target — never “camera pointed at”.
struct CoverageMapView: View {
    let snapshot: CaptureCoverageMapSnapshot
    var currentAzimuth: Double = 0
    var compact: Bool = false
    var showLegend: Bool = true

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: size / 2, y: size / 2)
                let radius = size * 0.42
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 2)

                    ForEach(snapshot.cells) { cell in
                        cellView(cell: cell, center: center, radius: radius, total: snapshot.cells.count)
                    }

                    // Object-orientation needle (turntable azimuth), not phone yaw.
                    let camAngle = (currentAzimuth - 90) * .pi / 180
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + CGFloat(cos(camAngle)) * (radius - 10),
                            y: center.y + CGFloat(sin(camAngle)) * (radius - 10)
                        ))
                    }
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    VStack(spacing: 2) {
                        Text(compact ? "\(snapshot.completedCount)/\(snapshot.requiredCount)" : "\(Int(currentAzimuth))°")
                            .font(.system(size: compact ? 14 : 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if !compact {
                            Text(snapshot.pass == .horizontal ? "sides" : "above")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .frame(width: size, height: size)
            }

            if showLegend {
                HStack(spacing: 10) {
                    legendDot(color: AppTheme.accent, label: "Done")
                    legendDot(color: .white, label: "Next")
                    legendDot(color: Color.white.opacity(0.28), label: "Missing")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
            }

            Text(snapshot.summaryText)
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func cellView(cell: CoverageMapCell, center: CGPoint, radius: CGFloat, total: Int) -> some View {
        let count = max(total, 1)
        let angle = cell.viewpoint.azimuthDegrees - 90
        let rad = angle * .pi / 180
        let pt = CGPoint(
            x: center.x + CGFloat(cos(rad)) * radius,
            y: center.y + CGFloat(sin(rad)) * radius
        )
        let size: CGFloat = {
            switch cell.state {
            case .completed, .targeted: return total > 20 ? 9 : 12
            case .missing: return total > 20 ? 7 : 9
            }
        }()
        ZStack {
            if cell.state == .targeted {
                Circle()
                    .stroke(AppTheme.accent, lineWidth: 2)
                    .frame(width: size + 8, height: size + 8)
            }
            Circle()
                .fill(fillColor(for: cell.state))
                .frame(width: size, height: size)
        }
        .position(pt)
        .accessibilityLabel("\(cell.viewpoint.label), \(cell.state.rawValue)")
        // Keep `count` referenced for future wedge drawing without unused warnings.
        .opacity(count > 0 ? 1 : 1)
    }

    private func fillColor(for state: CoverageCellState) -> Color {
        switch state {
        case .completed: return AppTheme.accent
        case .targeted: return .white
        case .missing: return Color.white.opacity(0.28)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// Side-by-side maps for both elevation passes (review / summary).
struct DualCoverageMapsView: View {
    let horizontal: CaptureCoverageMapSnapshot
    let elevated: CaptureCoverageMapSnapshot
    var currentAzimuth: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            CoverageMapView(snapshot: horizontal, currentAzimuth: currentAzimuth, compact: true, showLegend: false)
                .frame(height: 140)
            CoverageMapView(snapshot: elevated, currentAzimuth: currentAzimuth, compact: true, showLegend: false)
                .frame(height: 140)
        }
    }
}
