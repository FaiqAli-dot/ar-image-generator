import SwiftUI

struct CaptureInstructionsView: View {
    @Binding var path: NavigationPath

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

                Text("Place the food on a flat surface.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 12) {
                    tip("Keep the food still")
                    tip("Use good lighting")
                    tip("Keep the camera at a consistent distance")
                    tip("Make sure the entire food item is visible")
                }
                .padding(.top, 8)

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

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .foregroundStyle(AppTheme.textSecondary)
                .font(.system(size: 16, weight: .medium, design: .rounded))
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
