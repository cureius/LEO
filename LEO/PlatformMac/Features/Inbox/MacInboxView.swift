import SwiftUI

@MainActor
struct MacInboxView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var items: [any Item] = []
    @State private var isLoading = false
    @State private var sort: Sort = .priority

    enum Sort: String, CaseIterable {
        case priority = "Priority"
        case newest   = "Newest"
        case name     = "A–Z"
    }

    private var sorted: [any Item] {
        switch sort {
        case .priority: return items.sorted { $0.importance.rawValue > $1.importance.rawValue }
        case .newest:   return items.sorted { $0.createdAt > $1.createdAt }
        case .name:     return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sorted.isEmpty {
                LEOEmptyState(
                    title: "Inbox is empty",
                    message: "Capture something with ⌘N and leave it unscheduled.",
                    icon: "tray"
                )
            } else {
                itemList
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .leoTopBarTrailing) {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await load() }
        }
    }

    private var itemList: some View {
        List(sorted, id: \.id, selection: Binding(
            get: { nav.selectedItemID },
            set: { nav.selectedItemID = $0 }
        )) { item in
            MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .contextMenu {
                    Button("Schedule for Today") {
                        Task { await schedule(item, to: Calendar.current.startOfDay(for: .now)) }
                    }
                    Button("Schedule for Tomorrow") {
                        let tom = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
                        Task { await schedule(item, to: Calendar.current.startOfDay(for: tom)) }
                    }
                    Divider()
                    Button("Complete") { Task { await complete(item) } }
                    Button("Delete", role: .destructive) { Task { await delete(item) } }
                }
        }
    }

    private func load() async {
        isLoading = true
        let all = (try? await appEnv.itemRepository.fetch(predicate: .untimed)) ?? []
        items = all.filter { !$0.isCompleted }
        isLoading = false
    }

    private func schedule(_ item: any Item, to date: Date) async {
        var updated = item
        updated.anchor = .dueAt(date)
        try? await appEnv.itemRepository.update(updated)
    }

    private func complete(_ item: any Item) async {
        var updated = item
        updated.completion = .completed(at: .now)
        try? await appEnv.itemRepository.update(updated)
    }

    private func delete(_ item: any Item) async {
        try? await appEnv.itemRepository.delete(id: item.id)
        if nav.selectedItemID == item.id { nav.selectedItemID = nil }
    }
}
