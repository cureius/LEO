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
            vm = nil  // Bug 4: synchronously clear to prevent flash of prior item
            Task { await loadItem(id: newID) }
        }
        .onAppear {
            Task { await loadItem(id: nav.selectedItemID) }
        }
        .onDisappear {
            // Bug 3: flush any pending auto-save immediately on disappear
            autoSaveTask?.cancel()
            autoSaveTask = nil
            Task { _ = await vm?.save() }
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
            VStack(spacing: 6) {
                shortcutHint("⌘N", label: "New item")
                shortcutHint("↑↓", label: "Navigate items")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12))
                .cornerRadius(4)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
        case is EventItem:         return Theme.Color.accent
        case is AlarmItem:         return Theme.Color.danger
        case is ReminderItem:      return Theme.Color.warning
        case is TaskItem:          return Theme.Color.success
        case is HabitInstanceItem: return Theme.Color.warning
        default:                   return .secondary
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                typeBadge().padding(.top, 12)

                if let url = MeetingLinkDetector.detect(notes: vm.notes, location: vm.location, title: vm.title) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Join \(MeetingLinkDetector.provider(for: url))", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                field("Title") {
                    TextField("Title", text: $vm.title)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onChange(of: vm.title) { _, _ in onTriggerAutoSave() }
                }

                if vm.originalItem is EventItem {
                    // Synced invite notes — show cleaned, read-only (Apple Calendar style).
                    let clean = EventNotes.cleaned(vm.notes)
                    if !clean.isEmpty {
                        field("Notes") {
                            Text(clean)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    field("Notes") {
                        TextEditor(text: $vm.notes)
                            .font(.body)
                            .frame(minHeight: 60, maxHeight: 240)
                            .scrollContentBackground(.hidden)
                            .background(Theme.Color.surface.opacity(0.5))
                            .cornerRadius(6)
                            .onChange(of: vm.notes) { _, _ in onTriggerAutoSave() }
                    }
                }

                // Event-specific details (location + attendees) — dynamic per type.
                if vm.originalItem is EventItem {
                    if !vm.location.trimmingCharacters(in: .whitespaces).isEmpty {
                        field("Location") {
                            Label(vm.location, systemImage: "mappin.and.ellipse")
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    if !vm.attendees.isEmpty {
                        field("Attendees (\(vm.attendees.count))") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(vm.attendees, id: \.self) { person in
                                    Label(person, systemImage: "person.crop.circle")
                                        .font(.callout)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                }
                            }
                        }
                    }
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
                // Bug 6: preserve duration when start changes so end never precedes start
                DatePicker("Start", selection: Binding(get: { s }, set: { newStart in
                    let duration = e.timeIntervalSince(s)
                    let newEnd = max(e, newStart.addingTimeInterval(duration))
                    vm.anchor = .timeBlock(start: newStart, end: newEnd)
                }))
                DatePicker("End", selection: Binding(get: { e }, set: { vm.anchor = .timeBlock(start: s, end: $0) }))
            case .point(let d):
                DatePicker("At", selection: Binding(get: { d }, set: { vm.anchor = .point($0) })).labelsHidden()
            case .location(let loc):
                // Bug 7: show location details and allow clearing
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Clear location") { vm.anchor = .untimed }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Color.danger)
                        .font(.caption)
                }
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

// MARK: - Tag wrapping layout (Bug 14: real line-breaking flow)

private struct WrappingHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    let spacing: CGFloat

    init(_ data: Data, spacing: CGFloat = 4, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data; self.spacing = spacing; self.content = content
    }

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(Array(data.enumerated()), id: \.element) { _, item in
                content(item)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = origin.y + lineHeight
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            _ = maxWidth  // suppress warning
            subview.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
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
