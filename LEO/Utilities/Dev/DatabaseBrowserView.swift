import SwiftUI
import SwiftData

// MARK: - Root browser

#if DEBUG
struct DatabaseBrowserView: View {
    @Environment(AppEnvironment.self) private var appEnv

    @State private var selectedTab: EntityTab = .items
    @State private var allItems: [any Item] = []
    @State private var habits: [Habit] = []
    @State private var habitInstances: [HabitInstanceItem] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var lastRefresh: Date = .now

    // Selection state
    @State private var isEditing = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showDeleteConfirm = false

    enum EntityTab: String, CaseIterable {
        case items = "Items", habits = "Habits", instances = "Instances", stats = "Stats"
        var icon: String {
            switch self {
            case .items:     return "list.bullet"
            case .habits:    return "repeat.circle"
            case .instances: return "calendar.badge.clock"
            case .stats:     return "chart.bar"
            }
        }
        var supportsSelection: Bool { self != .stats }
    }

    // MARK: - Filtered data

    private var filteredItems: [any Item] {
        searchText.isEmpty ? allItems : allItems.filter { $0.title.lowercased().contains(searchText.lowercased()) }
    }
    private var filteredHabits: [Habit] {
        searchText.isEmpty ? habits : habits.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }
    private var filteredInstances: [HabitInstanceItem] {
        searchText.isEmpty ? habitInstances : habitInstances.filter { $0.title.lowercased().contains(searchText.lowercased()) }
    }

    private var currentTabAllIDs: Set<UUID> {
        switch selectedTab {
        case .items:     return Set(filteredItems.map(\.id))
        case .habits:    return Set(filteredHabits.map(\.id))
        case .instances: return Set(filteredInstances.map(\.id))
        case .stats:     return []
        }
    }

    private var allSelected: Bool { !currentTabAllIDs.isEmpty && currentTabAllIDs == selectedIDs }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("", selection: $selectedTab) {
                ForEach(EntityTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Selection bar — shown only in edit mode
            if isEditing {
                selectionBar
                Divider()
            }

            // Search — hidden during edit mode to save space
            if selectedTab != .stats && !isEditing {
                searchBar
            }

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else {
                switch selectedTab {
                case .items:
                    ItemsTab(items: filteredItems, isEditing: isEditing, selectedIDs: $selectedIDs)
                        .refreshable { await load() }
                case .habits:
                    HabitsTab(habits: filteredHabits, isEditing: isEditing, selectedIDs: $selectedIDs)
                        .refreshable { await load() }
                case .instances:
                    InstancesTab(instances: filteredInstances, habits: habits, isEditing: isEditing, selectedIDs: $selectedIDs)
                        .refreshable { await load() }
                case .stats:
                    StatsTab(items: allItems, habits: habits, instances: habitInstances)
                        .refreshable { await load() }
                }
            }

            // Timestamp footer — always visible at the bottom
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text("Updated \(lastRefresh.formatted(.dateTime.hour().minute().second()))")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
        }
        .navigationTitle("Database Browser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await load() }
        .onChange(of: selectedTab) {
            selectedIDs = []
            searchText = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await load() }
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) record\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        HStack(spacing: 0) {
            // Select All / Deselect All
            Button {
                withAnimation { selectedIDs = allSelected ? [] : currentTabAllIDs }
            } label: {
                Text(allSelected ? "Deselect All" : "Select All")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
            }

            Spacer()

            // Count badge
            Group {
                if selectedIDs.isEmpty {
                    Text("Tap rows to select")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedIDs.count) selected")
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 13))

            Spacer()

            // Delete
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selectedIDs.isEmpty ? Color.secondary.opacity(0.4) : .red)
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search…", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Select / Done — trailing, only on selectable tabs
        if selectedTab.supportsSelection {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Select") {
                    withAnimation {
                        isEditing.toggle()
                        if !isEditing { selectedIDs = [] }
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let window = DateInterval(
            start: .now.addingTimeInterval(-365 * 86400),
            end:   .now.addingTimeInterval( 365 * 86400)
        )
        async let itemsFetch     = (try? await appEnv.itemRepository.fetch(predicate: .all)) ?? []
        async let instancesFetch = (try? await appEnv.habitRepository.fetchInstances(in: window)) ?? []
        async let habitsFetch    = (try? await appEnv.habitRepository.fetchAll()) ?? []
        allItems        = await itemsFetch.filter { !($0 is HabitInstanceItem) }
                                         .sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }
        habitInstances  = await instancesFetch.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }
        habits          = await habitsFetch
        lastRefresh     = .now
    }

    // MARK: - Delete

    private func deleteSelected() async {
        let ids = selectedIDs
        let ctx = appEnv.persistenceController.mainContext

        switch selectedTab {
        case .items:
            // Bulk delete across all stored item types
            deleteBulk(ids: ids, from: ctx, type: StoredTask.self)
            deleteBulk(ids: ids, from: ctx, type: StoredEvent.self)
            deleteBulk(ids: ids, from: ctx, type: StoredReminder.self)
            deleteBulk(ids: ids, from: ctx, type: StoredAlarm.self)

        case .instances:
            deleteBulk(ids: ids, from: ctx, type: StoredHabitInstance.self)

        case .habits:
            deleteBulk(ids: ids, from: ctx, type: StoredHabit.self)
            // Also remove orphaned instances for deleted habits
            let habitIDs = Set(habits.filter { ids.contains($0.id) }.map(\.id))
            if let allInst = try? ctx.fetch(FetchDescriptor<StoredHabitInstance>()) {
                allInst.filter { habitIDs.contains($0.habitID) }.forEach { ctx.delete($0) }
            }

        case .stats:
            return
        }

        try? ctx.save()
        selectedIDs = []
        NotificationCenter.default.post(name: .leoDataDidChange, object: nil)
        await load()
    }

    private func deleteBulk<T: PersistentModel>(ids: Set<UUID>, from ctx: ModelContext, type: T.Type) {
        guard let records = try? ctx.fetch(FetchDescriptor<T>()) else { return }
        // All stored models have an `id: UUID` property
        for record in records {
            if let identifiable = record as? (any DBIdentifiable), ids.contains(identifiable.storedID) {
                ctx.delete(record)
            }
        }
    }
}

