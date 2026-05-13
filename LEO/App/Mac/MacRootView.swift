import SwiftUI

private let leoOnboardingKey = "onboarding_complete"

struct MacRootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var nav = MacNavigationModel()
    @State private var onboardingDone = UserDefaults.standard.bool(forKey: leoOnboardingKey)

    var body: some View {
        if onboardingDone {
            MacShellView()
                .environment(nav)
        } else {
            macOnboardingPlaceholder
        }
    }

    // Onboarding implemented in MM8-T01
    private var macOnboardingPlaceholder: some View {
        VStack(spacing: 20) {
            Text("Welcome to LEO")
                .font(.largeTitle.bold())
            Text("Your AI-first personal operating system.")
                .foregroundStyle(.secondary)
            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: leoOnboardingKey)
                onboardingDone = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: 720, height: 540)
    }
}
