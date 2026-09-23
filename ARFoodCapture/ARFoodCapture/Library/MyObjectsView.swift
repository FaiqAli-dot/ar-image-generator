import SwiftUI

struct MyObjectsView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var store: ObjectLibraryStore

    var body: some View {
        ZStack {
            ScreenBackground()
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

                Text("MY OBJECTS")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                if store.objects.isEmpty {
                    Text("No objects yet. Capture a dish to begin.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.objects) { object in
                                Button {
                                    path.append(Route.detail(id: object.id))
                                } label: {
                                    ObjectRow(object: object)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(24)
        }
        .navigationBarHidden(true)
    }
}

struct ObjectRow: View {
    @EnvironmentObject private var store: ObjectLibraryStore
    let object: FoodObject

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let thumb = store.loadThumbnail(for: object) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(object.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if object.isDemo {
                        Text("DEMO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    SyncStateBadge(state: object.syncState)
                }
                Text(object.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Text("\(object.viewCount) views · \(Int(object.widthCm)) cm")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

struct SyncStateBadge: View {
    let state: ObjectSyncState

    var body: some View {
        Text(state.badgeTitle)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch state {
        case .failed: return .white
        case .uploading: return .black
        default: return .white.opacity(0.9)
        }
    }

    private var background: Color {
        switch state {
        case .local: return Color.white.opacity(0.12)
        case .uploading: return AppTheme.accent.opacity(0.85)
        case .remote: return Color.blue.opacity(0.45)
        case .ready: return Color.green.opacity(0.45)
        case .failed: return Color.red.opacity(0.55)
        }
    }
}

struct ObjectDetailView: View {
    @Binding var path: NavigationPath
    let objectID: String
    @EnvironmentObject private var store: ObjectLibraryStore
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var confirmDelete = false
    @State private var showQR = false

    var object: FoodObject? {
        store.object(id: objectID) ?? store.reloadObject(id: objectID)
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            if let object {
                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            Button { path.removeLast() } label: {
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Color.white.opacity(0.08), in: Circle())
                            }
                            Spacer()
                            SyncStateBadge(state: object.syncState)
                        }

                        if let thumb = store.loadThumbnail(for: object) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                        }

                        Text(object.name)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("\(object.viewCount) photographic views · \(object.widthCm, specifier: "%.0f") cm wide")
                            .foregroundStyle(AppTheme.textSecondary)

                        if let err = object.lastUploadError, object.syncState == .failed {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }

                        if let arUrl = object.arUrl, object.isRemoteAvailable {
                            RemoteSharePanel(arUrl: arUrl, deepLink: object.deepLink)
                        }

                        Button("VIEW IN AR") {
                            path.append(Route.ar(id: object.id))
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if object.syncState == .local || object.syncState == .failed || (object.isDemo && !object.isRemoteAvailable) {
                            Button(object.syncState == .failed ? "RETRY UPLOAD" : "UPLOAD OBJECT") {
                                path.append(Route.upload(id: object.id))
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                        }

                        if object.isRemoteAvailable, object.arUrl != nil {
                            Button("QR CODE") {
                                showQR = true
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                        }

                        Button("RECENTRE") {
                            path.append(Route.ar(id: object.id))
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))

                        Button("SHARE PACKAGE") {
                            do {
                                shareURL = try ObjectExporter.makeSharePackage(for: object, store: store)
                                showShare = true
                            } catch {
                                // silent
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))

                        if !object.isDemo {
                            Button("DELETE") {
                                confirmDelete = true
                            }
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(.top, 8)
                        }
                    }
                    .padding(28)
                }
                .confirmationDialog("Delete this object?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        try? store.delete(object)
                        path.removeLast()
                    }
                }
                .sheet(isPresented: $showShare) {
                    if let shareURL {
                        ShareSheet(items: [shareURL])
                    }
                }
                .sheet(isPresented: $showQR) {
                    if let arUrl = object.arUrl {
                        ObjectQRView(arUrl: arUrl, title: object.name)
                    }
                }
            } else {
                Text("Missing object").foregroundStyle(.white)
            }
        }
        .navigationBarHidden(true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