// Protocol to unify id access across Stored* models
private protocol DBIdentifiable { var storedID: UUID { get } }
extension StoredTask:           DBIdentifiable { var storedID: UUID { id } }
extension StoredEvent:          DBIdentifiable { var storedID: UUID { id } }
extension StoredReminder:       DBIdentifiable { var storedID: UUID { id } }
extension StoredAlarm:          DBIdentifiable { var storedID: UUID { id } }
extension StoredHabitInstance:  DBIdentifiable { var storedID: UUID { id } }
extension StoredHabit:          DBIdentifiable { var storedID: UUID { id } }

// MARK: - Items tab

private struct ItemsTab: View {
    let items: [any Item]
    let isEditing: Bool
    @Binding var selectedIDs: Set<UUID>

    private var grouped: [(String, [any Item])] {
        [
            ("Tasks",           items.filter { $0 is TaskItem }),
            ("Events",          items.filter { $0 is EventItem }),
            ("Reminders",       items.filter { $0 is ReminderItem }),
            ("Alarms",          items.filter { $0 is AlarmItem }),
        ].filter { !$1.isEmpty }
    }

    var body: some View {
        if items.isEmpty {
            emptyState("No items")
        } else {
            List {
                ForEach(grouped, id: \.0) { typeName, typeItems in
                    Section("\(typeName) (\(typeItems.count))") {
                        ForEach(typeItems, id: \.id) { item in
                            SelectableRow(
                                id: item.id,
                                isEditing: isEditing,
                                selectedIDs: $selectedIDs,
                                detail: { ItemDetailBrowser(item: item) }
                            ) {
                                ItemBrowserRow(item: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: isEditing)
        }
    }
}

// MARK: - Habits tab

private struct HabitsTab: View {
    let habits: [Habit]
    let isEditing: Bool
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        if habits.isEmpty {
            emptyState("No habits")
        } else {
            List {
                Section("Habits (\(habits.count))") {
                    ForEach(habits) { habit in
                        SelectableRow(
                            id: habit.id,
                            isEditing: isEditing,
                            selectedIDs: $selectedIDs,
                            detail: { HabitDetailBrowser(habit: habit) }
                        ) {
                            HabitBrowserRow(habit: habit)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: isEditing)
        }
    }
}

// MARK: - Instances tab

private struct InstancesTab: View {
    let instances: [HabitInstanceItem]
    let habits: [Habit]
    let isEditing: Bool
    @Binding var selectedIDs: Set<UUID>

    private func habitName(for id: UUID) -> String {
        habits.first(where: { $0.id == id })?.name ?? String(id.uuidString.prefix(8))
    }

    var body: some View {
        if instances.isEmpty {
            emptyState("No habit instances")
        } else {
            List {
                Section("Instances (\(instances.count))") {
                    ForEach(instances, id: \.id) { inst in
                        SelectableRow(
                            id: inst.id,
                            isEditing: isEditing,
                            selectedIDs: $selectedIDs,
                            detail: { ItemDetailBrowser(item: inst) }
                        ) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(inst.title)
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                    CompletionDot(isCompleted: inst.isCompleted)
                                }
                                Text(habitName(for: inst.habitID))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if let d = inst.anchor.sortDate {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: isEditing)
        }
    }
}

// MARK: - Selectable row wrapper

/// Wraps any row content: in edit mode shows a leading checkbox + toggles selection on tap;
/// in view mode wraps it in a NavigationLink to the detail view.
private struct SelectableRow<Content: View, Detail: View>: View {
    let id: UUID
    let isEditing: Bool
    @Binding var selectedIDs: Set<UUID>
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let content: () -> Content

    private var isSelected: Bool { selectedIDs.contains(id) }

    var body: some View {
        if isEditing {
            Button {
                if isSelected { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                    content()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.06) : Color(.systemBackground))
        } else {
            NavigationLink { detail() } label: { content() }
        }
    }
}

// MARK: - Stats tab

private struct StatsTab: View {
    let items: [any Item]
    let habits: [Habit]
    let instances: [HabitInstanceItem]

    private var tasks:     [any Item] { items.filter { $0 is TaskItem } }
    private var events:    [any Item] { items.filter { $0 is EventItem } }
    private var reminders: [any Item] { items.filter { $0 is ReminderItem } }
    private var alarms:    [any Item] { items.filter { $0 is AlarmItem } }
    private func done(_ s: [any Item]) -> Int { s.filter(\.isCompleted).count }
    private func open(_ s: [any Item]) -> Int { s.filter { !$0.isCompleted }.count }

    var body: some View {
        List {
            Section("Record counts") {
                StatRow("Tasks",           "\(tasks.count)",     "\(open(tasks)) open · \(done(tasks)) done")
                StatRow("Events",          "\(events.count)",    "\(open(events)) open · \(done(events)) done")
                StatRow("Reminders",       "\(reminders.count)", "\(open(reminders)) open · \(done(reminders)) done")
                StatRow("Alarms",          "\(alarms.count)",    "\(open(alarms)) open · \(done(alarms)) done")
                StatRow("Habits",          "\(habits.count)",    "\(habits.filter { !$0.isArchived }.count) active")
                StatRow("Habit instances", "\(instances.count)", "\(instances.filter(\.isCompleted).count) completed")
            }
            Section("Today") {
                let todayItems = items.filter { guard let d = $0.anchor.sortDate else { return false }; return Calendar.current.isDateInToday(d) }
                StatRow("Total today",  "\(todayItems.count)",                                 "")
                StatRow("Open today",   "\(todayItems.filter { !$0.isCompleted }.count)",      "")
                StatRow("Done today",   "\(todayItems.filter(\.isCompleted).count)",           "")
            }
            Section("Date range") {
                let dates = items.compactMap(\.anchor.sortDate).sorted()
                if let first = dates.first, let last = dates.last {
                    StatRow("Earliest", first.formatted(.dateTime.month().day().year()), "")
                    StatRow("Latest",   last.formatted(.dateTime.month().day().year()),  "")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Detail: Item

private struct ItemDetailBrowser: View {
    let item: any Item
    var body: some View {
        List {
            Section("Identity") {
                FieldRow("ID",    item.id.uuidString)
                FieldRow("Type",  typeName)
                FieldRow("Title", item.title)
                if let n = item.notes { FieldRow("Notes", n) }
            }
            Section("Time") {
                FieldRow("Anchor",  anchorText)
                FieldRow("Created", item.createdAt.formatted(.dateTime))
                FieldRow("Updated", item.updatedAt.formatted(.dateTime))
            }
            Section("State") {
                FieldRow("Importance", item.importance.displayName)
                FieldRow("Completion", completionText)
                FieldRow("Completed",  item.isCompleted ? "Yes" : "No")
                FieldRow("Overdue",    item.isOverdue   ? "Yes" : "No")
            }
            if !item.tags.isEmpty {
                Section("Tags") {
                    ForEach(item.tags) { t in FieldRow(t.name, t.color.displayName) }
                }
            }
            if let ev = item as? EventItem {
                Section("Event") {
                    if let l = ev.location { FieldRow("Location", l) }
                    if !ev.attendees.isEmpty { FieldRow("Attendees", ev.attendees.joined(separator: ", ")) }
                }
            }
            if let inst = item as? HabitInstanceItem {
                Section("Habit Instance") {
                    FieldRow("Habit ID", inst.habitID.uuidString)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var typeName: String {
        switch item {
        case is TaskItem:          return "TaskItem"
        case is EventItem:         return "EventItem"
        case is ReminderItem:      return "ReminderItem"
        case is AlarmItem:         return "AlarmItem"
        case is HabitInstanceItem: return "HabitInstanceItem"
        default:                   return "Unknown"
        }
    }
    private var anchorText: String {
        switch item.anchor {
        case .untimed:               return "Untimed"
        case .dueAt(let d):          return "Due: \(d.formatted(.dateTime))"
        case .timeBlock(let s, let e): return "\(s.formatted(.dateTime)) → \(e.formatted(.dateTime))"
        case .point(let d):          return "Point: \(d.formatted(.dateTime))"
        case .location:              return "Location trigger"
        }
    }
    private var completionText: String {
        switch item.completion {
        case .open:                   return "Open"
        case .completed(let at):      return "Completed \(at.formatted(.dateTime))"
        case .skipped(let at, let r): return "Skipped \(at.formatted(.dateTime))\(r.map { " (\($0))" } ?? "")"
        case .dismissed:              return "Dismissed"
        }
    }
}

// MARK: - Detail: Habit

private struct HabitDetailBrowser: View {
    let habit: Habit
    var body: some View {
        List {
            Section("Identity") {
                FieldRow("ID",       habit.id.uuidString)
                FieldRow("Name",     habit.name)
                FieldRow("Archived", habit.isArchived ? "Yes" : "No")
                FieldRow("Created",  habit.createdAt.formatted(.dateTime))
            }
            Section("Schedule") {
                FieldRow("Frequency",   "\(habit.frequency)")
                FieldRow("Time hint",   habit.timeHint.map { "\($0)" } ?? "None")
                FieldRow("RRule",       habit.recurrenceRule.raw)
                FieldRow("Forgiveness", "\(habit.forgiveness)")
            }
            if let dur = habit.targetDuration {
                Section("Target") {
                    FieldRow("Duration", "\(Int(Double(dur.components.seconds) / 60)) min")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reusable row components

private struct ItemBrowserRow: View {
    let item: any Item
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(typeColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    if item.isOverdue {
                        Text("OVERDUE")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red.opacity(0.1)).clipShape(Capsule())
                    }
                }
                Text(subtitleText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            CompletionDot(isCompleted: item.isCompleted)
        }
        .padding(.vertical, 2)
    }

    private var subtitleText: String {
        var p = [String(item.id.uuidString.prefix(8)) + "…"]
        switch item.anchor {
        case .untimed:                  p.append("untimed")
        case .dueAt(let d):             p.append(d.formatted(.dateTime.month().day().hour().minute()))
        case .timeBlock(let s, let e):  p.append("\(s.formatted(.dateTime.hour().minute()))–\(e.formatted(.dateTime.hour().minute()))")
        case .point(let d):             p.append(d.formatted(.dateTime.month().day().hour().minute()))
        case .location:                 p.append("location")
        }
        return p.joined(separator: " · ")
    }
    private var typeIcon: String {
        switch item {
        case is EventItem:    return "calendar"
        case is ReminderItem: return "bell"
        case is AlarmItem:    return "alarm"
        default:              return "checklist"
        }
    }
    private var typeColor: Color {
        switch item {
        case is EventItem:    return .blue
        case is ReminderItem: return .green
        case is AlarmItem:    return .red
        default:              return .secondary
        }
    }
}

private struct HabitBrowserRow: View {
    let habit: Habit
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(habit.name).font(.system(size: 14, weight: .medium))
                if habit.isArchived {
                    Text("ARCHIVED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).clipShape(Capsule())
                }
            }
            Text("\(String(habit.id.uuidString.prefix(8)))… · \(habit.recurrenceRule.raw)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct CompletionDot: View {
    let isCompleted: Bool
    var body: some View {
        Circle().fill(isCompleted ? Color.green : Color.secondary.opacity(0.25)).frame(width: 8, height: 8)
    }
}

private struct FieldRow: View {
    let label: String; let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct StatRow: View {
    let label: String; let value: String; let detail: String
    init(_ label: String, _ value: String, _ detail: String) { self.label = label; self.value = value; self.detail = detail }
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.system(size: 14, weight: .semibold, design: .rounded))
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }
}

private func emptyState(_ message: String) -> some View {
    VStack(spacing: 12) {
        Spacer()
        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.secondary)
        Text(message).foregroundStyle(.secondary)
        Spacer()
    }
    .frame(maxWidth: .infinity)
}
#endif
