import SwiftUI

// MARK: - Root

@MainActor
struct TodayView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: TodayViewModel? = nil
    @State private var selectedItem: (any Item)? = nil
    @State private var showHistory = false
    @State private var showTimeline = false

    var body: some View {
        Group {
            if let vm = viewModel {
                mainContent(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Color.background)
            }
        }
        .task {
            guard viewModel == nil else { return }
            let vm = TodayViewModel(itemRepository: appEnv.itemRepository)
            viewModel = vm
            await vm.loadItems()
            await vm.startObserving()
        }
    }

    @ViewBuilder
    private func mainContent(vm: TodayViewModel) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TodayHeader(
                    date: vm.selectedDate,
                    showTimeline: $showTimeline,
                    onHistoryTap: { showHistory = true }
                )
                DateStrip(vm: vm)
                Divider().background(Theme.Color.divider)

                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Color.background)

                } else if showTimeline {
                    DayTimelineView(
                        selectedDate: vm.selectedDate,
                        timedItems: vm.timedItems,
                        completedItems: vm.completedTodayItems,
                        onComplete: { item in Task { await vm.completeItem(item) } },
                        onUncomplete: { item in Task { await vm.completeItem(item) } },
                        onTap: { item in selectedItem = item },
                        onRefresh: { await vm.loadItems() }
                    )
                    .transition(.opacity)
                } else if vm.timedItems.isEmpty && vm.untimedItems.isEmpty && vm.completedTodayItems.isEmpty {
                    let isToday = Calendar.current.isDateInToday(vm.selectedDate)
                    ScrollView {
                        LEOEmptyState(
                            title: isToday ? "Nothing today" : "Nothing on this day",
                            message: isToday
                                ? "Capture anything you owe your future self."
                                : "No tasks or events were scheduled for this day.",
                            icon: "calendar.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    .refreshable { await vm.loadItems() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Color.background)

                } else {
                    TodayScrollView(
                        timedItems: vm.timedItems,
                        untimedItems: vm.untimedItems,
                        completedItems: vm.completedTodayItems,
                        onComplete: { item in Task { await vm.completeItem(item) } },
                        onUncomplete: { item in Task { await vm.completeItem(item) } },
                        onTap: { item in selectedItem = item },
                        onRefresh: { await vm.loadItems() }
                    )
                    .transition(.opacity)
                }
            }

            if let msg = vm.error {
                ErrorBanner(message: msg, retry: { Task { await vm.loadItems() } })
                    .padding(Theme.Spacing.lg)
            }
        }
        .background(Theme.Color.background)
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environment(appEnv)
        }
        #if os(iOS)
        .sheet(item: Binding(
            get: { selectedItem.map { IdentifiableItem($0) } },
            set: { selectedItem = $0?.item }
        )) { wrapper in
            ItemDetailSheet(item: wrapper.item, onSave: { _ in
                selectedItem = nil
                Task { await vm.loadItems() }
            })
        }
        #endif
    }
}

// MARK: - Date strip (week navigation + expandable month grid)

