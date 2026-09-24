import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DoseFlowStore

    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("今日", systemImage: "checklist")
            }

            NavigationStack {
                PlanView()
            }
            .tabItem {
                Label("疗程", systemImage: "calendar")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("记录", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(DoseFlowTheme.accent)
        .alert(
            "药序",
            isPresented: Binding(
                get: { store.presentedMessage != nil },
                set: { if !$0 { store.presentedMessage = nil } }
            )
        ) {
            Button("知道了") { store.presentedMessage = nil }
        } message: {
            Text(store.presentedMessage ?? "")
        }
    }
}
