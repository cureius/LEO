import SwiftUI

/// 3-step flow: preferences → review → activated. Generates and applies a plan
/// fully on-device using FitnessPlanGenerator + the bundled FitnessLibrary.
@MainActor
struct GeneratePlanFlowView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .preferences
    @State private var preferences = PlanPreferences()
    @State private var plan: FitnessPlanGenerator.GeneratedPlan?
    @State private var includedWorkouts: Set<UUID> = []
    @State private var includedMeals: Set<UUID> = []
    @State private var isGenerating = false
    @State private var isActivating = false
    @State private var errorMessage: String?

    enum Step { case preferences, reviewing, activated }

    var body: some View {
        NavigationStack {
            content
                #if os(macOS)
                .overlay(alignment: .topTrailing) {
                    Button("Close") { dismiss() }
                        .padding(12)
                }
                #endif
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if step != .activated {
                        ToolbarItem(placement: .leoTopBarLeading) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
                .alert("Plan", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    private var navTitle: String {
        switch step {
        case .preferences: "New plan"
        case .reviewing:   "Review plan"
        case .activated:   "Plan activated"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .preferences:
            PlanPreferencesForm(preferences: $preferences, isGenerating: isGenerating, onGenerate: { Task { await generate() } })
        case .reviewing:
            if let plan {
                PlanReviewList(
                    plan: plan,
                    includedWorkouts: $includedWorkouts,
                    includedMeals: $includedMeals,
                    isActivating: isActivating,
                    onActivate: { Task { await activate() } },
                    onBack: { step = .preferences }
                )
            }
        case .activated:
            PlanActivatedSummary(
                workoutCount: includedWorkouts.count,
                mealCount: includedMeals.count,
                onDone: { dismiss() }
            )
        }
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let generator = FitnessPlanGenerator(bodyProfileRepository: appEnv.bodyProfileRepository)
        let result = await generator.generate(preferences: preferences)

        // Empty result → tell the user why and stay on preferences
        if result.workouts.isEmpty && result.meals.isEmpty {
            errorMessage = "We couldn't build a plan with these preferences. Try selecting more equipment options or different diet settings in your body profile."
            return
        }

        self.plan = result
        includedWorkouts = Set(result.workouts.map(\.id))
        includedMeals = Set(result.meals.map(\.id))
        withAnimation { step = .reviewing }
    }

    private func activate() async {
        guard let plan else { return }
        isActivating = true
        defer { isActivating = false }
        do {
            for w in plan.workouts where includedWorkouts.contains(w.id) {
                try await appEnv.itemRepository.add(w)
            }
            for m in plan.meals where includedMeals.contains(m.id) {
                try await appEnv.itemRepository.add(m)
            }
            withAnimation { step = .activated }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Step 1: Preferences

private struct PlanPreferencesForm: View {
    @Binding var preferences: PlanPreferences
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        Form {
            Section("Workout schedule") {
                Stepper("Duration: \(preferences.weeks) week\(preferences.weeks == 1 ? "" : "s")",
                        value: $preferences.weeks, in: 1...12)
                Stepper("Days per week: \(preferences.daysPerWeek)",
                        value: $preferences.daysPerWeek, in: 1...7)
                Picker("Split style", selection: $preferences.splitStyle) {
                    ForEach(SplitStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                DatePicker("Start date", selection: $preferences.startDate, displayedComponents: .date)
                Stepper("Start time: \(formatHour(preferences.workoutHour))",
                        value: $preferences.workoutHour, in: 5...22)
                Stepper("Session length: \(preferences.workoutDurationMinutes) min",
                        value: $preferences.workoutDurationMinutes, in: 20...120, step: 5)
            }

            Section("Equipment available") {
                ForEach(Equipment.allCases, id: \.self) { eq in
                    Button {
                        if preferences.equipment.contains(eq) {
                            preferences.equipment.remove(eq)
                        } else {
                            preferences.equipment.insert(eq)
                        }
                    } label: {
                        HStack {
                            Image(systemName: preferences.equipment.contains(eq) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(preferences.equipment.contains(eq) ? Theme.Color.accent : Theme.Color.textSecondary)
                            Text(eq.displayName)
                                .foregroundStyle(Theme.Color.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                if preferences.equipment.isEmpty {
                    Text("Select at least one — bodyweight is fine.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.warning)
                }
            }

            Section("Meal plan") {
                Toggle("Include meal plan", isOn: $preferences.includeMealPlan)
                if preferences.includeMealPlan {
                    Stepper("Meals per day: \(preferences.mealsPerDay)",
                            value: $preferences.mealsPerDay, in: 2...6)
                    Text("Recipes are selected from LEO's bundled library, filtered by your diet preferences and allergies in your body profile.")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Section {
                Button(action: onGenerate) {
                    HStack {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGenerating ? "Generating…" : "Generate plan")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || preferences.equipment.isEmpty)
            }
        }
    }

    private func formatHour(_ h: Int) -> String {
        let mod = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "AM" : "PM"
        return "\(mod):00 \(suffix)"
    }
}

// MARK: - Step 2: Review

private struct PlanReviewList: View {
    let plan: FitnessPlanGenerator.GeneratedPlan
    @Binding var includedWorkouts: Set<UUID>
    @Binding var includedMeals: Set<UUID>
    let isActivating: Bool
    let onActivate: () -> Void
    let onBack: () -> Void

    @State private var expandedWeeks: Set<Int> = [0]
    /// Resolved exercise metadata so we can show actual names + instructions
    /// without async-loading them in every row.
    @State private var exerciseLookup: [String: Exercise] = [:]

    private var workoutsByWeek: [(week: Int, items: [WorkoutItem])] {
        let grouped = Dictionary(grouping: plan.workouts) { weekNumber(for: $0.anchor.sortDate) }
        return grouped.sorted { $0.key < $1.key }.map { (week: $0.key, items: $0.value.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }) }
    }

    private var mealsByDay: [(day: Date, items: [MealItem])] {
        let grouped = Dictionary(grouping: plan.meals) { Calendar.current.startOfDay(for: $0.anchor.sortDate ?? .now) }
        return grouped.sorted { $0.key < $1.key }.map { (day: $0.key, items: $0.value.sorted { ($0.anchor.sortDate ?? .distantFuture) < ($1.anchor.sortDate ?? .distantFuture) }) }
    }

    private func weekNumber(for date: Date?) -> Int {
        guard let date, let first = plan.workouts.first?.anchor.sortDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: first), to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days / 7
    }

    var body: some View {
        List {
            Section { summaryCard }

            if !plan.workouts.isEmpty {
                Section("Workouts (\(includedWorkouts.count)/\(plan.workouts.count))") {
                    HStack {
                        Button("Select all") { plan.workouts.forEach { includedWorkouts.insert($0.id) } }
                        Spacer()
                        Button("Deselect all") { includedWorkouts.removeAll() }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)

                    ForEach(workoutsByWeek, id: \.week) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedWeeks.contains(group.week) },
                                set: { isOpen in
                                    if isOpen { expandedWeeks.insert(group.week) }
                                    else { expandedWeeks.remove(group.week) }
                                }
                            )
                        ) {
                            ForEach(group.items, id: \.id) { workout in
                                workoutRow(workout)
                            }
                        } label: {
                            HStack {
                                Text("Week \(group.week + 1)")
                                    .font(Theme.Typography.body.bold())
                                Spacer()
                                let included = group.items.filter { includedWorkouts.contains($0.id) }.count
                                Text("\(included)/\(group.items.count)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                }
            }

            if !plan.meals.isEmpty {
                Section("Meals (\(includedMeals.count)/\(plan.meals.count))") {
                    HStack {
                        Button("Select all") { plan.meals.forEach { includedMeals.insert($0.id) } }
                        Spacer()
                        Button("Deselect all") { includedMeals.removeAll() }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)

                    ForEach(mealsByDay.prefix(14), id: \.day) { group in
                        DisclosureGroup {
                            ForEach(group.items, id: \.id) { meal in
                                mealRow(meal)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                        .font(Theme.Typography.body)
                                    let total = group.items.reduce(0) { $0 + $1.targetKcal }
                                    Text("\(total) kcal · \(group.items.count) meals")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                }
                                Spacer()
                                let included = group.items.filter { includedMeals.contains($0.id) }.count
                                Text("\(included)/\(group.items.count)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                    if mealsByDay.count > 14 {
                        Text("Showing first 14 days. Remaining \(mealsByDay.count - 14) days are included by default.")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }

            Section {
                Button(action: onActivate) {
                    HStack {
                        if isActivating {
                            ProgressView().controlSize(.small)
                        }
                        Text(isActivating
                             ? "Activating…"
                             : "Activate plan (\(includedWorkouts.count + includedMeals.count) items)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActivating || (includedWorkouts.isEmpty && includedMeals.isEmpty))

                Button("Adjust preferences") { onBack() }
                    .frame(maxWidth: .infinity)
                    .disabled(isActivating)
            }
        }
        .task { await loadExerciseLookup() }
    }

    private func loadExerciseLookup() async {
        let ids = Set(plan.workouts.flatMap { $0.plannedExercises.map(\.exerciseID) })
        var lookup: [String: Exercise] = [:]
        for id in ids {
            if let ex = await FitnessLibrary.shared.exercise(id: id) {
                lookup[id] = ex
            }
        }
        exerciseLookup = lookup
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan summary")
                .font(.caption.bold())
                .foregroundStyle(Theme.Color.textSecondary)
            Text(plan.rationale)
                .font(Theme.Typography.body)
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("\(plan.workouts.count)").font(.title2.bold())
                    Text("workouts").font(.caption).foregroundStyle(Theme.Color.textSecondary)
                }
                VStack(alignment: .leading) {
                    Text("\(plan.meals.count)").font(.title2.bold())
                    Text("meals").font(.caption).foregroundStyle(Theme.Color.textSecondary)
                }
                VStack(alignment: .leading) {
                    Text("\(plan.dailyKcalTarget)").font(.title2.bold())
                    Text("kcal/day").font(.caption).foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func workoutRow(_ workout: WorkoutItem) -> some View {
        Button {
            toggle(workout.id, in: &includedWorkouts)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: includedWorkouts.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(includedWorkouts.contains(workout.id) ? Theme.Color.accent : Theme.Color.textSecondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.title)
                        .font(Theme.Typography.body.bold())
                        .foregroundStyle(Theme.Color.textPrimary)
                    if let start = workout.anchor.sortDate {
                        Text("\(start.formatted(.dateTime.weekday(.wide).month().day())) · \(start.formatted(.dateTime.hour().minute())) · ~\(workout.estimatedKcal) kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    // Exercise breakdown
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(workout.plannedExercises, id: \.exerciseID) { planned in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(Theme.Color.accent)
                                Text(exerciseLookup[planned.exerciseID]?.name ?? "Exercise")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                                Text(formatSetsReps(planned))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func formatSetsReps(_ p: PlannedExercise) -> String {
        if let mins = p.durationMin, mins > 0 {
            return "\(p.sets)×\(mins) min"
        }
        if let w = p.weightKg, w > 0 {
            return "\(p.sets)×\(p.reps) @ \(w.formatted(.number.precision(.fractionLength(1)))) kg"
        }
        return "\(p.sets)×\(p.reps)"
    }

    private func mealRow(_ meal: MealItem) -> some View {
        Button {
            toggle(meal.id, in: &includedMeals)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: includedMeals.contains(meal.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(includedMeals.contains(meal.id) ? Theme.Color.accent : Theme.Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title).font(Theme.Typography.body)
                    if let date = meal.anchor.sortDate {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Text("\(meal.targetKcal) kcal · \(meal.servings.formatted(.number.precision(.fractionLength(1)))) servings")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

// MARK: - Step 3: Activated

private struct PlanActivatedSummary: View {
    let workoutCount: Int
    let mealCount: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Color.success)
            Text("Plan activated")
                .font(.system(size: 28, weight: .bold))
            VStack(spacing: 8) {
                if workoutCount > 0 {
                    Text("\(workoutCount) workouts added")
                        .font(Theme.Typography.body)
                }
                if mealCount > 0 {
                    Text("\(mealCount) meals added")
                        .font(Theme.Typography.body)
                }
            }
            .foregroundStyle(Theme.Color.textSecondary)

            Text("You'll find them on Today and Fitness Home. Tap any item to complete it or log details.")
                .font(.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
        }
        .padding()
    }
}
