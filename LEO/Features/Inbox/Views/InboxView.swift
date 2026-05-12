import SwiftUI

@MainActor
struct InboxView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var allItems: [any Item] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedItemID: UUID? = nil
    @State private var showAddTask = false
    @State private var captureText = ""
    @State private var isSavingCapture = false
    @State private var sort: InboxSort = .priority
    @State private var showScheduleSheet = false
    @State private var itemToSchedule: (any Item)? = nil

    enum InboxSort: String, CaseIterable {
        case priority = "Priority"
        case newest   = "Newest"
        case name     = "Name"
    }

    private var selectedItem: (any Item)? {
        allItems.first { $0.id == selectedItemID }
    }

    private var sortedItems: [any Item] {
        switch sort {
        case .priority:
            return allItems.sorted { $0.importance.rawValue > $1.importance.rawValue }
        case .newest:
            return allItems.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return allItems.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    private var priorityGroups: [(importance: Importance, items: [any Item])] {
        [Importance.urgent, .high, .normal, .low].compactMap { imp in
            let group = sortedItems.filter { $0.importance == imp }
            return group.isEmpty ? nil : (imp, group)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                captureRow

                if allItems.isEmpty {
                    emptyStateSection
                } else if sort == .priority {
                    priorityGroupedSections
                } else {
                    flatSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Inbox")
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) {
                if let msg = error {
                    ErrorBanner(message: msg, retry: { Task { await loadItems() } })
                        .padding(Theme.Spacing.lg)
                }
            }
            .sheet(isPresented: $showAddTask) {
                ItemDetailSheet(item: nil, onSave: { _ in
                    showAddTask = false
                    Task { await loadItems() }
                })
            }
            .sheet(isPresented: Binding(
                get: { selectedItemID != nil },
                set: { if !$0 { selectedItemID = nil } }
            )) {
                if let item = selectedItem {
                    ItemDetailSheet(item: item, onSave: { _ in
                        selectedItemID = nil
                        Task { await loadItems() }
                    })
                }
            }
            .sheet(isPresented: $showScheduleSheet) {
                if let item = itemToSchedule {
                    ScheduleDateSheet(itemTitle: item.title) { date in
                        Task { await scheduleForDate(item, date: date) }
                    }
                }
            }
            .refreshable { await loadItems() }
        }
        .task { await loadItems() }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await loadItems() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !allItems.isEmpty {
                Text("\(allItems.count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.accent)
                    .clipShape(Capsule())
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(InboxSort.allCases, id: \.self) { s in
                        Button {
                            withAnimation { sort = s }
                        } label: {
                            Label(s.rawValue, systemImage: sort == s ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Button { showAddTask = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Quick capture row

    private var captureRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Color.accent)

            TextField("Capture a task…", text: $captureText)
                .font(.system(size: 15))
                .submitLabel(.done)
                .onSubmit { Task { await captureTask() } }

            if !captureText.isEmpty {
                Button { Task { await captureTask() } } label: {
                    Image(systemName: isSavingCapture ? "circle.dashed" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isSavingCapture ? Theme.Color.textSecondary : Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(isSavingCapture)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.Color.surface)
        .listRowSeparatorTint(Theme.Color.divider)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.35))
                VStack(spacing: 6) {
                    Text("Inbox is clear")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Type above to quickly capture a task, or tap + for full details.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Priority-grouped sections

    @ViewBuilder
    private var priorityGroupedSections: some View {
        ForEach(priorityGroups, id: \.importance) { group in
            Section {
                ForEach(group.items, id: \.id) { item in
                    inboxRow(item)
                }
            } header: {
                PriorityHeader(importance: group.importance, count: group.items.count)
            }
        }
    }

    // MARK: - Flat section (Newest / Name sort)

    @ViewBuilder
    private var flatSection: some View {
        Section {
            ForEach(sortedItems, id: \.id) { item in
                inboxRow(item)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func inboxRow(_ item: any Item) -> some View {
        InboxItemRow(item: item) {
            Task { await complete(item) }
        } onEdit: {
            selectedItemID = item.id
        } onDelete: {
            Task { await delete(item) }
        } onScheduleToday: {
            scheduleForToday(item)
        } onPickDate: {
            itemToSchedule = item
            showScheduleSheet = true
        } onSetPriority: { imp in
            Task { await setPriority(item, importance: imp) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { Task { await delete(item) } } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { scheduleForToday(item) } label: {
                Label("Today", systemImage: "sun.max")
            }
            .tint(Theme.Color.accent)

            Button {
                itemToSchedule = item
                showScheduleSheet = true
            } label: {
                Label("Pick date", systemImage: "calendar.badge.plus")
            }
            .tint(Theme.Color.success)
        }
        .listRowBackground(Theme.Color.background)
        .listRowSeparatorTint(Theme.Color.divider)
    }

    // MARK: - Actions

    private func loadItems() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            allItems = try await appEnv.itemRepository.fetch(predicate: .untimed)
                .filter { !$0.isCompleted }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func captureTask() async {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSavingCapture = true
        defer { isSavingCapture = false }
        let task = TaskItem(title: text, anchor: .untimed)
        try? await appEnv.itemRepository.add(task)
        captureText = ""
        await loadItems()
    }

    private func complete(_ item: any Item) async {
        var updated = item
        updated.completion = item.isCompleted ? .open : .completed(at: .now)
        updated.updatedAt = .now
        try? await appEnv.itemRepository.update(updated)
        await loadItems()
    }

    private func delete(_ item: any Item) async {
        try? await appEnv.itemRepository.delete(id: item.id)
        await loadItems()
    }

    private func scheduleForToday(_ item: any Item) {
        Task {
            let now = Date.now
            var updated = item
            updated.anchor = .dueAt(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now)
            updated.updatedAt = .now
            try? await appEnv.itemRepository.update(updated)
            await loadItems()
        }
    }

    private func scheduleForDate(_ item: any Item, date: Date) async {
        var updated = item
        updated.anchor = .dueAt(date)
        updated.updatedAt = .now
        try? await appEnv.itemRepository.update(updated)
        await loadItems()
    }

    private func setPriority(_ item: any Item, importance: Importance) async {
        var updated = item
        updated.importance = importance
        updated.updatedAt = .now
        try? await appEnv.itemRepository.update(updated)
        await loadItems()
    }
}

// MARK: - Inbox item row

private struct InboxItemRow: View {
    let item: any Item
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onScheduleToday: () -> Void
    let onPickDate: () -> Void
    let onSetPriority: (Importance) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button(action: onComplete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        item.isCompleted ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.35)
                    )
                    .contentShape(Circle().scale(1.3))
            }
            .buttonStyle(.plain)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if item.importance == .urgent {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.danger)
                    } else if item.importance == .high {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.warning)
                    }
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        .strikethrough(item.isCompleted, color: Theme.Color.textSecondary)
                        .lineLimit(2)
                }
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.3))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .contextMenu {
            if item.isCompleted {
                Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete() }
            } else {
                Button("Mark complete", systemImage: "checkmark.circle") { onComplete() }
            }

            Divider()

            Menu("Set priority") {
                ForEach(Importance.allCases.reversed(), id: \.self) { imp in
                    Button {
                        onSetPriority(imp)
                    } label: {
                        Label(imp.displayName, systemImage: item.importance == imp ? "checkmark" : imp.systemImage)
                    }
                }
            }

            Divider()

            Button("Schedule for today", systemImage: "sun.max") { onScheduleToday() }
            Button("Pick date…", systemImage: "calendar.badge.plus") { onPickDate() }

            Divider()

            Button("Edit", systemImage: "pencil") { onEdit() }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Priority section header

private struct PriorityHeader: View {
    let importance: Importance
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: importance.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(headerColor)
            Text(importance.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(headerColor)
                .tracking(0.5)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Color.surface)
                .clipShape(Capsule())
        }
    }

    private var headerColor: Color {
        switch importance {
        case .urgent: return Theme.Color.danger
        case .high:   return Theme.Color.warning
        default:      return Theme.Color.textSecondary
        }
    }
}

// MARK: - Schedule date sheet

private struct ScheduleDateSheet: View {
    let itemTitle: String
    let onSchedule: (Date) -> Void

    @State private var date: Date = {
        let tomorrow = Date.now.addingTimeInterval(86400)
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                } header: {
                    Text("Schedule \"\(itemTitle)\"")
                }
            }
            .navigationTitle("Pick date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        onSchedule(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    InboxView()
        .environment(AppEnvironment(useInMemory: true))
}
