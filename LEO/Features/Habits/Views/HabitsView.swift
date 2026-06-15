import SwiftUI

// MARK: - Main view

@MainActor
struct HabitsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var habits: [Habit] = []
    @State private var instancesByHabit: [UUID: [HabitInstanceItem]] = [:]
    @State private var isLoading = false
    @State private var showAddHabit = false

    var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    // Habits scheduled for today based on their frequency rule
    private var habitsScheduledToday: [Habit] {
        activeHabits.filter { isScheduledOn($0, date: .now) }
    }

    // Today's completion totals (only counts habits scheduled today)
    private var todayDone: Int  { habitsScheduledToday.filter { todayCompleted(for: $0) }.count }
    private var todayTotal: Int { habitsScheduledToday.count }
    private var todayProgress: Double {
        todayTotal == 0 ? 0 : Double(todayDone) / Double(todayTotal)
    }

    // MARK: - Schedule helpers

    /// Returns true if the habit is supposed to run on the given date's weekday.
    private func isScheduledOn(_ habit: Habit, date: Date) -> Bool {
        switch habit.frequency {
        case .daily:               return true
        case .timesPerWeek:        return true
        case .specificDays(let days):
            return days.contains(weekday(from: date))
        case .custom:              return true
        }
    }

    private func weekday(from date: Date) -> Weekday {
        switch Calendar.current.component(.weekday, from: date) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && habits.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if habits.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .leoTopBarTrailing) {
                    Button { showAddHabit = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showAddHabit) {
                HabitEditView(habit: nil) { newHabit in
                    Task {
                        try? await appEnv.habitRepository.add(newHabit)
                        await loadData()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
                Task { await loadData() }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                // Today's progress header
                TodayProgressHeader(done: todayDone, total: todayTotal, progress: todayProgress)
                    .padding()

                // Today's habit cards — only habits scheduled for today's weekday
                if !habitsScheduledToday.isEmpty {
                    SectionLabel("Today")
                    TodayHabitsGrid(
                        habits: habitsScheduledToday,
                        instancesByHabit: instancesByHabit,
                        onComplete: { habit in Task { await completeToday(habit: habit) } }
                    )
                    .padding(.horizontal)
                }

                // All habits list
                SectionLabel("All Habits")
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(activeHabits) { habit in
                        NavigationLink {
                            HabitDetailView(
                                habit: habit,
                                instances: instancesByHabit[habit.id] ?? [],
                                streak: streakState(for: habit),
                                onComplete: { Task { await completeToday(habit: habit) } },
                                onDelete: { Task { await deleteHabit(habit) } }
                            )
                        } label: {
                            HabitListRow(
                                habit: habit,
                                streak: streakState(for: habit),
                                instances: instancesByHabit[habit.id] ?? [],
                                completedToday: todayCompleted(for: habit)
                            )
                            .leoCard()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await deleteHabit(habit) }
                            } label: {
                                Label("Delete Habit", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer().frame(height: 32)
            }
        }
        .background(Theme.Color.background)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "repeat.circle")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.textSecondary)
            Text("No habits yet")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Tap + to create your first habit and start building streaks.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { showAddHabit = true } label: {
                Label("Add first habit", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func streakState(for habit: Habit) -> StreakState {
        StreakEngine.currentStreak(for: habit, instances: instancesByHabit[habit.id] ?? [])
    }

    private func todayCompleted(for habit: Habit) -> Bool {
        let instances = instancesByHabit[habit.id] ?? []
        return instances.contains {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d) && $0.isCompleted
        }
    }

    // MARK: - Actions

    private func completeToday(habit: Habit) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let instances = instancesByHabit[habit.id] ?? []

        // Already marked done today — nothing to do
        if instances.contains(where: {
            guard let d = $0.anchor.sortDate else { return false }
            return cal.isDate(d, inSameDayAs: today) && $0.isCompleted
        }) { return }

        if let existing = instances.first(where: {
            guard let d = $0.anchor.sortDate else { return false }
            return cal.isDate(d, inSameDayAs: today) && !$0.isCompleted
        }) {
            // Update the existing open instance
            var updated = existing
            updated.completion = .completed(at: .now)
            updated.updatedAt  = .now
            try? await appEnv.habitRepository.updateInstance(updated)
        } else {
            // No instance exists for today yet — create one and mark it complete.
            // This handles the case where the habit materialiser hasn't run or
            // seeded data didn't extend to today's date.
            let hintHour = habit.timeHint?.hintHour ?? 9
            let start = cal.date(bySettingHour: hintHour, minute: 0, second: 0, of: today) ?? today
            let duration = Double(habit.targetDuration?.components.seconds ?? 1800)
            let newInstance = HabitInstanceItem(
                title: habit.name,
                anchor: .timeBlock(start: start, end: start.addingTimeInterval(duration)),
                completion: .completed(at: .now),
                habitID: habit.id,
                targetDuration: habit.targetDuration
            )
            try? await appEnv.habitRepository.addInstance(newInstance)
        }

        await loadData()
    }

    private func deleteHabit(_ habit: Habit) async {
        try? await appEnv.habitRepository.delete(id: habit.id)
        await loadData()
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        habits = (try? await appEnv.habitRepository.fetchAll()) ?? []
        let now = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let window = DateInterval(start: start, end: now.addingTimeInterval(14 * 86400))
        let all = (try? await appEnv.habitRepository.fetchInstances(in: window)) ?? []
        instancesByHabit = Dictionary(grouping: all, by: \.habitID)
    }
}

// MARK: - Today progress header

private struct TodayProgressHeader: View {
    let done: Int
    let total: Int
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(done)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                Text("of \(total) done today")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.bottom, 2)
                Spacer()
                if done == total && total > 0 {
                    Text("All done! 🎉")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Color.success.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Color.surface)
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Color.accent, Theme.Color.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(.spring(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Today habits grid

private struct TodayHabitsGrid: View {
    let habits: [Habit]
    let instancesByHabit: [UUID: [HabitInstanceItem]]
    let onComplete: (Habit) -> Void

    // The habits list is already pre-filtered to today's schedule by the parent.
    // We only need to check completion state from instances.
    private func isCompleted(_ habit: Habit) -> Bool {
        (instancesByHabit[habit.id] ?? []).contains {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d) && $0.isCompleted
        }
    }

    var body: some View {
        if habits.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Color.success)
                Text("No habits scheduled for today")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.vertical, 12)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(habits) { habit in
                    TodayHabitCard(
                        habit: habit,
                        isCompleted: isCompleted(habit),
                        onTap: { onComplete(habit) }
                    )
                }
            }
        }
    }
}