private struct DateStrip: View {
    var vm: TodayViewModel
    @State private var showMonthGrid = false
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // ── Month / nav row ────────────────────────────────────────
            HStack(spacing: 4) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { vm.weekOffset -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 28, height: 28)
                }

                // Month label — tap to expand/collapse month grid
                Button {
                    let opening = !showMonthGrid
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) { showMonthGrid.toggle() }
                    if opening { Task { await vm.loadMonthDates(for: vm.weekDays[3]) } }
                } label: {
                    HStack(spacing: 3) {
                        Text(vm.visibleMonthLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Image(systemName: showMonthGrid ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Week item total — only when there's something to show
                if vm.weekItemTotal > 0 {
                    Text("\(vm.weekItemTotal) this week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .transition(.opacity)
                }

                if !cal.isDateInToday(vm.selectedDate) || vm.weekOffset != 0 {
                    Button("Today") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.selectedDate = cal.startOfDay(for: .now)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Color.accent.opacity(0.1))
                    .clipShape(Capsule())
                }

                Button { withAnimation(.easeInOut(duration: 0.2)) { vm.weekOffset += 1 } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)

            // ── Day buttons (swipeable) ────────────────────────────────
            HStack(spacing: 0) {
                ForEach(vm.weekDays, id: \.self) { day in
                    DayButton(
                        date: day,
                        isSelected: cal.isDate(day, inSameDayAs: vm.selectedDate),
                        isToday: cal.isDateInToday(day),
                        itemCount: vm.weekItemCounts[cal.startOfDay(for: day)] ?? 0
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.selectedDate = cal.startOfDay(for: day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 40, coordinateSpace: .local)
                    .onEnded { value in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if value.translation.width < -40 { vm.weekOffset += 1 }
                            else if value.translation.width > 40 { vm.weekOffset -= 1 }
                        }
                    }
            )

            // ── Expandable month grid ──────────────────────────────────
            if showMonthGrid {
                MonthGridView(
                    vm: vm,
                    onDismiss: {
                        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { showMonthGrid = false }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.Color.background)
    }
}

private struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let itemCount: Int
    let onTap: () -> Void

    private var dayLetter: String { date.formatted(.dateTime.weekday(.narrow)) }
    private var dayNumber: String { date.formatted(.dateTime.day()) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                // Weekday letter
                Text(dayLetter)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        isSelected ? Theme.Color.accent
                            : isToday  ? Theme.Color.accent
                            : Theme.Color.textSecondary
                    )

                // Day number circle
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: 34, height: 34)
                    } else if isToday {
                        Circle()
                            .strokeBorder(Theme.Color.accent, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }
                    Text(dayNumber)
                        .font(.system(size: 15, weight: isSelected || isToday ? .bold : .regular))
                        .foregroundStyle(
                            isSelected ? .white
                                : isToday  ? Theme.Color.accent
                                : Theme.Color.textPrimary
                        )
                }

                // Density dot — shows when day has items OR is today-but-not-selected.
                // White when selected (visible on filled background), accent otherwise.
                let showDot = itemCount > 0 || (isToday && !isSelected)
                Circle()
                    .fill(showDot
                          ? (isSelected ? Color.white.opacity(0.8) : Theme.Color.accent)
                          : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            date.formatted(.dateTime.weekday(.wide).month().day())
            + (itemCount > 0 ? ", \(itemCount) items" : "")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Header

private struct TodayHeader: View {
    let date: Date
    @Binding var showTimeline: Bool
    let onHistoryTap: () -> Void
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isToday ? Theme.Color.accent : Theme.Color.textPrimary)
                Text(date, format: .dateTime.month(.wide).day())
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()

            // Icon cluster — list · timeline · history
            HStack(spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showTimeline = false } } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: showTimeline ? .regular : .semibold))
                        .foregroundStyle(showTimeline ? Theme.Color.textSecondary : Theme.Color.accent)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("List view")

                Button { withAnimation(.easeInOut(duration: 0.2)) { showTimeline = true } } label: {
                    Image(systemName: "calendar.day.timeline.leading")
                        .font(.system(size: 13, weight: showTimeline ? .semibold : .regular))
                        .foregroundStyle(showTimeline ? Theme.Color.accent : Theme.Color.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Timeline view")

                Divider().frame(height: 16)

                Button(action: onHistoryTap) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 32, height: 30)
                }
                .accessibilityLabel("View history")
            }
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (isToday ? "Today, " : "")
            + date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        )
    }
}

// MARK: - Scroll view

private struct TodayScrollView: View {
    let timedItems: [any Item]
    let untimedItems: [any Item]
    let completedItems: [any Item]
    let onComplete: (any Item) -> Void
    let onUncomplete: (any Item) -> Void
    let onTap: (any Item) -> Void
    let onRefresh: () async -> Void

    @State private var showCompleted = false

