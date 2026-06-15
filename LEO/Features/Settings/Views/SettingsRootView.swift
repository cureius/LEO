import SwiftUI

@MainActor
struct SettingsRootView: View {
    @State private var searchText = ""
    @State private var sheetRoute: SettingsRoute? = nil
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    // Grouped catalog of all navigable settings — drives both the layout and search.
    private var groups: [(title: String, entries: [SettingsEntry])] {
        var result: [(title: String, entries: [SettingsEntry])] = [
            ("General", [
                .init(title: "Appearance", subtitle: "Theme & how LEO looks",
                      icon: "paintpalette.fill", color: .indigo,
                      keywords: ["theme", "dark", "light", "mode", "color"], route: .appearance),
                .init(title: "Notifications", subtitle: "Permissions & persistent reminders",
                      icon: "bell.badge.fill", color: .red,
                      keywords: ["alerts", "reminders", "permission", "persistent", "push"], route: .notifications),
                .init(title: "Cloud Sync", subtitle: "Live sync & cloud backup across devices",
                      icon: "icloud.fill", color: .cyan,
                      keywords: ["sync", "cloud", "supabase", "backup", "account", "sign in", "devices"], route: .cloudSync),
            ]),
            ("Calendar", [
                .init(title: "Calendars & Reminders", subtitle: "Sync Google, iCloud & more",
                      icon: "calendar", color: .orange,
                      keywords: ["google", "icloud", "sync", "events", "subscribe"], route: .calendars),
                .init(title: "Import & Export", subtitle: "Move calendar data in and out",
                      icon: "square.and.arrow.up", color: .blue,
                      keywords: ["ics", "csv", "export", "import"], route: .importExport),
            ]),
            ("Fitness", [
                .init(title: "Gym Companion", subtitle: "Body profile, workouts & meals",
                      icon: "dumbbell.fill", color: .green,
                      keywords: ["fitness", "workout", "meal", "body", "gym", "weight"], route: .fitness),
            ]),
            ("Intelligence", [
                .init(title: "AI", subtitle: "API key & model routing",
                      icon: "sparkles", color: .purple,
                      keywords: ["claude", "api", "key", "routing", "opus", "model"], route: .ai),
                .init(title: "AI Usage", subtitle: "Tokens used this month",
                      icon: "chart.bar.fill", color: .purple,
                      keywords: ["tokens", "cost", "usage", "spend"], route: .aiUsage),
            ]),
            ("Data", [
                .init(title: "Backup & Restore", subtitle: "Snapshot or restore your data",
                      icon: "externaldrive.fill", color: .teal,
                      keywords: ["backup", "restore", "snapshot", "export", "import"], route: .backup),
            ]),
            ("Support", [
                .init(title: "Send Feedback", subtitle: "Report a bug or share an idea",
                      icon: "envelope.fill", color: .blue,
                      keywords: ["feedback", "bug", "contact", "email", "support"], route: .feedback,
                      presentsSheet: true),
                .init(title: "Beta Info", subtitle: "About this beta build",
                      icon: "info.circle.fill", color: .gray,
                      keywords: ["beta", "build", "version", "testflight"], route: .betaInfo),
            ]),
            ("Subscription", [
                .init(title: "Upgrade to Pro", subtitle: "Unlock everything",
                      icon: "crown.fill", color: .yellow,
                      keywords: ["pro", "premium", "subscribe", "upgrade", "plan"], route: .paywall,
                      presentsSheet: true),
            ]),
        ]
        #if DEBUG
        result.append(("Developer", [
            .init(title: "Debug Menu", subtitle: "Internal tools",
                  icon: "ladybug.fill", color: .gray,
                  keywords: ["debug", "developer", "logs"], route: .debug,
                  presentsSheet: true),
        ]))
        #endif
        return result
    }

    private var allEntries: [SettingsEntry] { groups.flatMap(\.entries) }

    private var filteredEntries: [SettingsEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return allEntries.filter { $0.matches(q) }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            SettingsRow(entry: entry, onSheet: { sheetRoute = $0 }) {
                                destination(for: entry.route)
                            }
                        }
                    }
                }
                aboutSection
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section {
                    ForEach(filteredEntries) { entry in
                        SettingsRow(entry: entry, onSheet: { sheetRoute = $0 }) {
                            destination(for: entry.route)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search settings")
        #else
        .searchable(text: $searchText, prompt: "Search settings")
        #endif
        .sheet(item: $sheetRoute) { destination(for: $0) }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent {
                Text(appVersion).foregroundStyle(Theme.Color.textSecondary)
            } label: {
                rowLabel("Version", icon: "number", color: .gray)
            }
            Link(destination: URL(string: "https://leo.app/privacy")!) {
                rowLabel("Privacy Policy", icon: "lock.fill", color: .gray)
            }
            Link(destination: URL(string: "https://leo.app/terms")!) {
                rowLabel("Terms of Service", icon: "doc.text.fill", color: .gray)
            }
        }
    }

    private func rowLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: icon, color: color)
            Text(title).foregroundStyle(Theme.Color.textPrimary)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .appearance:    AppearanceSettingsPage()
        case .notifications: NotificationsSettingsPage()
        case .cloudSync:     CloudSyncView()
        case .calendars:     CalendarSettingsView()
        case .importExport:  CalendarImportExportView()
        case .fitness:       FitnessSettingsView()
        case .ai:            AISettingsPage()
        case .aiUsage:       AIUsageView()
        case .backup:        DataSnapshotView()
        case .feedback:
            #if os(iOS)
            FeedbackView()
            #else
            Text("Email feedback@leo.app").padding()
            #endif
        case .betaInfo:
            Text("Thank you for being a beta tester! Report any issues via Send Feedback. Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                .padding()
                .navigationTitle("Beta Info")
        case .paywall:
            #if os(iOS)
            PaywallView()
            #else
            Text("Mac paywall — MM8-T03").padding()
            #endif
        case .debug:
            #if os(iOS)
            DebugMenu()
            #else
            Text("Use ⌘⇧⌥D for debug menu on Mac")
            #endif
        }
    }
}

