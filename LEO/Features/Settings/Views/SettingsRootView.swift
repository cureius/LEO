import SwiftUI

@MainActor
struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var showAPIKeyInput = false
    @State private var apiKeyInput = ""
    @State private var monthlyTokens: (input: Int, output: Int) = (0, 0)
    @State private var hasAPIKey = false
    @State private var routingOverride = "none"
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section("Calendars") {
                NavigationLink("Calendars & Reminders") {
                    CalendarSettingsView()
                }
            }

            Section("Fitness") {
                NavigationLink("Gym Companion") {
                    FitnessSettingsView()
                }
            }

            Section("AI") {
                NavigationLink("AI Usage") {
                    AIUsageView()
                }

                Button(hasAPIKey ? "Update API key" : "Add API key") {
                    showAPIKeyInput = true
                }

                Picker("Routing", selection: $routingOverride) {
                    Text("Auto").tag("none")
                    Text("Always Opus").tag("always_opus")
                    Text("Prefer on-device").tag("prefer_on_device")
                }
                .pickerStyle(.menu)
                .onChange(of: routingOverride) { _, val in
                    Task { await AIRouter.shared.setOverride(AIRouter.Override(rawValue: val) ?? .none) }
                }
            }

            Section("Notifications") {
                Button("Request permission") {
                    Task { _ = await appEnv.notificationManager.requestAuthorization() }
                }
            }

            Section("Support") {
                #if os(iOS)
                NavigationLink("Send feedback") { FeedbackView() }
                #else
                Link("Send feedback", destination: URL(string: "mailto:feedback@leo.app")!)
                #endif
                NavigationLink("Beta info") {
                    Text("Thank you for being a beta tester! Report any issues via Send feedback. Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                        .padding()
                        .navigationTitle("Beta info")
                }
            }

            Section("Subscription") {
                #if os(iOS)
                NavigationLink("Upgrade to Pro") { PaywallView() }
                #else
                NavigationLink("Upgrade to Pro") { Text("Mac paywall — MM8-T03").padding() }
                #endif
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Link("Privacy Policy", destination: URL(string: "https://leo.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://leo.app/terms")!)
                Link("Support", destination: URL(string: "mailto:feedback@leo.app")!)
            }

            #if DEBUG
            Section("Debug") {
                NavigationLink("Debug menu") {
                    #if os(iOS)
                    DebugMenu()
                    #else
                    Text("Use ⌘⇧⌥D for debug menu on Mac")
                    #endif
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .task {
            hasAPIKey = await appEnv.claudeClient.hasAPIKey
            routingOverride = await AIRouter.shared.routingOverride.rawValue
        }
        .sheet(isPresented: $showAPIKeyInput) {
            APIKeyInputView { key in
                Task { await appEnv.claudeClient.setAPIKey(key) }
            }
        }
    }
}

// MARK: - API Key input

private struct APIKeyInputView: View {
    let onSave: (String) -> Void
    @State private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Claude API Key") {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Your API key is stored securely in the device Keychain and never logged.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .navigationTitle("Add API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(key); dismiss() }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AI Usage view (M4-T06)

struct AIUsageView: View {
    @State private var records: [AIRequestRecord] = []
    @State private var monthlyTotal: (input: Int, output: Int) = (0, 0)

    var body: some View {
        List {
            Section("This month") {
                LabeledContent("Input tokens", value: "\(monthlyTotal.input.formatted())")
                LabeledContent("Output tokens", value: "\(monthlyTotal.output.formatted())")
            }

            Section("Recent requests") {
                if records.isEmpty {
                    Text("No AI requests yet.")
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    ForEach(records.reversed().prefix(20)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.model)
                                    .font(.caption.bold())
                                Spacer()
                                Text(r.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            Text("in:\(r.inputTokens) out:\(r.outputTokens) cached:\(r.cacheReadTokens)")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Usage")
        .task {
            let telemetry = AITelemetry.shared
            records = await telemetry.allRecords()
            monthlyTotal = await telemetry.totalTokensThisMonth()
        }
    }
}