    // Ticks every minute so the NOW marker re-evaluates its position automatically
    @State private var now: Date = .now
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // All-day events (midnight-to-midnight blocks) shown in a separate strip
    private var allDayItems: [any Item] {
        timedItems.filter { $0.anchor.isAllDayBlock }
                  .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    // Regular timed events shown in the timeline
    private var scheduledItems: [any Item] {
        timedItems.filter { !$0.anchor.isAllDayBlock }
    }

    // Sorted scheduled items + "now" marker injected between past & future
    private var scheduleEntries: [ScheduleEntry] {
        let sorted = scheduledItems.sorted { a, b in
            let da = a.anchor.sortDate ?? .distantFuture
            let db = b.anchor.sortDate ?? .distantFuture
            if da != db { return da < db }
            return a.anchor.sortPriority < b.anchor.sortPriority
        }
        var entries = sorted.map { ScheduleEntry.item($0) }
        let nowIdx = sorted.firstIndex(where: {
            ($0.anchor.sortDate ?? .distantFuture) > now
        }) ?? sorted.count
        entries.insert(.nowMarker, at: nowIdx)
        return entries
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {

                    // ── Unscheduled tasks ──────────────────────────────
                    if !untimedItems.isEmpty {
                        SectionHeader(title: "Unscheduled", count: untimedItems.count)

                        ForEach(untimedItems, id: \.id) { item in
                            UnscheduledRow(
                                item: item,
                                onComplete: onComplete,
                                onTap: onTap
                            )
                            RowDivider()
                        }
                        Spacer().frame(height: Theme.Spacing.lg)
                    }

                    // ── Timed schedule ─────────────────────────────────
                    if !timedItems.isEmpty {
                        SectionHeader(title: "Schedule", count: timedItems.count)

                        // All-day strip — shown above the hourly timeline
                        if !allDayItems.isEmpty {
                            AllDayStrip(items: allDayItems, onComplete: onComplete, onTap: onTap)
                            if !scheduledItems.isEmpty {
                                RowDivider(leadingPad: 0)
                            }
                        }

                        ForEach(scheduleEntries) { entry in
                            switch entry {
                            case .item(let item):
                                ScheduleRow(item: item, onComplete: onComplete, onTap: onTap)
                                    .id(item.id)
                                RowDivider(leadingPad: 60)
                            case .nowMarker:
                                NowMarkerRow()
                                    .id("now-marker")
                            }
                        }
                    }

                    // ── Completed today ────────────────────────────────
                    if !completedItems.isEmpty {
                        CompletedSection(
                            items: completedItems,
                            isExpanded: $showCompleted,
                            onUncomplete: onUncomplete,
                            onTap: onTap
                        )
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await onRefresh() }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo("now-marker", anchor: .center) }
                }
            }
            .onReceive(minuteTimer) { fired in
                now = fired
            }
        }
    }
}

// MARK: - Schedule entry model

private enum ScheduleEntry: Identifiable {
    case item(any Item)
    case nowMarker

