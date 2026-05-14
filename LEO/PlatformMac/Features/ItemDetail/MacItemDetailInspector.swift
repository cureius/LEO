import SwiftUI

/// Mac inspector panel for viewing and editing any Item type.
/// Replaces the iOS ItemDetailSheet. Bound to MacNavigationModel.selectedItemID.
@MainActor
struct MacItemDetailInspector: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var vm: ItemDetailViewModel? = nil
    @State private var showDeleteConfirm = false
    @State private var autoSaveTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if let vm {
                inspectorBody(vm)
            } else if nav.selectedItemID == nil {
                emptyInspector
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onChange(of: nav.selectedItemID) { _, newID in
            Task { await loadItem(id: newID) }
        }
        .onAppear {
            Task { await loadItem(id: nav.selectedItemID) }
        }
    }

    // MARK: - Inspector content

    private func inspectorBody(_ vm: ItemDetailViewModel) -> some View {
        MacItemDetailForm(vm: vm, showDeleteConfirm: $showDeleteConfirm,
                          onTriggerAutoSave: triggerAutoSave, onDeleteItem: deleteItem,
                          typeBadge: { typeBadge(vm.originalItem) })
    }

    // MARK: - Empty state

    private var emptyInspector: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No item selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select an item to view its details")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func typeBadge(_ item: (any Item)?) -> some View {
        if let item {
            HStack(spacing: 6) {
                Image(systemName: typeIcon(item))
                    .font(.caption)
                Text(typeName(item))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(typeColor(item))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(typeColor(item).opacity(0.12))
            .cornerRadius(5)
        }
    }

    private func loadItem(id: UUID?) async {
        guard let id else { vm = nil; return }
        guard let items = try? await appEnv.itemRepository.fetch(predicate: .byID(id)),
              let item = items.first else { vm = nil; return }
        vm = ItemDetailViewModel(item: item, repository: appEnv.itemRepository)
    }

    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            _ = await vm?.save()
        }
    }

    private func deleteItem() async {
        guard let id = nav.selectedItemID else { return }
        try? await appEnv.itemRepository.delete(id: id)
        nav.selectedItemID = nil
        vm = nil
    }

    private func typeIcon(_ item: any Item) -> String {
        switch item {
        case is EventItem:    return "calendar"
        case is ReminderItem: return "bell"
        case is AlarmItem:    return "alarm"
        case is TaskItem:     return "checklist"
        case is HabitInstanceItem: return "repeat.circle"
        case is WorkoutItem:  return "figure.run"
        case is MealItem:     return "fork.knife"
        default:              return "circle"
        }
    }

    private func typeName(_ item: any Item) -> String {
        switch item {
        case is EventItem:    return "Event"
        case is ReminderItem: return "Reminder"
        case is AlarmItem:    return "Alarm"
        case is TaskItem:     return "Task"
        case is HabitInstanceItem: return "Habit"
        case is WorkoutItem:  return "Workout"
        case is MealItem:     return "Meal"
        default:              return "Item"
        }
    }

    private func typeColor(_ item: any Item) -> Color {
        switch item {
        case is EventItem:    return Theme.Color.accent
        case is AlarmItem:    return Theme.Color.danger
        case is ReminderItem: return Theme.Color.warning
        default:              return .secondary
        }
    }
}

// MARK: - Form body (uses @Bindable for @Observable vm)

private struct MacItemDetailForm<Badge: View>: View {
    @Bindable var vm: ItemDetailViewModel
    @Binding var showDeleteConfirm: Bool
    let onTriggerAutoSave: () -> Void
    let onDeleteItem: () async -> Void
    @ViewBuilder let typeBadge: () -> Badge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                typeBadge().padding(.top, 12)

                field("Title") {
                    TextField("Title", text: $vm.title)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onChange(of: vm.title) { _, _ in onTriggerAutoSave() }
                }

                field("Notes") {
                    TextEditor(text: $vm.notes)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Color.surface.opacity(0.5))
                        .cornerRadius(6)
                        .onChange(of: vm.notes) { _, _ in onTriggerAutoSave() }
                }

                field("Importance") {
                    Picker("", selection: $vm.importance) {
                        ForEach(Importance.allCases, id: \.self) { imp in
                            Text(imp.displayName).tag(imp)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: vm.importance) { _, _ in onTriggerAutoSave() }
                }

                anchorEditor

                Divider()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash").foregroundStyle(Theme.Color.danger)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await onDeleteItem() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private var anchorEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Schedule").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { anchorKey(vm.anchor) },
                set: { vm.anchor = newAnchor(for: $0) }
            )) {
                Text("Unscheduled").tag("untimed")
                Text("Due at").tag("dueAt")
                Text("Time block").tag("timeBlock")
                Text("Point in time").tag("point")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: vm.anchor) { _, _ in onTriggerAutoSave() }

            switch vm.anchor {
            case .dueAt(let d):
                DatePicker("Due", selection: Binding(get: { d }, set: { vm.anchor = .dueAt($0) })).labelsHidden()
            case .timeBlock(let s, let e):
                DatePicker("Start", selection: Binding(get: { s }, set: { vm.anchor = .timeBlock(start: $0, end: e) }))
                DatePicker("End",   selection: Binding(get: { e }, set: { vm.anchor = .timeBlock(start: s, end: $0) }))
            case .point(let d):
                DatePicker("At", selection: Binding(get: { d }, set: { vm.anchor = .point($0) })).labelsHidden()
            default: EmptyView()
            }
        }
    }

    private func anchorKey(_ a: Anchor) -> String {
        switch a {
        case .untimed:   return "untimed"
        case .dueAt:     return "dueAt"
        case .timeBlock: return "timeBlock"
        case .point:     return "point"
        case .location:  return "untimed"
        }
    }

    private func newAnchor(for key: String) -> Anchor {
        let ref = Date.now
        switch key {
        case "dueAt":     return .dueAt(ref)
        case "timeBlock": return .timeBlock(start: ref, end: ref.addingTimeInterval(3600))
        case "point":     return .point(ref)
        default:          return .untimed
        }
    }
}

// MARK: - Simple wrapping HStack for tags

private struct WrappingHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.content = content
    }
    var body: some View {
        // Simple horizontal flow — adequate for small tag sets
        HStack(spacing: 4) {
            ForEach(Array(data.enumerated()), id: \.element) { _, item in
                content(item)
            }
        }
    }
}

// MARK: - Binding onChange helper

extension Binding {
    func onChange(_ handler: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in wrappedValue = newValue; handler() }
        )
    }
}
