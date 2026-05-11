import SwiftUI
import UserNotifications

private let onboardingDoneKey = "onboarding_complete"

struct OnboardingFlow: View {
    let onComplete: () -> Void
    @Environment(AppEnvironment.self) private var appEnv
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            OnboardingPage1().tag(0)
            OnboardingPage2().tag(1)
            OnboardingPage3(onNext: { page = 3 }).tag(2)
            OnboardingPage4(onNext: { page = 4 }).tag(3)
            OnboardingPageGym(bodyProfileRepository: appEnv.bodyProfileRepository, onDone: {
                UserDefaults.standard.set(true, forKey: onboardingDoneKey)
                onComplete()
            }).tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .tint(Theme.Color.accent)
    }
}

// MARK: - Check whether onboarding is needed

extension UserDefaults {
    var hasCompletedOnboarding: Bool {
        bool(forKey: onboardingDoneKey)
    }
}

// MARK: - Page 1: Capture demo

private struct OnboardingPage1: View {
    @State private var demoText = ""
    @State private var parsedResult: String? = nil

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Color.accent)
            Text("Capture in three seconds")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Type anything — LEO understands time, priority, and intent naturally.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)

            TextField("Try: \"dentist tuesday 3pm\" or \"buy milk\"", text: $demoText)
                .padding()
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .onSubmit { tryParse() }

            if let result = parsedResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(Theme.Color.success)
            }

            Text("Swipe to continue →")
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .padding(32)
    }

    private func tryParse() {
        Task {
            let result = await DeterministicParser().parse(demoText)
            parsedResult = result.draft.map { "Parsed: \($0.title) — \(result.rationale)" }
        }
    }
}

// MARK: - Page 2: Ask LEO demo

private struct OnboardingPage2: View {
    @State private var showCannedResponse = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Color.accent)
            Text("Ask LEO anything")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text("LEO uses AI to help you plan, reschedule, and think clearly — without you doing the work.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)

            if showCannedResponse {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You: \"I'm slammed Wednesday. What should I push?\"")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text("LEO: I found 3 items on Wednesday that could move. I propose shifting the weekly review to Thursday and the vendor call to Friday morning when you have a free slot. Want to apply these changes?")
                        .font(Theme.Typography.body)
                        .padding()
                        .background(Theme.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            } else {
                Button("See LEO in action") {
                    withAnimation { showCannedResponse = true }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(32)
    }
}

// MARK: - Page 3: Permissions

private struct OnboardingPage3: View {
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Color.accent)
                Text("A few permissions")
                    .font(.system(size: 28, weight: .bold))
                Text("LEO needs these to work well. You can grant them now or later in Settings.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)

                PermissionRow(icon: "bell.fill", title: "Notifications", description: "Reminders, alarms, and habit check-ins.") {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                }
                PermissionRow(icon: "calendar", title: "Calendars", description: "Sync your iOS calendars with LEO.") {}
                PermissionRow(icon: "location.fill", title: "Location (When In Use)", description: "Location-based reminders.") {}

                Button("Continue") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
            }
            .padding(32)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let onGrant: () async -> Void
    @State private var granted = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.body.bold())
                Text(description).font(.caption).foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            Button(granted ? "Granted" : "Allow") {
                Task { await onGrant(); granted = true }
            }
            .buttonStyle(.bordered)
            .disabled(granted)
        }
        .padding()
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

// MARK: - Page 4: Connect calendars

private struct OnboardingPage4: View {
    let onNext: () -> Void
    var onDone: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.Color.accent)
                Text("Connect your calendars")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("LEO mirrors any calendar you've added to iOS — iCloud, Gmail, Google Workspace, Exchange.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Have multiple Google accounts?")
                        .font(Theme.Typography.body.weight(.semibold))
                    Text("Add each one in **iOS Settings → Calendar → Accounts → Add Account → Google**. LEO will see all of them.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open iOS Settings")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Text("You'll pick which calendars to sync in Settings → Calendars & Reminders.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button("Continue") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
    }
}
