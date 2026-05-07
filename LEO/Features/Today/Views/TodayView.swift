import SwiftUI

@MainActor
struct TodayView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: TodayViewModel? = nil
    @State private var showQuickAdd = false
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
                } else if vm.timedItems.isEmpty && vm.untimedItems.isEmpty {
                    LEOEmptyState(
                        title: "Nothing today",
                        message: "Capture anything you owe your future self.",
                        icon: "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TodayScrollView(
                        timedItems: vm.timedItems,
                        untimedItems: vm.untimedItems,
                        onComplete: { item in Task { await vm.completeItem(item) } },
                        onTap: { item in selectedItem = item },
                        onReschedule: { item, anchor in Task { await vm.reschedule(item: item, to: anchor) } }
                    )
                }
            }
            .background(Theme.Color.background)

            if let errorMsg = vm.error {
                ErrorBanner(message: errorMsg, retry: { Task { await vm.loadItems() } })
                    .padding(Theme.Spacing.lg)
            }
        }
        .sheet(item: Binding(
            get: { selectedItem.map { IdentifiableItem(item: $0) } },
            set: { selectedItem = $0?.item }
        )) { wrapper in
            ItemDetailSheet(item: wrapper.item, onSave: { _ in
                selectedItem = nil
                Task { await vm.loadItems() }
            })
        }
    }
}

// MARK: - Today header

private struct TodayHeader: View {
    let date: Date

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(Theme.Typography.headline)
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
        .accessibilityLabel(accessibilityDateLabel)
    }

    private var accessibilityDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return (isToday ? "Today, " : "") + formatter.string(from: date)
    }
}

// MARK: - Scrollable timeline

private struct TodayScrollView: View {
    let timedItems: [any Item]
    let untimedItems: [any Item]
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void
    let onReschedule: (any Item, Anchor) -> Void

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 60  // 60pt per hour = 1pt/min

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Untimed items lane
                    if !untimedItems.isEmpty {
                        untimedLane
                        Divider().background(Theme.Color.divider).padding(.vertical, Theme.Spacing.sm)
                    }

                    // Hour grid + items
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        timedItemsLayer
                        NowLine(startHour: startHour, hourHeight: hourHeight)
                    }
                    .frame(height: CGFloat(endHour - startHour) * hourHeight + 80)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .padding(.bottom, 100) // quick-add bar clearance
            }
            .onAppear {
                let nowHour = Calendar.current.component(.hour, from: .now)
                let scrollHour = max(startHour, nowHour - 1)
                proxy.scrollTo("hour-\(scrollHour)", anchor: .top)
            }
        }
    }

    // MARK: - Untimed lane

    private var untimedLane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No time set")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
            ForEach(untimedItems, id: \.id) { item in
                ItemRow(item: item, onComplete: onComplete, onTap: onTap)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Hour rail

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text(hourLabel(hour))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                    Rectangle()
                        .fill(Theme.Color.divider)
                        .frame(height: 0.5)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: hourHeight)
                .id("hour-\(hour)")
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let d = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return d.formatted(.dateTime.hour())
    }

    // MARK: - Timed items layer

    private var timedItemsLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(timedItems, id: \.id) { item in
                if let sortDate = item.anchor.sortDate {
                    let topOffset = yOffset(for: sortDate)
                    let itemHeight = height(for: item)
                    TimelineItemCard(
                        item: item,
                        height: itemHeight,
                        onComplete: onComplete,
                        onTap: onTap
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 52) // after the hour label
                    .offset(y: topOffset)
                }
            }
        }
    }

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = CGFloat(cal.component(.hour, from: date) - startHour)
        let minute = CGFloat(cal.component(.minute, from: date))
        return (hour * hourHeight) + (minute / 60 * hourHeight)
    }

    private func height(for item: any Item) -> CGFloat {
        if case .timeBlock(let s, let e) = item.anchor {
            let minutes = e.timeIntervalSince(s) / 60
            return max(44, CGFloat(minutes) / 60 * hourHeight)
        }
        return 44
    }
}

// MARK: - Now line (ticks every 60s)

private struct NowLine: View {
    let startHour: Int
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let offset = nowOffset()
            HStack(spacing: 0) {
                Text("▶")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Color.danger)
                    .frame(width: 52, alignment: .trailing)
                Rectangle()
                    .fill(Theme.Color.danger)
                    .frame(height: 1.5)
                    .frame(maxWidth: .infinity)
            }
            .offset(y: offset)
            .accessibilityHidden(true)
        }
    }

    private func nowOffset() -> CGFloat {
        let cal = Calendar.current
        let now = Date.now
        let hour = CGFloat(cal.component(.hour, from: now) - startHour)
        let minute = CGFloat(cal.component(.minute, from: now))
        return (hour * hourHeight) + (minute / 60 * hourHeight)
    }
}

// MARK: - Timeline item card

private struct TimelineItemCard: View {
    let item: any Item
    let height: CGFloat
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void

    var body: some View {
        Button { onTap(item) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Rectangle()
                    .fill(typeColor)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(height > 60 ? 2 : 1)
                    if let timeStr = timeString {
                        Text(timeStr)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                Spacer()
                if item.importance == .high || item.importance == .urgent {
                    Image(systemName: item.importance == .urgent ? "exclamationmark.2" : "exclamationmark")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.warning)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(height: height, alignment: .top)
        }
        .buttonStyle(.plain)
        .background(typeColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(typeColor.opacity(0.3), lineWidth: 1))
        .contextMenu {
            Button("Complete") { onComplete(item) }
            Button("Edit") { onTap(item) }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open details")
    }

    private var typeColor: Color {
        switch item {
        case is EventItem:         return Theme.Color.accent
        case is ReminderItem:      return Theme.Color.success
        case is AlarmItem:         return Theme.Color.danger
        case is HabitInstanceItem: return Theme.Color.warning
        default:                   return Theme.Color.textSecondary
        }
    }

    private var timeString: String? {
        switch item.anchor {
        case .timeBlock(let s, let e):
            return "\(s.formatted(.dateTime.hour().minute())) – \(e.formatted(.dateTime.hour().minute()))"
        case .point(let d):
            return d.formatted(.dateTime.hour().minute())
        default:
            return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.title]
        if let t = timeString { parts.append(t) }
        if item.importance != .normal { parts.append(item.importance.displayName) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Type-erased Identifiable wrapper for .sheet(item:)

private struct IdentifiableItem: Identifiable {
    let item: any Item
    var id: UUID { item.id }
}

#Preview("Today — seeded") {
    TodayView()
        .environment(AppEnvironment(useInMemory: true))
}
