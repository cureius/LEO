import SwiftUI
import EventKit

@MainActor
struct CalendarImportExportView: View {
    @Environment(AppEnvironment.self) private var appEnv

    // Import state
    @State private var subscribedCount = 0
    @State private var isImporting = false
    @State private var importResult: ImportResult? = nil
    @State private var showCleanSlateConfirm = false

    // Export state
    @State private var writableCalendars: [EKCalendar] = []
    @State private var selectedExportCalendarID: String? = nil
    @State private var exportableCount = 0
    @State private var isExporting = false
    @State private var exportResult: ExportResult? = nil

    // Auth
    @State private var hasCalendarAccess = false

    var body: some View {
        List {
            if !hasCalendarAccess {
                Section {
                    Label("Calendar access is required. Grant access in Settings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Color.warning)
                        .font(.caption)
                }
            }

            importSection
            exportSection
        }
        .navigationTitle("Import & Export")
        .task { await loadState() }
        .confirmationDialog(
            "Replace all synced events?",
            isPresented: $showCleanSlateConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace from System", role: .destructive) {
                Task { await runImport(cleanSlate: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all calendar-synced events from LEO and re-imports them fresh from your selected calendars. LEO-native items are not affected.")
        }
    }

    // MARK: - Import section

    @ViewBuilder
    private var importSection: some View {
        Section {
            if subscribedCount == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No calendars selected", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(Theme.Color.warning)
                    Text("Go to Calendars & Reminders to pick which calendars to sync.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            } else {
                Label("\(subscribedCount) calendar\(subscribedCount == 1 ? "" : "s") selected", systemImage: "calendar")
                    .foregroundStyle(Theme.Color.textSecondary)
                    .font(.caption)
            }

            // Additive import
            Button {
                Task { await runImport(cleanSlate: false) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Merge into LEO")
                            .foregroundStyle(subscribedCount == 0 || isImporting ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        Text("Adds new events and updates changed ones. Your LEO items are untouched.")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    if isImporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(subscribedCount == 0 || isImporting || isExporting || !hasCalendarAccess)

            // Clean slate import
            Button(role: .destructive) {
                showCleanSlateConfirm = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace from System")
                    Text("Removes all synced events and re-imports everything fresh.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .disabled(subscribedCount == 0 || isImporting || isExporting || !hasCalendarAccess)

            if let result = importResult {
                importResultRow(result)
            }
        } header: {
            Text("Import from System Calendar")
        }
    }

    @ViewBuilder
    private func importResultRow(_ result: ImportResult) -> some View {
        switch result {
        case .success(let report):
            let parts: [String] = [
                report.imported > 0 ? "+\(report.imported)" : nil,
                report.updated  > 0 ? "~\(report.updated)"  : nil,
                report.removed  > 0 ? "-\(report.removed)"  : nil,
            ].compactMap { $0 }
            Label(
                parts.isEmpty ? "Already up to date" : parts.joined(separator: "  "),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(Theme.Color.success)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Color.danger)
        }
    }

    // MARK: - Export section

    @ViewBuilder
    private var exportSection: some View {
        Section {
            if exportableCount == 0 {
                Text("No LEO-native events to export.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                Label(
                    "\(exportableCount) LEO event\(exportableCount == 1 ? "" : "s") not yet in system calendar",
                    systemImage: "calendar.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            }

            if !writableCalendars.isEmpty {
                Picker("Export to", selection: $selectedExportCalendarID) {
                    Text("Default calendar").tag(String?.none)
                    ForEach(writableCalendars, id: \.calendarIdentifier) { cal in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 10, height: 10)
                            Text(cal.title)
                        }
                        .tag(Optional(cal.calendarIdentifier))
                    }
                }
            }

            Button {
                Task { await runExport() }
            } label: {
                HStack {
                    Text("Export to Calendar")
                        .foregroundStyle(exportableCount == 0 || isExporting ? Theme.Color.textSecondary : Theme.Color.accent)
                    Spacer()
                    if isExporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(exportableCount == 0 || isExporting || isImporting || !hasCalendarAccess)

            if let result = exportResult {
                exportResultRow(result)
            }
        } header: {
            Text("Export to System Calendar")
        } footer: {
            Text("Exports events you created in LEO that haven't been synced to a system calendar yet.")
        }
    }

    @ViewBuilder
    private func exportResultRow(_ result: ExportResult) -> some View {
        switch result {
        case .success(let count):
            Label(count == 0 ? "Nothing to export" : "Exported \(count) event\(count == 1 ? "" : "s")",
                  systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Color.success)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.Color.danger)
        }
    }

    // MARK: - Actions

    private func loadState() async {
        let bridge = appEnv.eventKitBridge
        let status = await bridge.requestEventsAccess()
        hasCalendarAccess = (status == .fullAccess)

        let subIDs = await bridge.subscribedCalendars
        subscribedCount = subIDs.count

        writableCalendars = await bridge.writableCalendars()

        let all = (try? await appEnv.itemRepository.fetch()) ?? []
        exportableCount = all.filter { item in
            guard let ev = item as? EventItem else { return false }
            return ev.externalRef == nil && !ev.anchor.isUntimed
        }.count
    }

    private func runImport(cleanSlate: Bool) async {
        isImporting = true
        importResult = nil
        defer { isImporting = false }
        do {
            let report = cleanSlate
                ? try await appEnv.eventKitBridge.cleanSlateSync()
                : try await appEnv.eventKitBridge.sync()
            importResult = .success(report)
            // Refresh exportable count since the store changed
            let all = (try? await appEnv.itemRepository.fetch()) ?? []
            exportableCount = all.filter { item in
                guard let ev = item as? EventItem else { return false }
                return ev.externalRef == nil && !ev.anchor.isUntimed
            }.count
        } catch {
            importResult = .failure(error.localizedDescription)
        }
    }

    private func runExport() async {
        isExporting = true
        exportResult = nil
        defer { isExporting = false }
        do {
            let all = (try? await appEnv.itemRepository.fetch()) ?? []
            let count = try await appEnv.eventKitBridge.exportToSystem(
                items: all,
                calendarID: selectedExportCalendarID
            )
            exportResult = .success(count)
            exportableCount = max(0, exportableCount - count)
        } catch {
            exportResult = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Result types

private enum ImportResult {
    case success(EKSyncReport)
    case failure(String)
}

private enum ExportResult {
    case success(Int)
    case failure(String)
}

#Preview {
    NavigationStack {
        CalendarImportExportView()
            .environment(AppEnvironment(useInMemory: true))
    }
}
