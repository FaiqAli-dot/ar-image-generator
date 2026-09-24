import SwiftUI

struct CaptureInstructionsView: View {
    @Binding var path: NavigationPath

    private let steps: [(String, String)] = [
        ("1", "Place the food on a flat surface with good, even light."),
        ("2", "Stand about 40–50 cm away so the whole dish stays in frame."),
        ("3", "You will walk a full circle twice — sides first, then slightly above."),
        ("4", "The app takes photos automatically. There is no shutter — do not tap to shoot."),
        ("5", "Move slowly so every tick on the ring fills in as you orbit.")
    ]

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(alignment: .leading, spacing: 24) {
                Button { path.removeLast() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: Circle())
                }

                Text("CAPTURE")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Guided walk-around — about 72 photos")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Photos capture from your motion. Walk slowly, keep the dish centered, and watch the ring fill in.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps, id: \.0) { step in
                        numberedStep(step.0, step.1)
                    }
                }
                .padding(.top, 4)

                Spacer()

                Button("START CAPTURE") {
                    path.append(Route.scale)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
        }
        .navigationBarHidden(true)
    }

    private func numberedStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 26, height: 26)
                .background(AppTheme.accent, in: Circle())
            Text(text)
                .foregroundStyle(AppTheme.textSecondary)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ScaleInputView: View {
    @Binding var path: NavigationPath
    @State private var widthText = "12"
    @State private var name = "My Food"

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(alignment: .leading, spacing: 22) {
                Button { path.removeLast() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.08), in: Circle())
                }

                Text("REAL-WORLD SCALE")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("How wide is the food? (centimeters)")
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("Width cm", text: $widthText)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                TextField("Name", text: $name)
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                Spacer()

                Button("CONTINUE") {
                    let width = Double(widthText.replacingOccurrences(of: ",", with: ".")) ?? 12
                    let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Food" : name
                    path.append(Route.capture(widthCm: width, name: label))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
        }
        .navigationBarHidden(true)
    }
}
