import SwiftUI

@MainActor
struct InboxView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var items: [any Item] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedItemID: UUID? = nil

    private var selectedItem: (any Item)? {
        items.first { $0.id == selectedItemID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    LEOEmptyState(
                        title: "Inbox is clear",
                        message: "Items without a date live here until you schedule them.",
                        icon: "tray"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items, id: \.id) { item in
                            ItemRow(item: item,
                                    onComplete: { i in Task { await complete(i) } },
                                    onTap: { selectedItemID = $0.id },
                                    onDelete: { i in Task { await delete(i) } })
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
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.Color.background)
                }
            }
            .navigationTitle("Inbox")
            .background(Theme.Color.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Color.accent)
                            .clipShape(Capsule())
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMsg = error {
                    ErrorBanner(message: errorMsg, retry: { Task { await loadItems() } })
                        .padding(Theme.Spacing.lg)
                }
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
            .refreshable { await loadItems() }
        }
        .task { await loadItems() }
    }

    private func loadItems() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            items = try await appEnv.itemRepository.fetch(predicate: .untimed)
                .filter { !$0.isCompleted }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            self.error = error.localizedDescription
        }
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
        let itemID = item.id
        Task {
            guard var updated = items.first(where: { $0.id == itemID }) else { return }
            let now = Date.now
            updated.anchor = .dueAt(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now)
            updated.updatedAt = .now
            try? await appEnv.itemRepository.update(updated)
            await loadItems()
        }
    }
}

#Preview {
    InboxView()
        .environment(AppEnvironment(useInMemory: true))
}
