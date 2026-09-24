import SwiftUI

struct CaptureInstructionsView: View {
    @Binding var path: NavigationPath

    private let steps: [(String, String)] = [
        ("1", "Put the food on a lazy Susan / turntable with even light."),
        ("2", "Prop the phone ~40–50 cm away so the whole dish is in frame — then FREEZE the phone."),
        ("3", "Rotate only the dish. Do not walk around. Do not spin or flip the phone."),
        ("4", "Each step: rotate the dish ~10°, tap CAPTURE NEXT. Green frame = phone still enough to shoot."),
        ("5", "Pass 2: raise the phone ~15 cm and tilt down a little once, freeze again, then rotate the dish through 360° — never a 180° phone flip.")
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

                Text("Phone stays put · dish rotates · ~72 photos")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("CAPTURE NEXT always works. Object angle is the dish orientation — never phone yaw. Spinning the phone will not capture angles correctly.")
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