    var id: String {
        switch self {
        case .item(let i): return i.id.uuidString
        case .nowMarker:   return "now-marker"
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

// MARK: - Dividers

private struct RowDivider: View {
    var leadingPad: CGFloat = Theme.Spacing.lg

    var body: some View {
        Divider()
            .background(Theme.Color.divider)
            .padding(.leading, leadingPad)
    }
}

// MARK: - Now marker

private struct NowMarkerRow: View {
    var body: some View {
        HStack(spacing: 0) {
            // Aligns with the time column
            Text("NOW")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Color.danger)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Circle()
                .fill(Theme.Color.danger)
                .frame(width: 6, height: 6)

            Rectangle()
                .fill(Theme.Color.danger)
                .frame(height: 1)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Unscheduled task row

private struct UnscheduledRow: View {
    let item: any Item
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        Button { onTap(item) } label: {
            HStack(spacing: Theme.Spacing.md) {
                CompletionButton(item: item, onComplete: onComplete)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary
                        )
                        .strikethrough(item.isCompleted, color: Theme.Color.textSecondary)
                        .lineLimit(2)

                    if !item.tags.isEmpty || item.rruleRaw != nil {
                        subtitleLabel
                    }
                }

                Spacer(minLength: 0)
                ImportanceBadge(importance: item.importance, completed: item.isCompleted)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowContextMenu }
    }

    private var subtitleLabel: some View {
        var parts: [String] = []
        if let raw = item.rruleRaw, let rule = try? RRule.parse(raw) {
            parts.append("↩ \(RecurrenceFormatter.summary(for: rule))")
        }
        parts += item.tags.map(\.name)
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 12))
            .foregroundStyle(Theme.Color.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        if item.isCompleted {
            Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete(item) }
        } else {
            Button("Complete", systemImage: "checkmark.circle") { onComplete(item) }
        }
        Button("Edit", systemImage: "pencil") { onTap(item) }
    }
}

// MARK: - Schedule (timed) row

private struct ScheduleRow: View {
    let item: any Item
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    private var isNow: Bool {
        guard case .timeBlock(let s, let e) = item.anchor else { return false }
        return s <= Date.now && Date.now < e
    }

    var body: some View {
        Button { onTap(item) } label: {
            HStack(alignment: .top, spacing: 0) {
                // ── Time label (52pt) ──────────────────────────────────
                Text(startTimeText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        item.isCompleted ? Theme.Color.textSecondary.opacity(0.5) : Theme.Color.textSecondary
                    )
                    .frame(width: 52, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.top, 13)

                // ── Type indicator ─────────────────────────────────────
                typeIndicator

                // ── Content ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary
                            )
                            .strikethrough(item.isCompleted, color: Theme.Color.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ImportanceBadge(importance: item.importance, completed: item.isCompleted)
                        CompletionButton(item: item, onComplete: onComplete)
                    }

                    subtitleText
                }
                .padding(.top, 10)
                .padding(.bottom, 12)
                .padding(.trailing, Theme.Spacing.lg)
            }
            .background(isNow ? typeColor.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowContextMenu }
    }

    // Left colour bar (timeBlock) or dot (point/alarm)
    @ViewBuilder
    private var typeIndicator: some View {
        if case .timeBlock = item.anchor {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(typeColor.opacity(item.isCompleted ? 0.3 : 1))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.trailing, 8)
        } else {
            Circle()
                .fill(typeColor.opacity(item.isCompleted ? 0.3 : 1))
                .frame(width: 7, height: 7)
                .padding(.trailing, 8)
                .frame(width: 3)    // same column width as the bar
                .padding(.top, 17)
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        let parts = subtitleParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textSecondary)
                .lineLimit(1)
        }
    }

    private var subtitleParts: [String] {
        var parts: [String] = []

        // Time range or point
        switch item.anchor {
        case .timeBlock(let s, let e):
            let fmt = Date.FormatStyle().hour().minute()
            parts.append("\(s.formatted(fmt))–\(e.formatted(fmt))")
        case .point(let d):
            parts.append(d.formatted(.dateTime.hour().minute()))
        default: break
        }

        // Recurrence frequency
        if let raw = item.rruleRaw, let rule = try? RRule.parse(raw) {
            parts.append("↩ \(RecurrenceFormatter.summary(for: rule))")
        }

        // Location (first segment only — keeps it short)
        if let ev = item as? EventItem, let loc = ev.location, !loc.isEmpty {
            parts.append(loc.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? loc)
        }

        // Attendee count
        if let ev = item as? EventItem, !ev.attendees.isEmpty {
            let n = ev.attendees.count
            parts.append(n == 1 ? "1 person" : "\(n) people")
        }

        // Tags
        if !item.tags.isEmpty {
            parts.append(item.tags.map(\.name).joined(separator: ", "))
        }

        return parts
    }

    private var startTimeText: String {
        if item.anchor.isAllDayBlock { return "" }
        guard let d = item.anchor.sortDate else { return "" }
        return d.formatted(.dateTime.hour().minute())
    }

    private var typeColor: Color {
        switch item {
        case is EventItem:          return Theme.Color.accent
        case is ReminderItem:       return Theme.Color.success
        case is AlarmItem:          return Theme.Color.danger
        case is HabitInstanceItem:  return Theme.Color.warning
        default:                    return Theme.Color.textSecondary
        }
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        if item.isCompleted {
            Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete(item) }
        } else {
            Button("Complete", systemImage: "checkmark.circle") { onComplete(item) }
        }
        Button("Edit", systemImage: "pencil") { onTap(item) }
    }
}

