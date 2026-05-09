import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var showDebugMenu = false
    @State private var onboardingDone = UserDefaults.standard.hasCompletedOnboarding

    var body: some View {
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
