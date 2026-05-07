import SwiftUI

/// Root tab bar. Replaces ContentPlaceholderView once M1 ships.
@MainActor
struct AppTabView: View {
    var body: some View {
        TabView {
            TodayTabView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(1)
        }
        .tint(Theme.Color.accent)
    }
}

#Preview {
    AppTabView()
        .environment(AppEnvironment(useInMemory: true))
}