// MARK: - Shared sub-components

private struct CompletionButton: View {
    let item: any Item
    let onComplete: (any Item) -> Void

    var body: some View {
        Button { onComplete(item) } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(
                    item.isCompleted ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.35)
                )
                .contentShape(Circle().scale(1.4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")
    }
}

private struct ImportanceBadge: View {
    let importance: Importance
    let completed: Bool

    var body: some View {
        if !completed {
            switch importance {
            case .urgent:
                Text("Urgent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.danger)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.danger.opacity(0.12))
                    .clipShape(Capsule())
            case .high:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Color.warning)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Helpers

// MARK: - Completed section (collapsible)

private struct CompletedSection: View {
    let items: [any Item]
    @Binding var isExpanded: Bool
    let onUncomplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row — tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.success)
                    Text("Completed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Color.surface)
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded rows
            if isExpanded {
                Divider().background(Theme.Color.divider)
                ForEach(items, id: \.id) { item in
                    HStack(spacing: Theme.Spacing.md) {
                        Button { onUncomplete(item) } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.Color.success)
                                .contentShape(Circle().scale(1.4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark incomplete")

                        Button { onTap(item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    if item is WorkoutItem {
                                        Image(systemName: "figure.strengthtraining.traditional")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.Color.warning.opacity(0.7))
                                    } else if item is MealItem {
                                        Image(systemName: "fork.knife")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.Color.accent.opacity(0.7))
                                    }
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Theme.Color.textSecondary)
                                        .strikethrough(true, color: Theme.Color.textSecondary)
                                        .lineLimit(1)
                                }
                                if let timeStr = completionTimeString(item) {
                                    Text(timeStr)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Color.textSecondary.opacity(0.7))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 10)
                    .opacity(0.7)
                    .contextMenu {
                        Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") {
                            onUncomplete(item)
                        }
                    }
                    if item.id != items.last?.id {
                        RowDivider()
                    }
                }
            }
        }
        .background(Theme.Color.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.lg)
    }

    private func completionTimeString(_ item: any Item) -> String? {
        switch item.anchor {
        case .timeBlock(let s, let e):
            if item.anchor.isAllDayBlock { return "All day" }
            return "\(s.formatted(.dateTime.hour().minute()))–\(e.formatted(.dateTime.hour().minute()))"
        case .point(let d):
            return d.formatted(.dateTime.hour().minute())
        case .dueAt(let d):
            return "Due \(d.formatted(.dateTime.hour().minute()))"
        default:
            if let completedAt = item.completion.completedAt {
                return "Done at \(completedAt.formatted(.dateTime.hour().minute()))"
            }
            return nil
        }
    }
}

// MARK: - All-day strip

/// Compact strip shown above the hourly schedule for all-day events.
/// Visually distinct from timed rows: no time column, accent-tinted background.
private struct AllDayStrip: View {
    let items: [any Item]
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section micro-label
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                Text("ALL DAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                    .tracking(0.8)
            }
            .padding(.leading, Theme.Spacing.lg)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(items, id: \.id) { item in
                AllDayRow(item: item, onComplete: onComplete, onTap: onTap)
                if item.id != items.last?.id {
                    Divider()
                        .background(Theme.Color.accent.opacity(0.15))
                        .padding(.leading, Theme.Spacing.lg)
                }
            }
        }
        .background(Theme.Color.accent.opacity(0.06))
        .padding(.bottom, 4)
    }
}

