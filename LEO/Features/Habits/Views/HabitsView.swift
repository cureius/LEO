import SwiftUI

@MainActor
struct HabitsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var habits: [Habit] = []
    @State private var instancesByHabit: [UUID: [HabitInstanceItem]] = [:]
    @State private var showAddHabit = false
    @State private var selectedHabit: Habit? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Today's rings
                if !habits.isEmpty {
                    todayRingsSection
                        .padding()
                }

                // Habit list
                List {
                    ForEach(habits.filter { !$0.isArchived }) { habit in
                        HabitRow(habit: habit, streak: streak(for: habit))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedHabit = habit }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddHabit = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await loadData() }
            .sheet(isPresented: $showAddHabit) {
                HabitEditView(habit: nil) { habit in
                    Task { try? await appEnv.habitRepository.add(habit); await loadData() }
                }
            }
            .sheet(item: $selectedHabit) { habit in
                HabitDetailView(habit: habit, instances: instancesByHabit[habit.id] ?? [])
            }
        }
    }

    // MARK: - Rings

    private var todayRingsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(habits.filter { !$0.isArchived }) { habit in
                    let instances = instancesByHabit[habit.id] ?? []
                    let todayInstances = instances.filter { instance -> Bool in
                        guard let d = instance.anchor.sortDate else { return false }
                        return Calendar.current.isDateInToday(d)
                    }
                    let done = todayInstances.filter(\.isCompleted).count
                    let total = max(1, todayInstances.count)
                    VStack(spacing: 4) {
                        HabitRing(progress: Double(done) / Double(total))
                            .frame(width: 52, height: 52)
                        Text(habit.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadData() async {
        habits = (try? await appEnv.habitRepository.fetchAll()) ?? []
        let now = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let window = DateInterval(start: start, end: now.addingTimeInterval(14 * 86400))
        let allInstances = (try? await appEnv.habitRepository.fetchInstances(in: window)) ?? []
        instancesByHabit = Dictionary(grouping: allInstances, by: \.habitID)
    }

    private func streak(for habit: Habit) -> StreakState {
        let instances = instancesByHabit[habit.id] ?? []
        return StreakEngine.currentStreak(for: habit, instances: instances)
    }
}

// MARK: - HabitRow

private struct HabitRow: View {
    let habit: Habit
    let streak: StreakState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(Theme.Typography.body.bold())
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.activeStreakDays > 0 ? Theme.Color.warning : Theme.Color.textSecondary)
                        .font(.caption)
                    Text("\(streak.activeStreakDays) day streak")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    if streak.atRisk {
                        Text("at risk")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.Color.danger.opacity(0.15))
                            .foregroundStyle(Theme.Color.danger)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.Color.textSecondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HabitRing (simple arc)

private struct HabitRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Color.surface, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - HabitDetailView

private struct HabitDetailView: View {
    let habit: Habit
    let instances: [HabitInstanceItem]
    @Environment(\.dismiss) private var dismiss

    var streak: StreakState { StreakEngine.currentStreak(for: habit, instances: instances) }

    var body: some View {
        NavigationStack {
            List {
                Section("Streak") {
                    LabeledContent("Current", value: "\(streak.activeStreakDays) days")
                    LabeledContent("Best", value: "\(streak.longestStreak) days")
                    if let remaining = streak.forgivenessRemainingThisPeriod {
                        LabeledContent("Misses left this week", value: "\(remaining)")
                    }
                }

                Section("90-day history") {
                    HabitCalendarHeatmap(instances: instances)
                }
            }
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Calendar heatmap

private struct HabitCalendarHeatmap: View {
    let instances: [HabitInstanceItem]

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date.now)
        return (0..<90).compactMap { i in
            Calendar.current.date(byAdding: .day, value: -(89 - i), to: today)
        }
    }

    private func completionFor(_ day: Date) -> Color {
        let dayInstances = instances.filter { instance -> Bool in
            guard let d = instance.anchor.sortDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: day)
        }
        if dayInstances.isEmpty { return Theme.Color.surface }
        return dayInstances.contains(where: \.isCompleted) ? Theme.Color.success : Theme.Color.danger.opacity(0.4)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 13), spacing: 3) {
            ForEach(days, id: \.self) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(completionFor(day))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

// MARK: - HabitEditView (stub for add/edit)

struct HabitEditView: View {
    let habit: Habit?
    let onSave: (Habit) -> Void
    @State private var name = ""
    @State private var timeHint = TimeOfDay.morning
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Morning run", text: $name)
                }
                Section("Time hint") {
                    Picker("When", selection: $timeHint) {
                        Text("Morning").tag(TimeOfDay.morning)
                        Text("Afternoon").tag(TimeOfDay.afternoon)
                        Text("Evening").tag(TimeOfDay.evening)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(habit == nil ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let h = Habit(
                            name: name.isEmpty ? "Habit" : name,
                            frequency: .daily,
                            timeHint: timeHint,
                            recurrenceRule: .daily()
                        )
                        onSave(h)
                        dismiss()
                    }
                }
            }
            .onAppear { name = habit?.name ?? "" }
        }
        .presentationDetents([.medium])
    }
}
