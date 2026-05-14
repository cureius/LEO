import SwiftUI

/// Full macOS Settings window — wired via Settings scene in LEOMacApp.
struct MacSettingsScene: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        TabView {
            MacGeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            CalendarSettingsView()
                .environment(appEnv)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            FitnessSettingsView()
                .environment(appEnv)
                .tabItem { Label("Fitness", systemImage: "figure.run") }

            MacSyncPane()
                .environment(appEnv)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            MacAISettingsPane()
                .environment(appEnv)
                .tabItem { Label("AI", systemImage: "sparkles") }

            MacKeyboardSettingsPane()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(minWidth: 620, minHeight: 500)
        .padding()
    }
}

// MARK: - General

private struct MacGeneralSettingsPane: View {
    @AppStorage("leo.mac.today.mode") private var todayMode: String = "timeline"
    @AppStorage("leo.inspector.visible") private var inspectorVisible: Bool = true

    var body: some View {
        Form {
            Section("Today View") {
                Picker("Default mode", selection: $todayMode) {
                    Text("Timeline").tag("timeline")
                    Text("List").tag("list")
                }
                .pickerStyle(.segmented)
            }
            Section("Inspector") {
                Toggle("Show inspector by default", isOn: $inspectorVisible)
            }
            Section("Notifications") {
                Text("Notification permissions are managed in System Settings → Privacy & Security.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                Link("Privacy Policy", destination: URL(string: "https://leo.app/privacy")!)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sync

private struct MacSyncPane: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var syncing = false
    @State private var cloudKitDisabled = UserDefaults.standard.bool(forKey: "LEODisableCloudKitSync")

    var body: some View {
        Form {
            Section("iCloud Sync") {
                if let token = FileManager.default.ubiquityIdentityToken {
                    Label("Signed in to iCloud", systemImage: "checkmark.icloud")
                        .foregroundStyle(.green)
                    Text("Sync enabled. Items created on this Mac will appear on your iPhone automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Not signed in to iCloud", systemImage: "xmark.icloud")
                        .foregroundStyle(.red)
                    Text("Sign in to iCloud in System Settings to enable sync between your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.appleIDPreferences")!)
                    }
                }
                Toggle("Disable CloudKit sync (debug)", isOn: $cloudKitDisabled)
                    .onChange(of: cloudKitDisabled) { _, val in
                        UserDefaults.standard.set(val, forKey: "LEODisableCloudKitSync")
                    }
            }
            Section("EventKit") {
                Button(syncing ? "Syncing…" : "Sync calendars and reminders now") {
                    Task {
                        syncing = true
                        await appEnv.calendarSyncCoordinator.syncOnForeground()
                        syncing = false
                    }
                }
                .disabled(syncing)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct MacAISettingsPane: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var showAPIKeyInput = false
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = false

    var body: some View {
        Form {
            Section("Claude API") {
                Button(hasAPIKey ? "Update API key" : "Add API key") {
                    showAPIKeyInput = true
                }
            }
            Section("Routing") {
                Text("AI routing is configured automatically. On-device Foundation Models run on Apple Silicon Macs with Apple Intelligence enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { hasAPIKey = await appEnv.claudeClient.hasAPIKey }
        .sheet(isPresented: $showAPIKeyInput) {
            VStack(spacing: 16) {
                Text("Enter Claude API Key").font(.headline)
                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showAPIKeyInput = false }
                    Spacer()
                    Button("Save") {
                        Task {
                            await appEnv.claudeClient.setAPIKey(apiKeyInput)
                            hasAPIKey = true
                            showAPIKeyInput = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
    }
}

// MARK: - Keyboard shortcuts

private struct MacKeyboardSettingsPane: View {
    private struct Shortcut: Identifiable {
        let id = UUID(); let label: String; let combo: String
    }
    private let shortcuts: [Shortcut] = [
        .init(label: "New item", combo: "⌘N"),
        .init(label: "Toggle inspector", combo: "⌃⌥⌘I"),
        .init(label: "Quick Capture (global)", combo: "⌃⌥Space"),
        .init(label: "Today", combo: "⌘1"),
        .init(label: "Inbox", combo: "⌘2"),
        .init(label: "Habits", combo: "⌘3"),
        .init(label: "Ask LEO", combo: "⌘4"),
        .init(label: "Fitness", combo: "⌘5"),
        .init(label: "Complete item", combo: "⌘."),
        .init(label: "Reschedule item", combo: "⌘⇧R"),
        .init(label: "Delete item", combo: "⌘⌫"),
    ]

    var body: some View {
        Table(shortcuts) {
            TableColumn("Action") { Text($0.label) }
            TableColumn("Shortcut") { Text($0.combo).font(.system(.body, design: .monospaced)) }
        }
        .frame(minHeight: 300)
    }
}
