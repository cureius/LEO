import SwiftUI

@MainActor
struct MacTodayView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var vm: TodayViewModel? = nil
    @SceneStorage("leo.mac.today.mode") private var modeRaw: String = "timeline"

    enum Mode: String { case list, timeline }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .timeline }

    var body: some View {
        VStack(spacing: 0) {
            macToolbar
            Divider()
            if let vm {
                ScrollViewReader { proxy in
                    ScrollView {
                        if mode == .list {
                            MacTodayListContent(vm: vm, nav: nav)
                        } else {
                            DayTimelineView(
                                selectedDate: vm.selectedDate,
                                timedItems: vm.timedItems,
                                completedItems: vm.completedTodayItems,
                                onComplete: { item in Task { await vm.completeItem(item) } },
                                onUncomplete: { item in Task { await vm.completeItem(item) } },
                                onTap: { item in nav.selectedItemID = item.id },
                                onRefresh: { await vm.loadItems() }
                            )
                            .padding(.horizontal, 12)
                        }
                    }
                    .onAppear {
                        if mode == .timeline {
                            let hour = Calendar.current.component(.hour, from: .now)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation { proxy.scrollTo("hour-\(hour)", anchor: .center) }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard vm == nil else { return }
            let newVM = TodayViewModel(itemRepository: appEnv.itemRepository)
            vm = newVM
            await newVM.loadItems()
            await newVM.startObserving()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await vm?.loadItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("leoSwitchTodayMode"))) { note in
            if let raw = note.object as? String { modeRaw = raw }
        }
    }

    private var macToolbar: some View {
        HStack(spacing: 12) {
            // Date navigation
            Button { vm?.weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(vm?.selectedDate ?? .now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.headline)
            Button { vm?.weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
            Button("Today") { vm?.weekOffset = 0 }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.accent)
                .opacity((vm?.weekOffset ?? 0) == 0 ? 0 : 1)

            Spacer()

            // Mode toggle
            Picker("", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                Image(systemName: "list.bullet").tag(Mode.list)
                Image(systemName: "calendar.day.timeline.leading").tag(Mode.timeline)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            // History
            NavigationLink {
                HistoryView()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - List mode content

private struct MacTodayListContent: View {
    let vm: TodayViewModel
    let nav: MacNavigationModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if vm.untimedItems.isEmpty && vm.timedItems.isEmpty {
                LEOEmptyState(
                    title: "A clear day",
                    message: "Add something with ⌘N",
                    icon: "sun.horizon"
                )
                .padding(.top, 60)
            }

            if !vm.timedItems.isEmpty {
                sectionHeader("Scheduled")
                ForEach(vm.timedItems, id: \.id) { item in
                    MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                        .onTapGesture { nav.selectedItemID = item.id }
                        .contextMenu { itemContextMenu(item) }
                }
            }

            if !vm.untimedItems.isEmpty {
                sectionHeader("Unscheduled")
                ForEach(vm.untimedItems, id: \.id) { item in
                    MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                        .onTapGesture { nav.selectedItemID = item.id }
                        .contextMenu { itemContextMenu(item) }
                }
            }

            if !vm.completedTodayItems.isEmpty {
                sectionHeader("Completed")
                ForEach(vm.completedTodayItems, id: \.id) { item in
                    MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                        .onTapGesture { nav.selectedItemID = item.id }
                        .opacity(0.55)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func itemContextMenu(_ item: any Item) -> some View {
        Button("Complete", systemImage: "checkmark") {
            Task { await vm.completeItem(item) }
        }
        Button("Edit") { nav.selectedItemID = item.id }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            Task {
                await vm.deleteItem(item)
            }
        }
    }
}
