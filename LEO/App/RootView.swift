import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var showDebugMenu = false
    @State private var onboardingDone = UserDefaults.standard.hasCompletedOnboarding
    @AppStorage("leo.appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    var body: some View {
        content
            .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme)
            .animation(.easeInOut(duration: 0.35), value: appearanceRaw)
    }

    @ViewBuilder
    private var content: some View {
        if onboardingDone {
            AppTabView()
                #if DEBUG
                .onShake { showDebugMenu = true }
                .sheet(isPresented: $showDebugMenu) { DebugMenu() }
                #endif
        } else {
            OnboardingFlow {
                onboardingDone = true
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment(useInMemory: true))
}
