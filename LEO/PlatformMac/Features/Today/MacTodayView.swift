import SwiftUI

@MainActor
struct MacTodayView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(MacNavigationModel.self) private var nav
    @State private var vm: TodayViewModel? = nil
    @State private var showHistory = false
    @SceneStorage("leo.mac.today.mode") private var modeRaw: String = "timeline"

    enum Mode: String { case list, timeline }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .timeline }

    var body: some View {
        VStack(spacing: 0) {
            dateToolbar
            Divider()
            contentArea
        }
        .navigationTitle("Today")
        .toolbar { toolbarItems }
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
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environment(appEnv)
                .frame(minWidth: 620, minHeight: 520)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .leoTopBarTrailing) {
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History (⌘⇧H)")
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        ToolbarItem(placement: .leoTopBarTrailing) {
            Picker("", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                Image(systemName: "list.bullet").tag(Mode.list)
                Image(systemName: "calendar.day.timeline.leading").tag(Mode.timeline)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .help("Toggle list / timeline view")
        }
    }

    // MARK: - Date navigation bar

    private var dateToolbar: some View {
        HStack(spacing: 6) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Previous day")

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Next day")

            if let vm {
                // Click to jump to any date.
                DatePicker(
                    "",
                    selection: Binding(
                        get: { vm.selectedDate },
                        set: { vm.selectedDate = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(minWidth: 130)
                .padding(.leading, 4)

                if !Calendar.current.isDateInToday(vm.selectedDate) {
                    Button("Today") {
                        vm.selectedDate = Calendar.current.startOfDay(for: .now)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.Color.accent)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func shiftDay(_ delta: Int) {
        guard let vm else { return }
        let base = vm.selectedDate
        vm.selectedDate = Calendar.current.date(byAdding: .day, value: delta, to: base) ?? base
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
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
                        .padding(.horizontal, 8)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - List mode content

@MainActor
private struct MacTodayListContent: View {
    let vm: TodayViewModel
    let nav: MacNavigationModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
            if vm.timedItems.isEmpty && vm.untimedItems.isEmpty {
                let isToday = Calendar.current.isDateInToday(vm.selectedDate)
                LEOEmptyState(
                    title: isToday ? "Nothing today" : "Nothing on this day",
                    message: isToday ? "Capture anything with ⌘N." : "No items scheduled for this day.",
                    icon: "sun.horizon"
                )
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
            } else {
                if !vm.timedItems.isEmpty {
                    sectionHeader("Scheduled — \(vm.timedItems.count)")
                    ForEach(vm.timedItems, id: \.id) { item in
                        MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                            .onTapGesture { nav.selectedItemID = item.id }
                            .contextMenu { rowContextMenu(item, vm: vm) }
                    }
                }
                if !vm.untimedItems.isEmpty {
                    sectionHeader("Unscheduled — \(vm.untimedItems.count)")
                    ForEach(vm.untimedItems, id: \.id) { item in
                        MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                            .onTapGesture { nav.selectedItemID = item.id }
                            .contextMenu { rowContextMenu(item, vm: vm) }
                    }
                }
                if !vm.completedTodayItems.isEmpty {
                    sectionHeader("Completed — \(vm.completedTodayItems.count)")
                    ForEach(vm.completedTodayItems, id: \.id) { item in
                        MacItemRow(item: item, isSelected: nav.selectedItemID == item.id)
                            .onTapGesture { nav.selectedItemID = item.id }
                            .opacity(0.5)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.5)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowContextMenu(_ item: any Item, vm: TodayViewModel) -> some View {
        if !item.isCompleted {
            Button("Complete", systemImage: "checkmark") {
                Task { await vm.completeItem(item) }
            }
        } else {
            Button("Mark incomplete") {
                Task { await vm.completeItem(item) }
            }
        }
        Button("Edit") { nav.selectedItemID = item.id }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            Task { await vm.deleteItem(item) }
        }
    }
}
