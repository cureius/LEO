import SwiftUI
import Charts

// MARK: - Section enum

enum HealthSection: CaseIterable {
    case habits, fitness, diet

    var title: String {
        switch self {
        case .habits:  return "Habits"
        case .fitness: return "Fitness"
        case .diet:    return "Diet"
        }
    }

    var icon: String {
        switch self {
        case .habits:  return "repeat.circle"
        case .fitness: return "figure.strengthtraining.traditional"
        case .diet:    return "fork.knife"
        }
    }
}

// MARK: - Root

@MainActor
struct HealthTabView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var section: HealthSection = .habits
    @State private var fitnessVM: FitnessHomeViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Pill picker — sits above all three NavigationStacks
            HealthSectionPicker(selected: $section)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.Color.background)

            Divider()

            // Each section owns its own NavigationStack so titles/toolbars compose cleanly.
            // Opacity + allowsHitTesting keeps state alive across switches.
            ZStack {
                HabitsView()
                    .opacity(section == .habits ? 1 : 0)
                    .allowsHitTesting(section == .habits)

                FitnessSection(vm: fitnessVM)
                    .opacity(section == .fitness ? 1 : 0)
                    .allowsHitTesting(section == .fitness)

                DietSection(vm: fitnessVM)
                    .opacity(section == .diet ? 1 : 0)
                    .allowsHitTesting(section == .diet)
            }
        }
        .background(Theme.Color.background)
        .task {
            let vm = FitnessHomeViewModel(
                itemRepository: appEnv.itemRepository,
                bodyProfileRepository: appEnv.bodyProfileRepository
            )
            fitnessVM = vm
            await vm.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await fitnessVM?.load() }
        }
    }
}

// MARK: - Pill picker

private struct HealthSectionPicker: View {
    @Binding var selected: HealthSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HealthSection.allCases, id: \.self) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selected = s }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: s.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(s.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selected == s ? .white : Theme.Color.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(selected == s ? Theme.Color.accent : Color.clear)
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.18), value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Color.surface)
        .clipShape(Capsule())
    }
}

// MARK: - Fitness section

private struct FitnessSection: View {
    let vm: FitnessHomeViewModel?

