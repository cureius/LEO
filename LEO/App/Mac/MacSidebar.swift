import SwiftUI

struct MacSidebar: View {
    @Environment(MacNavigationModel.self) private var nav
    @Environment(AppEnvironment.self) private var appEnv
    @State private var todayCount: Int = 0
    @State private var inboxCount: Int = 0

    var body: some View {
        List {
            Section("Planning") {
                row(.today, badge: todayCount > 0 ? todayCount : nil)
                row(.inbox, badge: inboxCount > 0 ? inboxCount : nil)
                row(.habits)
            }
            Section("Tools") {
                row(.ask)
                row(.fitness)
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

    // MARK: - Row builder

    @ViewBuilder
    private func row(_ section: SidebarSection, badge: Int? = nil) -> some View {
        let selected = nav.selection == section
        Button {
            nav.selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Theme.Color.accent : .secondary)
                    .frame(width: 18)
                Text(section.label)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? .primary : .primary)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Color.accent.opacity(0.12))
                : nil
        )
    }

    // MARK: - Counts

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
