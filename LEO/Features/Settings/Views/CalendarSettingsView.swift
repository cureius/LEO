import SwiftUI
import EventKit

/// Lets the user pick which iOS calendars and reminder lists to sync into LEO.
/// Calendars are grouped by their account (iCloud, Gmail/Google, Exchange, etc.) so
/// users with multiple Google accounts can see at a glance which account each
/// calendar belongs to and bulk-toggle a whole account.
@MainActor
struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var calendarGroups: [(source: EKSource, calendars: [EKCalendar])] = []
    @State private var reminderLists: [EKCalendar] = []
    @State private var selectedCalendarIDs: Set<String> = loadSavedCalendarIDs()
    @State private var selectedReminderListIDs: Set<String> = loadSavedReminderListIDs()
    @State private var syncReport: String? = nil
    @State private var isSyncing = false
    @State private var authStatus: String = ""

    var body: some View {
        List {
            if !authStatus.isEmpty {
                Section {
                    Text(authStatus)
                        .foregroundStyle(Theme.Color.warning)
                        .font(.caption)
                }
            }

            // Add-account section — deep links to iOS Settings → Calendar → Accounts
            Section {
                Button {
                    openIOSCalendarSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Theme.Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Google or other account")
                                .font(Theme.Typography.body.weight(.semibold))
                                .foregroundStyle(Theme.Color.textPrimary)
                            Text("Opens iOS Settings → Calendar → Accounts. Then come back to enable the new calendars below.")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }

            // One section per source (Gmail account, iCloud, Exchange, etc.)
            ForEach(calendarGroups, id: \.source.sourceIdentifier) { group in
                calendarSection(for: group.source, calendars: group.calendars)
            }

            if !reminderLists.isEmpty {
                Section("Reminders") {
                    ForEach(reminderLists, id: \.calendarIdentifier) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { selectedReminderListIDs.contains(list.calendarIdentifier) },
                            set: { on in
                                if on { selectedReminderListIDs.insert(list.calendarIdentifier) }
                                else  { selectedReminderListIDs.remove(list.calendarIdentifier) }
                                saveReminderListIDs(selectedReminderListIDs)
                                Task { await pushSubscription() }
                            }
                        ))
                    }
                }
            }

            Section {
                Button {
                    Task { await syncNow() }
                } label: {
                    HStack {
                        Text("Sync now")
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing)

                if let report = syncReport {
                    Text(report)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
        .navigationTitle("Calendars & Reminders")
        .task { await loadCalendars() }
    }

    // MARK: - Per-source section

    @ViewBuilder
    private func calendarSection(for source: EKSource, calendars: [EKCalendar]) -> some View {
        let calendarIDs = calendars.map(\.calendarIdentifier)
        let selectedInGroup = calendarIDs.filter { selectedCalendarIDs.contains($0) }.count
        let allSelected = selectedInGroup == calendarIDs.count
        let noneSelected = selectedInGroup == 0

        Section {
            // Header row with master toggle
            HStack(spacing: 12) {
                Image(systemName: sourceIcon(for: source))
                    .font(.title3)
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(Theme.Typography.body.weight(.semibold))
                    Text("\(selectedInGroup) of \(calendarIDs.count) syncing")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { on in
                        if on { selectedCalendarIDs.formUnion(calendarIDs) }
                        else  { selectedCalendarIDs.subtract(calendarIDs) }
                        saveCalendarIDs(selectedCalendarIDs)
                        Task { await pushSubscription() }
                    }
                ))
                .labelsHidden()
                // Show indeterminate state with a hint of opacity when mixed
                .opacity(noneSelected || allSelected ? 1.0 : 0.65)
            }

            ForEach(calendars, id: \.calendarIdentifier) { cal in
                Toggle(isOn: Binding(
                    get: { selectedCalendarIDs.contains(cal.calendarIdentifier) },
                    set: { on in
                        if on { selectedCalendarIDs.insert(cal.calendarIdentifier) }
                        else  { selectedCalendarIDs.remove(cal.calendarIdentifier) }
                        saveCalendarIDs(selectedCalendarIDs)
                        Task { await pushSubscription() }
                    }
                )) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: 10, height: 10)
                        Text(cal.title)
                    }
                }
                .tint(Color(cgColor: cal.cgColor))
                .padding(.leading, 36)
            }
        }
    }

    private func sourceIcon(for source: EKSource) -> String {
        switch source.sourceType {
        case .calDAV:
            // iCloud uses CalDAV under the hood; Google does too when added via iOS Settings.
            if source.title.localizedCaseInsensitiveContains("icloud") { return "icloud.fill" }
            if source.title.localizedCaseInsensitiveContains("gmail") ||
               source.title.localizedCaseInsensitiveContains("google") { return "envelope.fill" }
            return "globe"
        case .exchange:    return "building.2.fill"
        case .subscribed:  return "antenna.radiowaves.left.and.right"
        case .local:       return "iphone"
        case .birthdays:   return "gift.fill"
        case .mobileMe:    return "icloud"
        @unknown default:  return "calendar"
        }
    }

    // MARK: - Loading & sync

    private func loadCalendars() async {
        let bridge = appEnv.eventKitBridge
        let eventsStatus = await bridge.requestEventsAccess()
        let remindersStatus = await bridge.requestRemindersAccess()

        if eventsStatus != .fullAccess && remindersStatus != .fullAccess {
            authStatus = "Calendar and Reminders access not granted. Go to Settings to enable."
        } else if eventsStatus != .fullAccess {
            authStatus = "Calendar access not granted."
        } else if remindersStatus != .fullAccess {
            authStatus = "Reminders access not granted."
        } else {
            authStatus = ""
        }

        // Ask iOS to pull latest from CalDAV (Google, iCloud) so newly-added accounts show up.
        await bridge.refreshSources()
        calendarGroups = await bridge.calendarsGroupedBySource()
        reminderLists = await bridge.availableReminderLists()
        await pushSubscription()
    }

    private func pushSubscription() async {
        await appEnv.eventKitBridge.subscribe(
            calendarIDs: selectedCalendarIDs,
            reminderListIDs: selectedReminderListIDs
        )
    }

    private func syncNow() async {
        isSyncing = true
        syncReport = "Pulling from server…"
        defer { isSyncing = false }
        await pushSubscription()

        // Kick off a CalDAV pull. EKEventStoreChanged fires when iOS finishes.
        // We race that notification against a 6-second timeout so manual sync
        // doesn't hang forever if the server has nothing new to report.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.appEnv.eventKitBridge.refreshSources() }
            group.addTask {
                // Wait for the signal that iOS has finished pulling from CalDAV
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged).prefix(1) {}
            }
            group.addTask { try? await Task.sleep(for: .seconds(6)) }
            // Proceed as soon as ANY of the above finishes
            _ = await group.next()
            group.cancelAll()
        }

        do {
            let report = try await appEnv.eventKitBridge.sync()
            if report.imported == 0 && report.updated == 0 && report.removed == 0 {
                syncReport = "Already up to date"
            } else {
                syncReport = "Imported \(report.imported), updated \(report.updated), removed \(report.removed)"
            }
        } catch {
            syncReport = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func openIOSCalendarSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        #endif
    }
}

// MARK: - UserDefaults persistence

private func loadSavedCalendarIDs() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_calendar_ids") ?? [])
}

private func loadSavedReminderListIDs() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_reminder_list_ids") ?? [])
}

private func saveCalendarIDs(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids), forKey: "ek_subscribed_calendar_ids")
}

private func saveReminderListIDs(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids), forKey: "ek_subscribed_reminder_list_ids")
}
