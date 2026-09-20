import SwiftUI

enum AppTheme {
    static let bgTop = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let bgBottom = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let accent = Color(red: 0.95, green: 0.72, blue: 0.28)
    static let accentSoft = Color(red: 0.85, green: 0.55, blue: 0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let stroke = Color.white.opacity(0.12)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                bgTop,
                Color(red: 0.08, green: 0.06, blue: 0.04),
                bgBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(filled ? Color.black : AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accentSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.stroke, lineWidth: 1.2)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
            // Subtle warm vignette / grain atmosphere
            RadialGradient(
                colors: [AppTheme.accent.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.black.opacity(0.55), .clear],
                center: .bottom,
                startRadius: 40,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}
