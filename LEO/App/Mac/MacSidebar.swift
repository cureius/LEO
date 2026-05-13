import SwiftUI

struct MacSidebar: View {
    @Environment(MacNavigationModel.self) private var nav
    @Environment(AppEnvironment.self) private var appEnv
    @State private var todayCount: Int = 0
    @State private var inboxCount: Int = 0

    var body: some View {
        @Bindable var navBinding = nav
        List(selection: $navBinding.selection) {
            Section("Planning") {
                sidebarRow(.today, badge: todayCount > 0 ? todayCount : nil)
                sidebarRow(.inbox, badge: inboxCount > 0 ? inboxCount : nil)
                sidebarRow(.habits)
            }
            Section("Tools") {
                sidebarRow(.ask)
                sidebarRow(.fitness)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LEO")
        .frame(minWidth: 200, idealWidth: 240)
        .task { await refreshCounts() }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await refreshCounts() }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ section: SidebarSection, badge: Int? = nil) -> some View {
        Label(section.label, systemImage: section.icon)
            .tag(section)
            .badge(badge ?? 0)
    }

    private func refreshCounts() async {
        guard let items = try? await appEnv.itemRepository.fetch() else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        todayCount = items.filter { item in
            guard let d = item.anchor.sortDate else { return false }
            return d >= today && d < tomorrow && !item.isCompleted
        }.count
        inboxCount = items.filter { $0.anchor.isUntimed && !$0.isCompleted }.count
    }
}
