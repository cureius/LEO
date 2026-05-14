import SwiftUI

@MainActor
struct MacHabitsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var instances: [HabitInstanceItem] = []
    @State private var showAll = false

    var body: some View {
        Group {
            if instances.isEmpty {
                LEOEmptyState(
                    title: "No habits yet",
                    message: "Habits you track will appear here.",
                    icon: "repeat.circle"
                )
            } else {
                habitsContent
            }
        }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .leoTopBarLeading) {
                Picker("", selection: $showAll) {
                    Text("Today").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await load() }
        }
    }

    private var habitsContent: some View {
        List(instances, id: \.id, selection: Binding(
            get: { nav.selectedItemID },
            set: { nav.selectedItemID = $0 }
        )) { instance in
            HabitRow(instance: instance, isSelected: nav.selectedItemID == instance.id) {
                Task { await toggle(instance) }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
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
