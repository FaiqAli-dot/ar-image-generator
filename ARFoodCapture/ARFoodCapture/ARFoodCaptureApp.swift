import SwiftUI

@main
struct ARFoodCaptureApp: App {
    @ObservedObject private var store = ObjectLibraryStore.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
