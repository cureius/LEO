import SwiftUI

// MARK: - Root

@MainActor
struct TodayView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: TodayViewModel? = nil
    @State private var selectedItem: (any Item)? = nil

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
            // Observe data changes for the lifetime of this view
            await vm.startObserving()
        }
    }

    @ViewBuilder
    private func mainContent(vm: TodayViewModel) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TodayHeader(date: vm.selectedDate)
                Divider().background(Theme.Color.divider)

                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Color.background)

                } else if vm.timedItems.isEmpty && vm.untimedItems.isEmpty {
                    LEOEmptyState(
                        title: "Nothing today",
                        message: "Capture anything you owe your future self.",
                        icon: "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Color.background)

                } else {
                    TodayScrollView(
                        timedItems: vm.timedItems,
                        untimedItems: vm.untimedItems,
                        onComplete: { item in Task { await vm.completeItem(item) } },
                        onTap: { item in selectedItem = item }
                    )
                }
            }

            if let msg = vm.error {
                ErrorBanner(message: msg, retry: { Task { await vm.loadItems() } })
                    .padding(Theme.Spacing.lg)
            }
        }
        .background(Theme.Color.background)
        .sheet(item: Binding(
            get: { selectedItem.map { IdentifiableItem($0) } },
            set: { selectedItem = $0?.item }
        )) { wrapper in
            ItemDetailSheet(item: wrapper.item, onSave: { _ in
                selectedItem = nil
                Task { await vm.loadItems() }
            })
        }
    }
}

// MARK: - Header

private struct TodayHeader: View {
    let date: Date
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isToday ? Theme.Color.accent : Theme.Color.textPrimary)
                Text(date, format: .dateTime.month(.wide).day())
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            if isToday {
                LEOChip(label: "Today", icon: "sun.max.fill", color: Theme.Color.accent)
            }
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
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    // Ticks every minute so the NOW marker re-evaluates its position automatically
    @State private var now: Date = .now
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // Sorted timed items + "now" marker injected between past & future
    private var scheduleEntries: [ScheduleEntry] {
        let sorted = timedItems.sorted {
            ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture)
        }
        var entries = sorted.map { ScheduleEntry.item($0) }
        // Use `now` (state) so SwiftUI re-evaluates this when the timer fires
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
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo("now-marker", anchor: .center) }
                }
            }
            .onReceive(minuteTimer) { fired in
                now = fired   // triggers scheduleEntries to recompute
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

                    if !item.tags.isEmpty {
                        tagsLabel
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

    private var tagsLabel: some View {
        Text(item.tags.map(\.name).joined(separator: " · "))
            .font(.system(size: 12))
            .foregroundStyle(Theme.Color.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        if !item.isCompleted {
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
        if !item.isCompleted {
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

private struct IdentifiableItem: Identifiable {
    let item: any Item
    var id: UUID { item.id }
    init(_ item: any Item) { self.item = item }
}

#Preview("Today — seeded") {
    TodayView()
        .environment(AppEnvironment(useInMemory: true))
}