private struct AllDayRow: View {
    let item: any Item
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        Button { onTap(item) } label: {
            HStack(spacing: 10) {
                // Completion circle
                Button(action: { onComplete(item) }) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            item.isCompleted ? Theme.Color.success : Theme.Color.accent.opacity(0.5)
                        )
                        .contentShape(Circle().scale(1.3))
                }
                .buttonStyle(.plain)

                // Title + optional location
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary
                        )
                        .strikethrough(item.isCompleted, color: Theme.Color.textSecondary)
                        .lineLimit(1)

                    if let ev = item as? EventItem,
                       let loc = ev.location, !loc.isEmpty {
                        let shortLoc = loc.components(separatedBy: ",").first?
                            .trimmingCharacters(in: .whitespaces) ?? loc
                        Text(shortLoc)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isCompleted {
                Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete(item) }
            } else {
                Button("Complete", systemImage: "checkmark.circle") { onComplete(item) }
            }
            Button("Edit", systemImage: "pencil") { onTap(item) }
        }
    }
}

// MARK: - Month grid (expandable calendar)

private struct MonthGridView: View {
    var vm: TodayViewModel
    let onDismiss: () -> Void

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)
    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdayHeaders = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.Color.divider)

            // Month navigation row
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth)!
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 36, height: 36)
                }

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth)!
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            // Weekday header row
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { h in
                    Text(h)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, Theme.Spacing.xs)

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthDays(for: displayedMonth).enumerated()), id: \.offset) { _, day in
                    if let day {
                        MonthDayCell(
                            date: day,
                            isSelected: cal.isDate(day, inSameDayAs: vm.selectedDate),
                            isToday: cal.isDateInToday(day),
                            hasItems: vm.monthItemDates.contains(cal.startOfDay(for: day))
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.selectedDate = cal.startOfDay(for: day)
                            }
                            onDismiss()
                        }
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .background(Theme.Color.background)
        .onAppear {
            displayedMonth = monthStart(for: vm.weekDays[3])
            Task { await vm.loadMonthDates(for: displayedMonth) }
        }
        .onChange(of: displayedMonth) { _, newMonth in
            Task { await vm.loadMonthDates(for: newMonth) }
        }
    }

    private func monthStart(for date: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthDays(for month: Date) -> [Date?] {
        let first = monthStart(for: month)
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let leadingBlanks = (cal.component(.weekday, from: first) + 5) % 7  // Mon = 0
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for i in 0..<count {
            days.append(cal.date(byAdding: .day, value: i, to: first))
        }
        let trailing = (7 - days.count % 7) % 7
        if trailing > 0 { days += Array(repeating: nil, count: trailing) }
        return days
    }
}

private struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle().fill(Theme.Color.accent)
                    } else if isToday {
                        Circle().strokeBorder(Theme.Color.accent, lineWidth: 1.5)
                    }
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected ? .white
                                : isToday ? Theme.Color.accent
                                : Theme.Color.textPrimary
                        )
                }
                .frame(width: 32, height: 32)

                Circle()
                    .fill(hasItems
                          ? (isSelected ? Color.white.opacity(0.7) : Theme.Color.accent)
                          : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Helpers

private struct IdentifiableItem: Identifiable {
    let item: any Item
    var id: UUID { item.id }
    init(_ item: any Item) { self.item = item }
}

// MARK: - Day timeline view (full 24-hour grid)

struct DayTimelineView: View {
    let selectedDate: Date
    let timedItems: [any Item]
    let completedItems: [any Item]
    let onComplete: (any Item) -> Void
    let onUncomplete: (any Item) -> Void
    let onTap: (any Item) -> Void
    let onRefresh: () async -> Void

    static let hourHeight: CGFloat = 64
    static let timeColWidth: CGFloat = 52
    static let eventLeadPad: CGFloat = 10

    @State private var now: Date = .now
    @State private var showCompleted = false
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var allDayItems: [any Item] {
        timedItems.filter { $0.anchor.isAllDayBlock }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
    private var scheduledItems: [any Item] { timedItems.filter { !$0.anchor.isAllDayBlock } }

    // MARK: - Overlap layout

    private struct LayoutEvent: Identifiable {
        let id: UUID
        let item: any Item
        let startMin: CGFloat
        let endMin: CGFloat
        var column: Int
        var columnCount: Int
    }

    private func computeLayout(_ items: [any Item]) -> [LayoutEvent] {
        guard !items.isEmpty else { return [] }

        // Build raw events sorted by start time
        var events: [LayoutEvent] = items.compactMap { item -> LayoutEvent? in
            guard let sm = startMinutes(item) else { return nil }
            let em: CGFloat
            if case .timeBlock(let s, let e) = item.anchor {
                em = sm + CGFloat(e.timeIntervalSince(s) / 60)
            } else {
                em = sm + 44  // point/due items get a virtual 44-min footprint
            }
            return LayoutEvent(id: item.id, item: item, startMin: sm, endMin: em, column: 0, columnCount: 1)
        }.sorted { $0.startMin < $1.startMin }

        // Greedy column assignment
        var colEnds: [CGFloat] = []
        for i in events.indices {
            let col = colEnds.firstIndex(where: { $0 <= events[i].startMin }) ?? colEnds.count
            if col == colEnds.count { colEnds.append(0) }
            colEnds[col] = events[i].endMin
            events[i].column = col
        }

        // BFS cluster detection: events that transitively overlap share the same columnCount
        var visited = Set<Int>()
        for i in events.indices where !visited.contains(i) {
            var cluster = [i]
            var queue = [i]
            visited.insert(i)
            while !queue.isEmpty {
                let cur = queue.removeFirst()
                for j in events.indices where !visited.contains(j) {
                    if events[cur].startMin < events[j].endMin && events[j].startMin < events[cur].endMin {
                        visited.insert(j)
                        cluster.append(j)
                        queue.append(j)
                    }
                }
            }
            let maxCol = cluster.map { events[$0].column }.max()! + 1
            for idx in cluster { events[idx].columnCount = maxCol }
        }

        return events
    }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    private var nowMinutes: CGFloat {
        guard isToday else { return -1 }
        let cal = Calendar.current
        return CGFloat(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now))
    }
    private var nowY: CGFloat { nowMinutes / 60 * Self.hourHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if !allDayItems.isEmpty {
                        AllDayStrip(items: allDayItems, onComplete: onComplete, onTap: onTap)
                        Divider().background(Theme.Color.divider)
                    }

                    // VStack gives each hour row a real layout position so
                    // ScrollViewReader.scrollTo("tl-hour-N") works correctly.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            TimelineHourSlot(hour: hour)
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.hourHeight)
                                .id("tl-hour-\(hour)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        // GeometryReader inherits the VStack's size (full width ×
                        // 24 * hourHeight), giving correct coordinates for event blocks.
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                let layout = computeLayout(scheduledItems)
                                ForEach(layout) { ev in
                                    let eX = Self.timeColWidth + Self.eventLeadPad
                                    let totalW = max(0, geo.size.width - eX - Theme.Spacing.md)
                                    let colW = totalW / CGFloat(ev.columnCount)
                                    let eW = max(0, colW - 4)
                                    TimelineEventBlock(
                                        item: ev.item,
                                        color: itemColor(ev.item),
                                        onComplete: onComplete,
                                        onTap: onTap
                                    )
                                    .frame(width: eW, height: blockHeight(ev.item))
                                    .offset(x: eX + CGFloat(ev.column) * colW, y: ev.startMin / 60 * Self.hourHeight)
                                }

                                if isToday && nowMinutes >= 0 {
                                    TimelineNowLine(width: geo.size.width)
                                        .offset(y: nowY)
                                }
                            }
                        }
                    }

                    if !completedItems.isEmpty {
                        CompletedSection(
                            items: completedItems,
                            isExpanded: $showCompleted,
                            onUncomplete: onUncomplete,
                            onTap: onTap
                        )
                    }

                    Spacer().frame(height: 120)
                }
            }
            .refreshable { await onRefresh() }
            .onAppear {
                let targetHour = isToday
                    ? max(0, Calendar.current.component(.hour, from: .now) - 1)
                    : 7
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { proxy.scrollTo("tl-hour-\(targetHour)", anchor: .top) }
                }
            }
            .onReceive(minuteTimer) { fired in now = fired }
        }
    }

    private func startMinutes(_ item: any Item) -> CGFloat? {
        let cal = Calendar.current
        func mins(_ d: Date) -> CGFloat {
            CGFloat(cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d))
        }
        switch item.anchor {
        case .timeBlock(let s, _): return mins(s)
        case .point(let d):        return mins(d)
        case .dueAt(let d):        return mins(d)
        default:                   return nil
        }
    }

    private func blockHeight(_ item: any Item) -> CGFloat {
        if case .timeBlock(let s, let e) = item.anchor {
            let mins = CGFloat(e.timeIntervalSince(s) / 60)
            return max(44, mins / 60 * Self.hourHeight)
        }
        return 44
    }

    private func itemColor(_ item: any Item) -> Color {
        switch item {
        case is EventItem:         return Theme.Color.accent
        case is ReminderItem:      return Theme.Color.success
        case is AlarmItem:         return Theme.Color.danger
        case is HabitInstanceItem: return Theme.Color.warning
        default:                   return Theme.Color.textSecondary
        }
    }
}

