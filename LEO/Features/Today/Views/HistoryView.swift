import SwiftUI

/// Shows all completed items grouped by day, in reverse chronological order.
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @State private var grouped: [(day: Date, items: [any Item])] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if grouped.isEmpty {
                    LEOEmptyState(
                        title: "No completed items",
                        message: "Items you complete will appear here, grouped by day.",
                        icon: "checkmark.circle"
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.day) { section in
                            Section(header: DayHeader(date: section.day, count: section.items.count)) {
                                ForEach(section.items, id: \.id) { item in
                                    HistoryRow(item: item)
                                        #if os(iOS)
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                Task { await reopen(item) }
                                            } label: {
                                                Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                                            }
                                            .tint(Theme.Color.accent)
                                        }
                                        #endif
                                        .contextMenu {
                                            Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") {
                                                Task { await reopen(item) }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh history")
                    .disabled(isLoading)
                }
                #endif
            }
        }
        .task { await load() }
    }

    // MARK: - Actions

    private func reopen(_ item: any Item) async {
        var updated = item
        updated.completion = .open
        updated.updatedAt = .now
        try? await appEnv.itemRepository.update(updated)
        await load()
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let window = DateInterval(
            start: .now.addingTimeInterval(-90 * 86400),
            end:   .now
        )
        let all = (try? await appEnv.itemRepository.fetch(predicate: .inDateInterval(window))) ?? []
        let completed = all.filter(\.isCompleted)

        let cal = Calendar.current
        var byDay = [Date: [any Item]]()
        for item in completed {
            let day: Date
            if let d = item.anchor.sortDate {
                day = cal.startOfDay(for: d)
            } else if let completedAt = item.completion.completedAt {
                day = cal.startOfDay(for: completedAt)
            } else {
                day = cal.startOfDay(for: item.updatedAt)
            }
            byDay[day, default: []].append(item)
        }

        grouped = byDay
            .map { day, items in
                let sorted = items.sorted {
                    ($0.anchor.sortDate ?? .distantPast) < ($1.anchor.sortDate ?? .distantPast)
                }
                return (day: day, items: sorted)
            }
            .sorted { $0.day > $1.day }
    }
}

// MARK: - Day section header

private struct DayHeader: View {
    let date: Date
    let count: Int

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Text("\(count) done")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

// MARK: - History row

private struct HistoryRow: View {
    let item: any Item

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(typeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .strikethrough(true, color: Theme.Color.textSecondary.opacity(0.5))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(typeName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(typeColor.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.08))
                        .clipShape(Capsule())

                    if let timeStr = timeString {
                        Text(timeStr)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }

                    if let completedAt = item.completion.completedAt {
                        Text("· completed \(completedAt.formatted(.dateTime.hour().minute()))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(0.85)
    }

    private var typeName: String {
        switch item {
        case is EventItem:         return "Event"
        case is ReminderItem:      return "Reminder"
        case is AlarmItem:         return "Alarm"
        case is HabitInstanceItem: return "Habit"
        default:                   return "Task"
        }
    }

    private var typeColor: Color {
        switch item {
        case is EventItem:         return Theme.Color.accent
        case is ReminderItem:      return Theme.Color.success
        case is AlarmItem:         return Theme.Color.danger
        case is HabitInstanceItem: return Theme.Color.warning
        default:                   return Theme.Color.textSecondary
        }
    }

    private var timeString: String? {
        switch item.anchor {
        case .timeBlock(let s, let e):
            if item.anchor.isAllDayBlock { return "All day" }
            return "\(s.formatted(.dateTime.hour().minute()))–\(e.formatted(.dateTime.hour().minute()))"
        case .point(let d):
            return d.formatted(.dateTime.hour().minute())
        case .dueAt(let d):
            return d.formatted(.dateTime.hour().minute())
        default:
            return nil
        }
    }
}