    @State private var showWorkoutDetail: WorkoutItem?
    @State private var showAddMeasurement = false
    @State private var showMeasurements = false
    @State private var showGeneratePlan = false
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    fitnessContent(vm: vm)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .leoTopBarLeading) {
                    Button { showGeneratePlan = true } label: {
                        Label("New plan", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .leoTopBarTrailing) {
                    Button { showAddMeasurement = true } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(item: $showWorkoutDetail) { workout in
            WorkoutDetailSheet(
                workout: workout,
                onComplete: { updated in Task { await vm?.completeWorkout(updated) } },
                onUncomplete: { updated in Task { await vm?.uncompleteWorkout(updated) } }
            )
        }
        .sheet(isPresented: $showAddMeasurement) {
            FitnessAddMeasurementSheet { kg, fat in
                Task { await vm?.addMeasurement(weightKg: kg, bodyFatPct: fat) }
            }
        }
        .sheet(isPresented: $showMeasurements) {
            if let vm {
                MeasurementsChartView(measurements: vm.measurements, onAdd: {
                    showMeasurements = false
                    showAddMeasurement = true
                })
            }
        }
        .sheet(isPresented: $showGeneratePlan) {
            GeneratePlanFlowView().environment(appEnv)
        }
    }

    @ViewBuilder
    private func fitnessContent(vm: FitnessHomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                kcalCard(vm: vm)
                workoutSection(vm: vm)
                weekStripCard(vm: vm)
                measurementsCard(vm: vm)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: Kcal card (burn-focused for fitness context)

    private func kcalCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 16) {
                HStack {
                    Text("Today's Energy")
                        .font(Theme.Typography.body.bold())
                    Spacer()
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month().day())
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                HStack(spacing: 0) {
                    // Burned — primary
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.warning)
                        Text("\(vm.kcalBurned)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(vm.kcalBurned > 0 ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                        Text("Burned")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Theme.Color.divider)
                        .frame(width: 1, height: 52)

                    // Consumed
                    VStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                        Text("\(vm.kcalIn)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Consumed")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Theme.Color.divider)
                        .frame(width: 1, height: 52)

                    // Net
                    let net = vm.kcalIn - vm.kcalBurned
                    VStack(spacing: 4) {
                        Image(systemName: net >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(abs(net) > 400 ? Theme.Color.warning : Theme.Color.success)
                        Text(net == 0 ? "0" : (net > 0 ? "+\(net)" : "\(net)"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Net")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Target reference line
                GeometryReader { geo in
                    let burnRatio = min(1, Double(vm.kcalBurned) / max(1, Double(vm.kcalTarget / 4)))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.Color.surface).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: [Theme.Color.warning, Theme.Color.danger.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * burnRatio), height: 5)
                            .animation(.spring(duration: 0.5), value: burnRatio)
                    }
                }
                .frame(height: 5)

                Text("Target: \(vm.kcalTarget) kcal/day")
                    .font(.caption2)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Workout section

    @ViewBuilder
    private func workoutSection(vm: FitnessHomeViewModel) -> some View {
        if vm.todayWorkouts.isEmpty {
            Button { showGeneratePlan = true } label: {
                LEOCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Theme.Color.accent.opacity(0.1)).frame(width: 44, height: 44)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No workout today")
                                .font(Theme.Typography.body.bold()).foregroundStyle(Theme.Color.textPrimary)
                            Text("Tap to generate a personalised plan")
                                .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles").foregroundStyle(Theme.Color.accent)
                    }
                }
            }.buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if vm.todayWorkouts.count > 1 {
                    HStack {
                        Text("Today's Workouts")
                            .font(Theme.Typography.body.bold()).padding(.horizontal, 4)
                        Spacer()
                        let done = vm.todayWorkouts.filter(\.isCompleted).count
                        Text("\(done)/\(vm.todayWorkouts.count) done")
                            .font(.caption).foregroundStyle(Theme.Color.textSecondary).padding(.horizontal, 4)
                    }
                }
                ForEach(vm.todayWorkouts) { workout in
                    workoutCard(workout, vm: vm)
                }
            }
        }
    }

    private func workoutCard(_ workout: WorkoutItem, vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(workout.isCompleted ? Theme.Color.success.opacity(0.15) : Theme.Color.accent.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: workout.isCompleted ? "checkmark" : "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(workout.isCompleted ? Theme.Color.success : Theme.Color.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title).font(Theme.Typography.body.bold())
                        .strikethrough(workout.isCompleted, color: Theme.Color.textSecondary)
                    HStack(spacing: 6) {
                        Text("\(workout.plannedExercises.count) exercises")
                        Text("·")
                        Text("~\(workout.estimatedKcal) kcal")
                    }
                    .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                    if let start = workout.anchor.sortDate {
                        Text(start, style: .time).font(.caption2).foregroundStyle(Theme.Color.textSecondary.opacity(0.7))
                    }
                }
                Spacer()
                if workout.isCompleted {
                    Button { showWorkoutDetail = workout } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Color.success)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Mark as incomplete", systemImage: "arrow.uturn.backward.circle") {
                            Task { await vm.uncompleteWorkout(workout) }
                        }
                    }
                } else {
                    Button("Start") { showWorkoutDetail = workout }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.Color.accent)
                }
            }
        }
        .contextMenu {
            if workout.isCompleted {
                Button("Mark as incomplete", systemImage: "arrow.uturn.backward.circle") {
                    Task { await vm.uncompleteWorkout(workout) }
                }
            } else {
                Button("Start workout", systemImage: "play.circle") {
                    showWorkoutDetail = workout
                }
            }
        }
    }

    // MARK: Week strip card

    private func weekStripCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(Theme.Typography.body.bold())
                        let done = vm.weekWorkouts.filter(\.isCompleted).count
                        let total = vm.weekWorkouts.count
                        Text(total == 0 ? "No sessions planned" : "\(done) of \(total) sessions done")
                            .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    ZStack {
                        Circle().stroke(Theme.Color.surface, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: vm.weekAdherenceRatio)
                            .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(vm.weekAdherenceRatio * 100))%")
                            .font(.system(size: 11, weight: .bold))
                    }.frame(width: 48, height: 48)
                }
                HStack(spacing: 0) {
                    ForEach(vm.weekDays, id: \.self) { day in
                        FitnessWeekDayCell(day: day, workouts: vm.workouts(on: day))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Measurements card

    private func measurementsCard(vm: FitnessHomeViewModel) -> some View {
        Button { showMeasurements = true } label: {
            LEOCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.Color.accent.opacity(0.1)).frame(width: 36, height: 36)
                        Image(systemName: "scalemass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body measurements")
                            .font(Theme.Typography.body.bold()).foregroundStyle(Theme.Color.textPrimary)
                        if let latest = vm.measurements.first {
                            HStack(spacing: 6) {
                                Text("\(latest.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                                if let fat = latest.bodyFatPct {
                                    Text("·")
                                    Text("\(fat.formatted(.number.precision(.fractionLength(1))))% BF")
                                }
                                Text("·")
                                Text(latest.date, style: .date)
                            }
                            .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                        } else {
                            Text("No measurements yet — tap to add")
                                .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }.buttonStyle(.plain)
    }
}

// MARK: - Fitness week day cell

private struct FitnessWeekDayCell: View {
    let day: Date
    let workouts: [WorkoutItem]

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isPast: Bool { day < Calendar.current.startOfDay(for: .now) }

    private enum Status { case rest, planned, completed, partial, missed }
    private var status: Status {
        if workouts.isEmpty { return .rest }
        let allDone = workouts.allSatisfy(\.isCompleted)
        let anyDone = workouts.contains(where: \.isCompleted)
        if allDone { return .completed }
        if anyDone { return .partial }
        return isPast ? .missed : .planned
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.Color.accent : Theme.Color.textSecondary)
            ZStack {
                switch status {
                case .completed: Circle().fill(Theme.Color.accent)
                case .partial:   Circle().fill(Theme.Color.warning)
                case .missed:    Circle().fill(Theme.Color.danger.opacity(0.7))
                case .planned:   Circle().strokeBorder(Theme.Color.accent, lineWidth: 1.5)
                case .rest:      Circle().fill(Color.clear)
                }
                if status != .rest {
                    Image(systemName: status == .completed ? "checkmark" : "figure.strengthtraining.traditional")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(status == .planned ? Theme.Color.accent : .white)
                }
            }
            .frame(width: 30, height: 30)
            Circle()
                .fill(isToday ? Theme.Color.accent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Diet section

private struct DietSection: View {
    let vm: FitnessHomeViewModel?
    @State private var showMealDetail: MealItem?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    dietContent(vm: vm)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Diet")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $showMealDetail) { meal in
            MealDetailSheet(meal: meal, onComplete: { updatedMeal, servings in
                Task { await vm?.completeMeal(updatedMeal, servings: servings) }
            })
        }
    }

    @ViewBuilder
    private func dietContent(vm: FitnessHomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Calories card (same as fitness — diet is the intake side)
                macroSummaryCard(vm: vm)

                // Today's meals
                if vm.todayMeals.isEmpty {
                    emptyMealsCard
                } else {
                    mealSection(vm.todayMeals, vm: vm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    private func macroSummaryCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Calories today")
                        .font(Theme.Typography.body.bold())
                    Spacer()
                    let remaining = vm.kcalTarget - vm.kcalIn
                    Text(remaining >= 0 ? "\(remaining) left" : "+\(abs(remaining)) over")
                        .font(.caption.bold())
                        .foregroundStyle(remaining >= 0 ? Theme.Color.textSecondary : Theme.Color.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(remaining >= 0 ? Theme.Color.surface : Theme.Color.warning.opacity(0.12))
                        .clipShape(Capsule())
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(vm.kcalIn)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                    Text("/ \(vm.kcalTarget) kcal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.Color.surface).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(vm.kcalProgress >= 1 ? Theme.Color.warning : Theme.Color.success)
                            .frame(width: max(0, geo.size.width * vm.kcalProgress), height: 8)
                            .animation(.spring(duration: 0.4), value: vm.kcalProgress)
                    }
                }.frame(height: 8)
                // Meal breakdown summary
                let logged = vm.todayMeals.filter(\.isCompleted).count
                let total = vm.todayMeals.count
                HStack {
                    Label(total == 0 ? "No meals planned" : "\(logged) of \(total) meals logged",
                          systemImage: "fork.knife")
                        .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private var emptyMealsCard: some View {
        LEOCard {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Color.textSecondary.opacity(0.4))
                Text("No meals planned today")
                    .font(Theme.Typography.body.bold())
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Generate a fitness plan from the Fitness tab to get meal suggestions.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func mealSection(_ meals: [MealItem], vm: FitnessHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Meals")
                .font(Theme.Typography.body.bold())
                .padding(.horizontal, 4)

            ForEach(meals) { meal in
                Button { showMealDetail = meal } label: {
                    LEOCard {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(meal.isCompleted
                                          ? Theme.Color.success.opacity(0.12)
                                          : Theme.Color.accent.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: meal.isCompleted ? "checkmark" : "fork.knife")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(meal.isCompleted ? Theme.Color.success : Theme.Color.accent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(meal.title)
                                    .font(Theme.Typography.body)
                                    .strikethrough(meal.isCompleted, color: Theme.Color.textSecondary)
                                    .foregroundStyle(meal.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                                HStack(spacing: 6) {
                                    Text("\(meal.displayKcal) kcal")
                                    Text("·")
                                    Text("\(meal.servings.formatted(.number.precision(.fractionLength(1)))) serving(s)")
                                }
                                .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                                if let d = meal.anchor.sortDate {
                                    Text(d, style: .time).font(.caption2)
                                        .foregroundStyle(Theme.Color.textSecondary.opacity(0.7))
                                }
                            }
                            Spacer()
                            if meal.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Color.success)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Add measurement sheet (local copy for FitnessSection)

private struct FitnessAddMeasurementSheet: View {
    let onSave: (Double, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var fatText = ""

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight (kg)") {
                    TextField("e.g. 75.5", text: $weightText).keyboardType(.decimalPad)
                }
                Section("Body fat % (optional)") {
                    TextField("e.g. 18", text: $fatText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Log measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let kg = parsedWeight else { return }
                        let fat = Double(fatText.replacingOccurrences(of: ",", with: "."))
                        onSave(kg, fat)
                        dismiss()
                    }
                    .disabled(parsedWeight == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    HealthTabView()
        .environment(AppEnvironment(useInMemory: true))
}