// MARK: - Timeline hour slot

private struct TimelineHourSlot: View {
    let hour: Int

    private var label: String {
        switch hour {
        case 0:  return "12 AM"
        case 12: return "12 PM"
        case 1..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.5))
                .frame(width: DayTimelineView.timeColWidth, alignment: .trailing)
                .padding(.trailing, 8)

            Rectangle()
                .fill(Theme.Color.divider)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Timeline event block

private struct TimelineEventBlock: View {
    let item: any Item
    let color: Color
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        Button { onTap(item) } label: {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(item.isCompleted ? 0.4 : 1))
                    .frame(width: 3)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? color.opacity(0.5) : color)
                        .strikethrough(item.isCompleted, color: color.opacity(0.5))
                        .lineLimit(2)

                    if let t = timeLabel {
                        Text(t)
                            .font(.system(size: 10))
                            .foregroundStyle(color.opacity(0.7))
                    }
                }

                Spacer(minLength: 0)

                Button { onComplete(item) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(item.isCompleted ? color.opacity(0.6) : color.opacity(0.4))
                        .contentShape(Circle().scale(1.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(item.isCompleted ? 0.05 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isCompleted {
                Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete(item) }
            } else {
                Button("Complete", systemImage: "checkmark.circle") { onComplete(item) }
            }
            Button("Edit", systemImage: "pencil") { onTap(item) }
        }
    }

    private var timeLabel: String? {
        switch item.anchor {
        case .timeBlock(let s, let e):
            return "\(s.formatted(.dateTime.hour().minute()))–\(e.formatted(.dateTime.hour().minute()))"
        case .point(let d):   return d.formatted(.dateTime.hour().minute())
        case .dueAt(let d):   return "Due \(d.formatted(.dateTime.hour().minute()))"
        default:              return nil
        }
    }
}

// MARK: - Timeline NOW line

private struct TimelineNowLine: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text("NOW")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Color.danger)
                .frame(width: DayTimelineView.timeColWidth - 2, alignment: .trailing)
                .padding(.trailing, 4)

            Circle()
                .fill(Theme.Color.danger)
                .frame(width: 7, height: 7)

            Rectangle()
                .fill(Theme.Color.danger.opacity(0.6))
                .frame(height: 1.5)
        }
        .frame(width: width)
    }
}

#Preview("Today — seeded") {
    TodayView()
        .environment(AppEnvironment(useInMemory: true))
}
