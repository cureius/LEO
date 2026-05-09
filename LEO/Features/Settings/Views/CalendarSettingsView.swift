import SwiftUI
import EventKit

/// Lets the user pick which iOS calendars and reminder lists to sync into LEO.
@MainActor
struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var calendars: [EKCalendar] = []
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

            Section("Calendars") {
                if calendars.isEmpty {
                    Text("No calendars available. Grant access in Settings.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        Toggle(cal.title, isOn: Binding(
                            get: { selectedCalendarIDs.contains(cal.calendarIdentifier) },
                            set: { on in
                                if on { selectedCalendarIDs.insert(cal.calendarIdentifier) }
                                else  { selectedCalendarIDs.remove(cal.calendarIdentifier) }
                                saveCalendarIDs(selectedCalendarIDs)
                            }
                        ))
                        .tint(Color(cgColor: cal.cgColor))
                    }
                }
            }

            Section("Reminders") {
                if reminderLists.isEmpty {
                    Text("No reminder lists available.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    ForEach(reminderLists, id: \.calendarIdentifier) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { selectedReminderListIDs.contains(list.calendarIdentifier) },
                            set: { on in
                                if on { selectedReminderListIDs.insert(list.calendarIdentifier) }
                                else  { selectedReminderListIDs.remove(list.calendarIdentifier) }
                                saveReminderListIDs(selectedReminderListIDs)
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

    // MARK: - Private

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

        calendars = await bridge.availableCalendars()
        reminderLists = await bridge.availableReminderLists()
        await bridge.subscribe(
            calendarIDs: selectedCalendarIDs,
            reminderListIDs: selectedReminderListIDs
        )
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        let bridge = appEnv.eventKitBridge
        await bridge.subscribe(
            calendarIDs: selectedCalendarIDs,
            reminderListIDs: selectedReminderListIDs
        )
        do {
            let report = try await bridge.sync()
            syncReport = "Imported \(report.imported), updated \(report.updated), removed \(report.removed)"
        } catch {
            syncReport = "Sync failed: \(error.localizedDescription)"
        }
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