// MARK: - Today habit card

private struct TodayHabitCard: View {
    let habit: Habit
    let isCompleted: Bool
    let onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            guard !isCompleted else { return }
            withAnimation(.spring(duration: 0.3)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onTap() }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    // Completion ring/check
                    ZStack {
                        Circle()
                            .stroke(
                                isCompleted ? Theme.Color.success : Theme.Color.divider,
                                lineWidth: 2.5
                            )
                            .frame(width: 32, height: 32)
                        if isCompleted {
                            Circle()
                                .fill(Theme.Color.success)
                                .frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .fill(Theme.Color.accent.opacity(0.08))
                                .frame(width: 32, height: 32)
                        }
                    }
                    .scaleEffect(pressed ? 1.15 : 1)
                    .animation(.spring(duration: 0.3), value: pressed)

                    Spacer()

                    if isCompleted {
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Color.success)
                    }
                }

                Text(habit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                    .lineLimit(2)

                if let hint = habit.timeHint {
                    Text(hint.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCompleted
                    ? Theme.Color.success.opacity(0.06)
                    : Theme.Color.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(
                        isCompleted ? Theme.Color.success.opacity(0.3) : Theme.Color.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onChange(of: isCompleted) { _, _ in pressed = false }
    }
}

// MARK: - Habit list row

private struct HabitListRow: View {
    let habit: Habit
    let streak: StreakState
    let instances: [HabitInstanceItem]
    let completedToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Today's ring
            TodayRing(
                completedToday: completedToday,
                scheduledToday: todayScheduled
            )

            // Name + metadata
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    if streak.atRisk {
                        Text("At Risk")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.danger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.Color.danger.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    // Streak
                    HStack(spacing: 3) {
                        Image(systemName: streak.activeStreakDays > 0 ? "flame.fill" : "flame")
                            .font(.system(size: 11))
                            .foregroundStyle(streak.activeStreakDays > 0 ? Theme.Color.warning : Theme.Color.textSecondary)
                        Text("\(streak.activeStreakDays)d")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }

                    Text("·")
                        .foregroundStyle(Theme.Color.divider)

                    // Schedule text
                    Text(scheduleText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }

                // 7-day mini heatmap
                MiniHeatmap(instances: instances)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary.opacity(0.5))
        }
    }

    private var todayScheduled: Bool {
        instances.contains {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d)
        }
    }

    private var scheduleText: String {
        switch habit.frequency {
        case .daily:             return "Daily"
        case .timesPerWeek(let n): return "\(n)× / week"
        case .specificDays(let days):
            return days.sorted(by: { $0.sortOrder < $1.sortOrder })
                       .map { $0.displayName }
                       .joined(separator: " · ")
        case .custom:            return "Custom"
        }
    }
}

