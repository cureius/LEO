import SwiftUI

@MainActor
struct MacHabitsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var instances: [HabitInstanceItem] = []
    @State private var showAll = false
    @State private var showAddHabit = false

    var body: some View {
        Group {
            if instances.isEmpty {
                VStack(spacing: 16) {
                    LEOEmptyState(
                        title: "No habits yet",
                        message: "Track recurring activities to build streaks.",
                        icon: "repeat.circle"
                    )
                    Button("Create Habit") { showAddHabit = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                habitsContent
            }
        }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .leoTopBarTrailing) {
                Button { showAddHabit = true } label: {
                    Image(systemName: "plus")
                }
                .help("Create habit")
            }
            ToolbarItem(placement: .leoTopBarTrailing) {
                Picker("", selection: $showAll) {
                    Text("Today").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .help("Filter habits")
            }
        }
        .task { await load() }
        .onChange(of: showAll) { _, _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await load() }
        }
        .sheet(isPresented: $showAddHabit) {
            HabitEditView(habit: nil) { newHabit in
                Task {
                    try? await appEnv.habitRepository.add(newHabit)
                    await load()
                }
            }
        }
    }

    private var habitsContent: some View {
        List(instances, id: \.id) { instance in
            HabitRow(instance: instance, isSelected: nav.selectedItemID == instance.id) {
                Task { await toggle(instance) }
            }
            .onTapGesture { nav.selectedItemID = instance.id }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .contextMenu {
                Button("Edit") { nav.selectedItemID = instance.id }
                Divider()
                Button(instance.isCompleted ? "Mark Incomplete" : "Complete") {
                    Task { await toggle(instance) }
                }
                Button("Delete", role: .destructive) {
                    Task { await deleteInstance(instance) }
                }
            }
        }
    }

    private func deleteInstance(_ instance: HabitInstanceItem) async {
        try? await appEnv.itemRepository.delete(id: instance.id)
        if nav.selectedItemID == instance.id { nav.selectedItemID = nil }
        await load()
    }

    private func load() async {
        let all = (try? await appEnv.itemRepository.fetch()) ?? []
        instances = all.compactMap { $0 as? HabitInstanceItem }.filter { instance in
            if showAll { return true }
            guard let d = instance.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d)
        }
    }

    private func toggle(_ instance: HabitInstanceItem) async {
        var updated = instance
        if instance.isCompleted {
            updated.completion = .open
        } else {
            updated.completion = .completed(at: .now)
        }
        try? await appEnv.itemRepository.update(updated)
    }
}

private struct HabitRow: View {
    let instance: HabitInstanceItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(Theme.Color.accent, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if instance.isCompleted {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.title)
                    .font(.system(size: 13))
                    .strikethrough(instance.isCompleted)
                    .foregroundStyle(instance.isCompleted ? .secondary : .primary)
                if let d = instance.anchor.sortDate {
                    Text(d, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.Color.accent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}
