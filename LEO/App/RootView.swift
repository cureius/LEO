import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        #if DEBUG
        ContentPlaceholderView()
            .onLongPressGesture(minimumDuration: 1.5) {
                // debug menu revealed via long press on placeholder in M0
            }
            .sheet(isPresented: .constant(false)) {
                DebugMenu()
            }
        #else
        ContentPlaceholderView()
        #endif
    }
}

private struct ContentPlaceholderView: View {
    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                Text("LEO")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Life Events Organizer")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment(useInMemory: true))
}
