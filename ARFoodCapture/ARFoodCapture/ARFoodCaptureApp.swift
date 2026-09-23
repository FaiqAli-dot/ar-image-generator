import SwiftUI

@main
struct ARFoodCaptureApp: App {
    @ObservedObject private var store = ObjectLibraryStore.shared
    @StateObject private var deepLinks = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(deepLinks)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    deepLinks.pendingURL = url
                }
        }
    }
}