// MARK: - Today ring (small indicator)

private struct TodayRing: View {
    let completedToday: Bool
    let scheduledToday: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Color.surface, lineWidth: 3.5)
                .frame(width: 36, height: 36)

            if scheduledToday {
                if completedToday {
                    Circle()
                        .fill(Theme.Color.success)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.0)
                        .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 3.5)
                        .frame(width: 36, height: 36)
                }
            } else {
                // Not scheduled today — dim dash
                Text("—")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.3))
            }
        }
    }
}

// MARK: - 7-day mini heatmap dots

private struct MiniHeatmap: View {
    let instances: [HabitInstanceItem]

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).map {
            Calendar.current.date(byAdding: .day, value: -( 6 - $0), to: today)!
        }
    }

    private func color(for day: Date) -> Color {
        let dayInst = instances.filter {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
        }
        if dayInst.isEmpty { return Theme.Color.surface }
        return dayInst.contains(where: \.isCompleted)
            ? Theme.Color.success.opacity(0.7)
            : Theme.Color.danger.opacity(0.35)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: day))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Section label

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

// MARK: - Habit detail view

struct HabitDetailView: View {
    let habit: Habit
    let instances: [HabitInstanceItem]
    let streak: StreakState
    let onComplete: () -> Void
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var completedToday: Bool {
        instances.contains {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDateInToday(d) && $0.isCompleted
        }
    }

