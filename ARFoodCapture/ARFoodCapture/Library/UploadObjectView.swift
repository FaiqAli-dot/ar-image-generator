import SwiftUI

struct UploadObjectView: View {
    @Binding var path: NavigationPath
    let objectID: String

    @EnvironmentObject private var store: ObjectLibraryStore
    @ObservedObject private var uploader = ObjectUploadService.shared

    @State private var name: String = ""
    @State private var widthText: String = "12"
    @State private var descriptionText: String = ""
    @State private var errorMessage: String?
    @State private var result: UploadObjectResponse?
    @State private var isUploading = false

    private var object: FoodObject? {
        store.object(id: objectID) ?? store.reloadObject(id: objectID)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button {
                            path.removeLast()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        Spacer()
                    }

                    Text("UPLOAD OBJECT")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Store real transparent views on the server and get a permanent AR URL + QR.")
                        .foregroundStyle(AppTheme.textSecondary)

                    if let object, let thumb = store.loadThumbnail(for: object) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .frame(maxWidth: .infinity)
                    }

                    fieldLabel("Name")
                    TextField("Dish name", text: $name)
                        .textFieldStyle(DarkFieldStyle())

                    fieldLabel("Width (cm)")
                    TextField("12", text: $widthText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(DarkFieldStyle())

                    fieldLabel("Description (optional)")
                    TextField("Short description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(DarkFieldStyle())

                    if !APIConfig.isConfigured {
                        Text("API base URL is not configured. Set ARFoodAPIBaseURL in Info.plist.")
                            .foregroundStyle(.red.opacity(0.9))
                            .font(.footnote)
                    }

                    if isUploading {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(uploader.stage)
                                .foregroundStyle(AppTheme.textSecondary)
                            ProgressView(value: uploader.progress)
                                .tint(AppTheme.accent)
                            Button("CANCEL") {
                                uploader.cancel()
                                isUploading = false
                                markFailed(APIClientError.cancelled)
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    if let result {
                        RemoteSharePanel(arUrl: result.arUrl, deepLink: result.deepLink)
                        Button("VIEW IN AR") {
                            path.append(Route.ar(id: objectID))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button("DONE") {
                            path = NavigationPath()
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    } else if !isUploading {
                        Button("UPLOAD") {
                            Task { await startUpload() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!APIConfig.isConfigured)
                    }
                }
                .padding(24)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if let object {
                if name.isEmpty { name = object.name }
                if widthText == "12" || widthText.isEmpty {
                    widthText = String(Int(object.widthCm))
                }
                if descriptionText.isEmpty {
                    descriptionText = object.objectDescription ?? object.notes ?? ""
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1)
            .foregroundStyle(AppTheme.textSecondary)
    }

    private func startUpload() async {
        guard var object else { return }
        guard let width = Double(widthText.replacingOccurrences(of: ",", with: ".")), width > 0 else {
            errorMessage = "Enter a valid width in cm"
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }

        errorMessage = nil
        isUploading = true
        object.syncState = .uploading
        object.name = trimmedName
        object.widthCm = width
        object.objectDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        object.lastUploadError = nil
        try? store.updateMetadata(object)

        do {
            let response = try await uploader.upload(
                object: object,
                store: store,
                name: trimmedName,
                widthCm: width,
                description: object.objectDescription
            )
            object.syncState = .remote
            object.remoteId = response.id
            object.arUrl = response.arUrl
            object.deepLink = response.deepLink
            object.lastUploadError = nil
            try store.updateMetadata(object)
            result = response
            isUploading = false
        } catch {
            isUploading = false
            markFailed(error)
        }
    }

    private func markFailed(_ error: Error) {
        errorMessage = error.localizedDescription
        guard var object else { return }
        object.syncState = .failed
        object.lastUploadError = error.localizedDescription
        try? store.updateMetadata(object)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct DarkFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
            .foregroundStyle(.white)
    }
}

struct RemoteSharePanel: View {
    let arUrl: String
    let deepLink: String?
    @State private var copied = false
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 14) {
            Text("REMOTE AR READY")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            if let qr = QRCodeGenerator.image(from: arUrl) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(arUrl)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button(copied ? "COPIED" : "COPY URL") {
                    UIPasteboard.general.string = arUrl
                    copied = true
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))

                Button("SHARE") {
                    showShare = true
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            }

            if let deepLink {
                Text(deepLink)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [arUrl])
        }
    }
}

struct ObjectQRView: View {
    @Environment(\.dismiss) private var dismiss
    let arUrl: String
    let title: String

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 20) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    Spacer()
                }
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                RemoteSharePanel(arUrl: arUrl, deepLink: nil)
                Spacer()
            }
            .padding(24)
        }
    }
}
