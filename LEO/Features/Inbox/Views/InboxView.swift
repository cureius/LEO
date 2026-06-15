import SwiftUI

@MainActor
struct InboxView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var allItems: [any Item] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedItemID: UUID? = nil
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
            VStack(spacing: 0) {
                inboxHeader

                List {
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
                .contentMargins(.top, 6, for: .scrollContent)
                .refreshable { await loadItems() }
            }
            .background(Theme.Color.background)
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .safeAreaInset(edge: .bottom) { captureBar }
            .overlay(alignment: .top) {
                if let msg = error {
                    ErrorBanner(message: msg, retry: { Task { await loadItems() } })
                        .padding(Theme.Spacing.lg)
                }
            }
            #if os(iOS)
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
            #endif
            .sheet(isPresented: $showScheduleSheet) {
                if let item = itemToSchedule {
                    ScheduleDateSheet(itemTitle: item.title) { date in
                        Task { await scheduleForDate(item, date: date) }
                    }
                }
            }
        }
        .task { await loadItems() }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await loadItems() }
        }
    }

    // MARK: - Docked capture bar (bottom, one-handed)

    private var captureBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.Color.divider)
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Color.accent)

                TextField("Capture a task…", text: $captureText)
                    .font(.system(size: 16))
                    .submitLabel(.done)
                    .onSubmit { Task { await captureTask() } }

                if !captureText.isEmpty {
                    Button { Task { await captureTask() } } label: {
                        Image(systemName: isSavingCapture ? "circle.dashed" : "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(isSavingCapture ? Theme.Color.textSecondary : Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingCapture)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.Color.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .animation(.easeInOut(duration: 0.15), value: captureText.isEmpty)
            .sensoryFeedback(.success, trigger: isSavingCapture) { old, new in old && !new }
        }
        .background(Theme.Color.background)
    }

    // MARK: - Header (title + count + inline sort)

    private var urgentCount: Int { allItems.filter { $0.importance == .urgent }.count }

    private var inboxHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inbox")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Color.textPrimary)
                if !allItems.isEmpty {
                    HStack(spacing: 5) {
                        Text("\(allItems.count) " + (allItems.count == 1 ? "task" : "tasks"))
                            .foregroundStyle(Theme.Color.textSecondary)
                        if urgentCount > 0 {
                            Text("·").foregroundStyle(Theme.Color.textSecondary.opacity(0.5))
                            Text("\(urgentCount) urgent").foregroundStyle(Theme.Color.danger)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            Spacer()
            if !allItems.isEmpty { sortMenu }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(InboxSort.allCases, id: \.self) { s in
                Button {
                    withAnimation { sort = s }
                } label: {
                    Label(s.rawValue, systemImage: sort == s ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text(sort.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.Color.accent.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.accent.opacity(0.1))
                        .frame(width: 88, height: 88)
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Theme.Color.accent)
                }
                VStack(spacing: 6) {
                    Text("Inbox Zero")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Nothing to triage. Capture a new task from the box below.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
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
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    /// Accent color for the leading stripe — only urgent/high get a visible bar.
    private var stripeColor: Color {
        switch item.importance {
        case .urgent: return Theme.Color.danger
        case .high:   return Theme.Color.warning
        default:      return .clear
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button(action: onComplete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23))
                    .foregroundStyle(
                        item.isCompleted ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.4)
                    )
                    .contentShape(Circle().scale(1.4))
            }
            .buttonStyle(.plain)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                    .strikethrough(item.isCompleted, color: Theme.Color.textSecondary)
                    .lineLimit(2)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.35))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            ZStack(alignment: .leading) {
                Theme.Color.surface
                Rectangle()
                    .fill(stripeColor)
                    .frame(width: 4)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Color.divider, lineWidth: 0.5)
        )
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
        HStack(spacing: 8) {
            Capsule()
                .fill(headerColor)
                .frame(width: 3, height: 13)
            Text(importance.displayName.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(headerColor)
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(headerColor.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(headerColor.opacity(0.14))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.leading, 2)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
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
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #endif
    }
}

#Preview {
    InboxView()
        .environment(AppEnvironment(useInMemory: true))
}
