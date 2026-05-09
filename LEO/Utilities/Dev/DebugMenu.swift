import SwiftUI

#if DEBUG
struct DebugMenu: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var seeding = false
    @State private var wiping = false
    @State private var showDesignSystem = false
    @State private var showDBBrowser = false
    @State private var showConfirmWipe = false
    @State private var statusMessage: String? = nil

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    var body: some View {
        NavigationStack {
            List {
                buildInfoSection
                databaseSection
                dataSection
                uiSection
                metricsSection
            }
            .navigationTitle("Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDesignSystem) { DesignSystemPreview() }
            .confirmationDialog("Wipe all data?", isPresented: $showConfirmWipe, titleVisibility: .visible) {
                Button("Wipe everything", role: .destructive) { Task { await wipeAll() } }
                Button("Cancel", role: .cancel) {}
            }
            .overlay(alignment: .bottom) {
                if let msg = statusMessage {
                    Text(msg)
                        .font(Theme.Typography.callout)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Color.surface)
                        .clipShape(Capsule())
                        .padding(.bottom, Theme.Spacing.xxl)
                        .onAppear {
                            Task { try? await Task.sleep(for: .seconds(2)); statusMessage = nil }
                        }
                }
            }
        }
    }

    private var buildInfoSection: some View {
        Section("Build") {
            LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "?")
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
        }
    }

    private var databaseSection: some View {
        Section("Database") {
            // Show the path so you can find the file in Xcode's container download
            if let dbURL = dbURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SQLite path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dbURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)   // long-press to copy
                }
                .padding(.vertical, 4)

                Button {
                    UIPasteboard.general.string = dbURL.path
                    statusMessage = "Path copied to clipboard"
                } label: {
                    Label("Copy path to clipboard", systemImage: "doc.on.doc")
                }

                LabeledContent("File exists", value: FileManager.default.fileExists(atPath: dbURL.path) ? "Yes" : "No")
                if let size = dbFileSize(dbURL) {
                    LabeledContent("File size", value: size)
                }
            } else {
                Text("Database URL not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dbURL: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("LEO.store")
    }

    private func dbFileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        let kb = Double(bytes) / 1024
        return kb < 1024 ? String(format: "%.1f KB", kb) : String(format: "%.2f MB", kb / 1024)
    }

    private var dataSection: some View {
        Section("Data") {
            Button {
                Task { await seedData() }
            } label: {
                Label(seeding ? "Seeding…" : "Seed 100 items", systemImage: "plus.circle.fill")
            }
            .disabled(seeding)

            Button(role: .destructive) {
                showConfirmWipe = true
            } label: {
                Label("Wipe all data", systemImage: "trash.fill")
            }
            .disabled(wiping)

            Button {
                Task { await forceSchemaSeed() }
            } label: {
                Label("Force CloudKit schema seed", systemImage: "icloud.and.arrow.up")
            }
        }
    }

    private var uiSection: some View {
        Section("UI & Inspection") {
            NavigationLink {
                DatabaseBrowserView()
                    .environment(appEnv)
            } label: {
                Label("Database browser", systemImage: "tablecells")
            }

            Button { showDesignSystem = true } label: {
                Label("Design system preview", systemImage: "paintbrush")
            }
        }
    }

    private var metricsSection: some View {
        Section("Metrics") {
            Text("MetricKit log available in Xcode console (category: metrics)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private func seedData() async {
        seeding = true
        defer { seeding = false }
        do {
            let seeder = Seeder()
            try await seeder.seedAll(itemRepository: appEnv.itemRepository, habitRepository: appEnv.habitRepository)
            statusMessage = "Seeded OK"
            // Single notification after all writes settle
            NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        } catch {
            statusMessage = "Seed failed: \(error.localizedDescription)"
        }
    }

    private func wipeAll() async {
        wiping = true
        defer { wiping = false }
        let ctx = appEnv.persistenceController.mainContext
        do {
            try ctx.delete(model: StoredTask.self)
            try ctx.delete(model: StoredEvent.self)
            try ctx.delete(model: StoredReminder.self)
            try ctx.delete(model: StoredAlarm.self)
            try ctx.delete(model: StoredHabitInstance.self)
            try ctx.delete(model: StoredHabit.self)
            try ctx.save()
            statusMessage = "All data wiped"
            NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        } catch {
            statusMessage = "Wipe failed: \(error.localizedDescription)"
        }
    }

    private func forceSchemaSeed() async {
        do {
            try await SchemaSync.forceSeed(controller: appEnv.persistenceController)
            statusMessage = "Schema seed complete"
        } catch {
            statusMessage = "Schema seed failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DebugMenu()
        .environment(AppEnvironment(useInMemory: true))
}
#endif
