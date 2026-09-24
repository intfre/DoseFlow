import SwiftUI

@main
struct DoseFlowApp: App {
    @StateObject private var store = DoseFlowStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.refreshNotificationsIfNeeded()
                }
        }
    }
}