// MARK: - Settings catalog model

enum SettingsRoute: Hashable, Identifiable {
    case appearance, notifications, cloudSync, calendars, importExport, fitness
    case ai, aiUsage, backup, feedback, betaInfo, paywall, debug
    var id: SettingsRoute { self }
}

struct SettingsEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let keywords: [String]
    let route: SettingsRoute
    /// Self-contained screens (own NavigationStack + dismiss) are shown as sheets.
    var presentsSheet: Bool = false

    func matches(_ query: String) -> Bool {
        if title.lowercased().contains(query) { return true }
        if subtitle.lowercased().contains(query) { return true }
        return keywords.contains { $0.contains(query) }
    }
}

private struct SettingsRow<Destination: View>: View {
    let entry: SettingsEntry
    let onSheet: (SettingsRoute) -> Void
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        if entry.presentsSheet {
            Button { onSheet(entry.route) } label: {
                rowContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { destination() } label: { rowContent }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            IconTile(symbol: entry.icon, color: entry.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Color.textPrimary)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            if entry.presentsSheet {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.35))
            }
        }
        .padding(.vertical, 2)
    }
}

/// A small rounded colored tile with an SF Symbol — the iOS-settings idiom.
struct IconTile: View {
    let symbol: String
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color.gradient)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Nested pages

private struct AppearanceSettingsPage: View {
    @AppStorage("leo.appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue
    var body: some View {
        List {
            Section {
                AppearanceSwitcher(rawValue: $appearanceRaw)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Choose how LEO looks. “System” follows your device’s appearance.")
            }
        }
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct NotificationsSettingsPage: View {
    @Environment(AppEnvironment.self) private var appEnv
    @AppStorage("persistentRemindersEnabled") private var persistentRemindersEnabled: Bool = true
    var body: some View {
        List {
            Section {
                Button("Request permission") {
                    Task { _ = await appEnv.notificationManager.requestAuthorization() }
                }
            } footer: {
                Text("Allow LEO to deliver reminders and alerts.")
            }
            Section {
                Toggle("Persistent reminders", isOn: $persistentRemindersEnabled)
                    .onChange(of: persistentRemindersEnabled) { _, _ in
                        Task {
                            guard let items = try? await appEnv.itemRepository.fetch() else { return }
                            await appEnv.notificationManager.sync(for: items)
                        }
                    }
            } footer: {
                Text("Re-notify every minute until you act on a reminder.")
            }
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct AISettingsPage: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var hasAPIKey = false
    @State private var routingOverride = "none"
    @State private var showAPIKeyInput = false

    var body: some View {
        List {
            Section {
                Button(hasAPIKey ? "Update API key" : "Add API key") { showAPIKeyInput = true }
            } header: {
                Text("Claude API")
            } footer: {
                Text("Your key is stored securely in the device Keychain and never logged.")
            }

            Section("Model routing") {
                Picker("Routing", selection: $routingOverride) {
                    Text("Auto").tag("none")
                    Text("Always Opus").tag("always_opus")
                    Text("Prefer on-device").tag("prefer_on_device")
                }
                .pickerStyle(.inline)
                .onChange(of: routingOverride) { _, val in
                    Task { await AIRouter.shared.setOverride(AIRouter.Override(rawValue: val) ?? .none) }
                }
            }

            Section {
                NavigationLink("AI Usage") { AIUsageView() }
            }
        }
        .navigationTitle("AI")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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

// MARK: - Appearance

/// The three appearance choices the theme switcher offers.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// `nil` means "follow the system" for `preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// A row of tappable preview cards for picking the app appearance.
struct AppearanceSwitcher: View {
    @Binding var rawValue: String

    private var selected: AppearanceMode { AppearanceMode(rawValue: rawValue) ?? .system }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppearanceMode.allCases) { mode in
                AppearanceCard(mode: mode, isSelected: selected == mode) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        rawValue = mode.rawValue
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: rawValue)
    }
}

private struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                MiniPreview(mode: mode)
                    .frame(height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Color.accent : Theme.Color.divider,
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.Color.accent)
                                .padding(6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: isSelected ? Theme.Color.accent.opacity(0.3) : .clear,
                            radius: 8, y: 4)

                Label(mode.title, systemImage: mode.icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
            }
            .scaleEffect(isSelected ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tiny mock of the UI rendered in a given appearance, used inside the cards.
private struct MiniPreview: View {
    let mode: AppearanceMode

    private struct Palette { let bg: Color; let bar: Color }
    private let light = Palette(bg: Color(white: 0.96), bar: Color(white: 0.80))
    private let dark  = Palette(bg: Color(white: 0.09), bar: Color(white: 0.34))

    var body: some View {
        ZStack {
            switch mode {
            case .light:
                mock(light)
            case .dark:
                mock(dark)
            case .system:
                mock(light)
                mock(dark).clipShape(CornerTriangle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func mock(_ p: Palette) -> some View {
        p.bg.overlay(
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Theme.Color.accent).frame(width: 28, height: 6)
                Capsule().fill(p.bar).frame(width: 44, height: 6)
                Capsule().fill(p.bar).frame(width: 36, height: 6)
                Spacer()
            }
            .padding(12),
            alignment: .topLeading
        )
    }
}

/// Lower-right triangle — used to diagonally split the System preview.
private struct CornerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