    private var completionRateLast30: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -29, to: today)!
        let window = instances.filter {
            guard let d = $0.anchor.sortDate else { return false }
            return d >= start && d <= today
        }
        guard !window.isEmpty else { return 0 }
        return Double(window.filter(\.isCompleted).count) / Double(window.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Hero streak
                streakHero

                // Complete today button
                completeTodayButton

                // This week
                thisWeekSection

                // Stats
                statsSection

                // Heatmap
                heatmapSection

                // Delete
                deleteButton
            }
            .padding()
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.large)
        .background(Theme.Color.background)
        .toolbar {
            ToolbarItem(placement: .leoTopBarTrailing) {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete “\(habit.name)”?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Habit", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the habit and its entire history. This can’t be undone.")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Habit")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Color.danger.opacity(0.1))
            .foregroundStyle(Theme.Color.danger)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    // MARK: - Sections

    private var streakHero: some View {
        HStack(spacing: Theme.Spacing.xl) {
            streakCard(
                value: "\(streak.activeStreakDays)",
                label: "Current",
                icon: "flame.fill",
                color: streak.activeStreakDays > 0 ? Theme.Color.warning : Theme.Color.textSecondary
            )
            Divider().frame(height: 50)
            streakCard(
                value: "\(streak.longestStreak)",
                label: "Best ever",
                icon: "trophy.fill",
                color: .yellow
            )
            if let remaining = streak.forgivenessRemainingThisPeriod {
                Divider().frame(height: 50)
                streakCard(
                    value: "\(remaining)",
                    label: "Misses left",
                    icon: "shield.fill",
                    color: remaining == 0 ? Theme.Color.danger : Theme.Color.accent
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private func streakCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var completeTodayButton: some View {
        if completedToday {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Color.success)
                Text("Completed today!")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.success)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Color.success.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.Color.success.opacity(0.3), lineWidth: 1)
            )
        } else {
            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Mark today complete")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Color.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            HStack(spacing: 0) {
                ForEach(thisWeekDays, id: \.self) { day in
                    WeekDayCell(day: day, instances: instances)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var thisWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        let daysBack = (weekday + 5) % 7  // Monday = 0
        let monday = cal.date(byAdding: .day, value: -daysBack, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    private var statsSection: some View {
        VStack(spacing: 0) {
            StatRow(label: "Completion rate (30 days)",
                    value: String(format: "%.0f%%", completionRateLast30 * 100))
            Divider()
            StatRow(label: "Schedule",   value: scheduleText)
            if let hint = habit.timeHint {
                Divider()
                StatRow(label: "Time",   value: hint.displayName)
            }
            Divider()
            StatRow(label: "Started",    value: habit.createdAt.formatted(.dateTime.month().day().year()))
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var scheduleText: String {
        switch habit.frequency {
        case .daily:              return "Every day"
        case .timesPerWeek(let n): return "\(n) times per week"
        case .specificDays(let days):
            return days.sorted(by: { $0.sortOrder < $1.sortOrder })
                       .map(\.displayName).joined(separator: ", ")
        case .custom: return "Custom"
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("90-day history")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    legendDot(color: Theme.Color.success.opacity(0.8), label: "Done")
                    legendDot(color: Theme.Color.danger.opacity(0.4),  label: "Missed")
                    legendDot(color: Theme.Color.surface,              label: "—")
                }
            }
            HabitCalendarHeatmap(instances: instances)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

// MARK: - Week day cell (detail view)

private struct WeekDayCell: View {
    let day: Date
    let instances: [HabitInstanceItem]

    private var state: CellState {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let dayStart = cal.startOfDay(for: day)
        let dayInst = instances.filter {
            guard let d = $0.anchor.sortDate else { return false }
            return cal.isDate(d, inSameDayAs: day)
        }
        if dayInst.isEmpty   { return dayStart > today ? .future : .noInstance }
        if dayInst.contains(where: \.isCompleted) { return .done }
        return dayStart > today ? .scheduled : .missed
    }

    enum CellState { case done, missed, scheduled, future, noInstance }

    private var label: String { day.formatted(.dateTime.weekday(.narrow)) }
    private var number: String { day.formatted(.dateTime.day()) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isToday ? Theme.Color.accent : Theme.Color.textSecondary)

            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 32, height: 32)
                if isToday {
                    Circle()
                        .strokeBorder(Theme.Color.accent, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var circleFill: Color {
        switch state {
        case .done:       return Theme.Color.success
        case .missed:     return Theme.Color.danger.opacity(0.15)
        case .scheduled:  return Theme.Color.accent.opacity(0.12)
        case .future, .noInstance: return Color.clear
        }
    }

    private var iconName: String {
        switch state {
        case .done:      return "checkmark"
        case .missed:    return "xmark"
        case .scheduled: return "circle"
        case .future, .noInstance: return "minus"
        }
    }

    private var iconColor: Color {
        switch state {
        case .done:      return .white
        case .missed:    return Theme.Color.danger
        case .scheduled: return Theme.Color.accent
        case .future, .noInstance: return Theme.Color.textSecondary.opacity(0.3)
        }
    }
}

// MARK: - Heatmap

private struct HabitCalendarHeatmap: View {
    let instances: [HabitInstanceItem]

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date.now)
        return (0..<90).map {
            Calendar.current.date(byAdding: .day, value: -(89 - $0), to: today)!
        }
    }

    private func fill(for day: Date) -> Color {
        let dayInst = instances.filter {
            guard let d = $0.anchor.sortDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
        }
        if dayInst.isEmpty { return Theme.Color.surface }
        return dayInst.contains(where: \.isCompleted)
            ? Theme.Color.success.opacity(0.75)
            : Theme.Color.danger.opacity(0.35)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 13),
            spacing: 3
        ) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill(for: day))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

// MARK: - Detail stat row

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Weekday sort order helper

private extension Weekday {
    var sortOrder: Int {
        switch self {
        case .monday: return 0; case .tuesday: return 1; case .wednesday: return 2
        case .thursday: return 3; case .friday: return 4; case .saturday: return 5
        case .sunday: return 6
        }
    }
}

// MARK: - HabitEditView

struct HabitEditView: View {
    let habit: Habit?
    let onSave: (Habit) -> Void
    @State private var name = ""
    @State private var timeHint = TimeOfDay.morning
    @State private var frequency = HabitFrequency.daily
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Morning run", text: $name)
                }
                Section("Time of day") {
                    Picker("When", selection: $timeHint) {
                        Text("Morning").tag(TimeOfDay.morning)
                        Text("Afternoon").tag(TimeOfDay.afternoon)
                        Text("Evening").tag(TimeOfDay.evening)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Frequency") {
                    Picker("How often", selection: $frequency) {
                        Text("Daily").tag(HabitFrequency.daily)
                        Text("Mon / Wed / Fri")
                            .tag(HabitFrequency.specificDays([.monday, .wednesday, .friday]))
                        Text("Tue / Thu")
                            .tag(HabitFrequency.specificDays([.tuesday, .thursday]))
                        Text("Weekdays")
                            .tag(HabitFrequency.specificDays([.monday, .tuesday, .wednesday, .thursday, .friday]))
                        Text("Weekends")
                            .tag(HabitFrequency.specificDays([.saturday, .sunday]))
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rRule: RecurrenceRule
                        switch frequency {
                        case .daily: rRule = .daily()
                        case .specificDays(let days): rRule = .weekly(on: days)
                        default: rRule = .daily()
                        }
                        let h = Habit(
                            id: habit?.id ?? UUID(),
                            name: name.isEmpty ? "Habit" : name,
                            frequency: frequency,
                            timeHint: timeHint,
                            recurrenceRule: rRule
                        )
                        onSave(h)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = habit?.name ?? ""
                if let h = habit { timeHint = h.timeHint ?? .morning; frequency = h.frequency }
            }
        }
        .presentationDetents([.large])
    }
}
