import SwiftUI
import Charts

@MainActor
struct FitnessHomeView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm: FitnessHomeViewModel?
    @State private var showWorkoutDetail: WorkoutItem?
    @State private var showMealDetail: MealItem?
    @State private var showMeasurements = false
    @State private var showAddMeasurement = false
    @State private var showGeneratePlan = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    content(vm: vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .leoTopBarLeading) {
                    Button {
                        showGeneratePlan = true
                    } label: {
                        Label("New plan", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .leoTopBarTrailing) {
                    Button {
                        showAddMeasurement = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .task {
            let v = FitnessHomeViewModel(
                itemRepository: appEnv.itemRepository,
                bodyProfileRepository: appEnv.bodyProfileRepository
            )
            vm = v
            await v.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await vm?.load() }
        }
        .sheet(item: $showWorkoutDetail) { workout in
            WorkoutDetailSheet(workout: workout, onComplete: { actual in
                Task { await vm?.completeWorkout(actual) }
            })
        }
        .sheet(item: $showMealDetail) { meal in
            MealDetailSheet(meal: meal, onComplete: { updatedMeal, servings in
                Task { await vm?.completeMeal(updatedMeal, servings: servings) }
            })
        }
        .sheet(isPresented: $showAddMeasurement) {
            AddMeasurementSheet { kg, fat in
                Task { await vm?.addMeasurement(weightKg: kg, bodyFatPct: fat) }
            }
        }
        .sheet(isPresented: $showMeasurements) {
            if let v = vm {
                MeasurementsChartView(measurements: v.measurements, onAdd: {
                    showMeasurements = false
                    showAddMeasurement = true
                })
            }
        }
        .sheet(isPresented: $showGeneratePlan) {
            GeneratePlanFlowView()
                .environment(appEnv)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(vm: FitnessHomeViewModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                kcalCard(vm: vm)
                workoutSection(vm: vm)
                if !vm.todayMeals.isEmpty {
                    mealSection(vm.todayMeals, vm: vm)
                }
                weekStripCard(vm: vm)
                measurementsPreviewCard(vm: vm)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Kcal card (progress bar style)

    private func kcalCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories today")
                            .font(Theme.Typography.body.bold())
                        Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    // Remaining / surplus badge
                    let remaining = vm.kcalTarget - vm.kcalIn
                    Text(remaining >= 0 ? "\(remaining) left" : "+\(abs(remaining)) over")
                        .font(.caption.bold())
                        .foregroundStyle(remaining >= 0 ? Theme.Color.textSecondary : Theme.Color.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((remaining >= 0 ? Theme.Color.surface : Theme.Color.warning.opacity(0.12)))
                        .clipShape(Capsule())
                }

                // Large consumed number + target
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(vm.kcalIn)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                    Text("/ \(vm.kcalTarget) kcal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Color.surface)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(vm.kcalProgress >= 1 ? Theme.Color.warning : Theme.Color.accent)
                            .frame(width: max(0, geo.size.width * vm.kcalProgress), height: 8)
                            .animation(.spring(duration: 0.4), value: vm.kcalProgress)
                    }
                }
                .frame(height: 8)

                // Bottom row: burned + macros hint
                HStack {
                    if vm.kcalBurned > 0 {
                        Label("\(vm.kcalBurned) kcal burned", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.warning)
                    } else {
                        Label("No workouts logged yet", systemImage: "figure.strengthtraining.traditional")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    if vm.kcalIn == 0 {
                        Text("Log meals to track intake")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Workout section (all today's workouts)

    @ViewBuilder
    private func workoutSection(vm: FitnessHomeViewModel) -> some View {
        if vm.todayWorkouts.isEmpty {
            emptyWorkoutCard
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if vm.todayWorkouts.count > 1 {
                    HStack {
                        Text("Today's Workouts")
                            .font(Theme.Typography.body.bold())
                            .padding(.horizontal, 4)
                        Spacer()
                        let done = vm.todayWorkouts.filter(\.isCompleted).count
                        Text("\(done)/\(vm.todayWorkouts.count) done")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.horizontal, 4)
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
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // Status icon
                    ZStack {
                        Circle()
                            .fill(workout.isCompleted ? Theme.Color.success.opacity(0.15) : Theme.Color.accent.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: workout.isCompleted ? "checkmark" : "figure.strengthtraining.traditional")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(workout.isCompleted ? Theme.Color.success : Theme.Color.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(Theme.Typography.body.bold())
                            .strikethrough(workout.isCompleted, color: Theme.Color.textSecondary)
                        HStack(spacing: 6) {
                            Text("\(workout.plannedExercises.count) exercises")
                            Text("·")
                            Text("~\(workout.estimatedKcal) kcal")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        if let start = workout.anchor.sortDate {
                            Text(start, style: .time)
                                .font(.caption2)
                                .foregroundStyle(Theme.Color.textSecondary.opacity(0.7))
                        }
                    }

                    Spacer()

                    if workout.isCompleted {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Color.success)
                                .font(.title2)
                            if let actual = workout.actualKcal {
                                Text("\(actual) kcal")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    } else {
                        Button("Start") { showWorkoutDetail = workout }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Theme.Color.accent)
                    }
                }

                // Mini exercise preview strip (not completed)
                if !workout.isCompleted && !workout.plannedExercises.isEmpty {
                    Divider()
                        .padding(.top, 10)
                        .padding(.horizontal, -16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(workout.plannedExercises.prefix(5), id: \.exerciseID) { ex in
                                Text(ex.exerciseID.split(separator: "_").first.map(String.init)?.capitalized ?? ex.exerciseID)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.Color.surface)
                                    .clipShape(Capsule())
                            }
                            if workout.plannedExercises.count > 5 {
                                Text("+\(workout.plannedExercises.count - 5) more")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .padding(.horizontal, 6)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
    }

    private var emptyWorkoutCard: some View {
        Button { showGeneratePlan = true } label: {
            LEOCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.Color.accent.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workout today")
                            .font(Theme.Typography.body.bold())
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Tap to generate a personalised plan")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meal section

    private func mealSection(_ meals: [MealItem], vm: FitnessHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Meals")
                    .font(Theme.Typography.body.bold())
                    .padding(.horizontal, 4)
                Spacer()
                let logged = meals.filter(\.isCompleted).count
                Text("\(logged)/\(meals.count) logged")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.horizontal, 4)
            }

            ForEach(meals) { meal in
                LEOCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(meal.isCompleted ? Theme.Color.success.opacity(0.12) : Theme.Color.accent.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(meal.isCompleted ? Theme.Color.success : Theme.Color.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title)
                                .font(Theme.Typography.body)
                                .strikethrough(meal.isCompleted, color: Theme.Color.textSecondary)
                            Text("\(meal.displayKcal) kcal · \(meal.servings.formatted(.number.precision(.fractionLength(1)))) serving(s)")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        Spacer()
                        if meal.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Color.success)
                        } else {
                            Button("Log") { showMealDetail = meal }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Week strip card (7-day grid + adherence ring)

    private func weekStripCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week")
                            .font(Theme.Typography.body.bold())
                        let done = vm.weekWorkouts.filter(\.isCompleted).count
                        let total = vm.weekWorkouts.count
                        Text(total == 0 ? "No sessions planned" : "\(done) of \(total) sessions done")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Spacer()
                    // Adherence ring
                    ZStack {
                        Circle()
                            .stroke(Theme.Color.surface, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: vm.weekAdherenceRatio)
                            .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(vm.weekAdherenceRatio * 100))%")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(width: 48, height: 48)
                }

                // 7-day strip
                HStack(spacing: 0) {
                    ForEach(vm.weekDays, id: \.self) { day in
                        WeekDayCell(
                            day: day,
                            workouts: vm.workouts(on: day)
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Measurements preview

    private func measurementsPreviewCard(vm: FitnessHomeViewModel) -> some View {
        Button { showMeasurements = true } label: {
            LEOCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.Color.accent.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "scalemass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body measurements")
                            .font(Theme.Typography.body.bold())
                            .foregroundStyle(Theme.Color.textPrimary)
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
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                        } else {
                            Text("No measurements yet — tap to add")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Week day cell

private struct WeekDayCell: View {
    let day: Date
    let workouts: [WorkoutItem]

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isPast: Bool { day < Calendar.current.startOfDay(for: .now) }
    private var dayLabel: String { day.formatted(.dateTime.weekday(.narrow)) }
    private var dayNum: String { day.formatted(.dateTime.day()) }

    private var status: DayStatus {
        if workouts.isEmpty { return .rest }
        let allDone = workouts.allSatisfy(\.isCompleted)
        let anyDone = workouts.contains(where: \.isCompleted)
        if allDone { return .completed }
        if anyDone { return .partial }
        return isPast ? .missed : .planned
    }

    enum DayStatus { case rest, planned, completed, partial, missed }

    var body: some View {
        VStack(spacing: 5) {
            Text(dayLabel)
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.Color.accent : Theme.Color.textSecondary)

            ZStack {
                switch status {
                case .completed:
                    Circle().fill(Theme.Color.accent)
                case .partial:
                    Circle().fill(Theme.Color.warning)
                case .missed:
                    Circle().fill(Theme.Color.danger.opacity(0.7))
                case .planned:
                    Circle().strokeBorder(Theme.Color.accent, lineWidth: 1.5)
                case .rest:
                    Circle().fill(Color.clear)
                }

                if status != .rest {
                    Image(systemName: status == .completed ? "checkmark" : "figure.strengthtraining.traditional")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(status == .planned ? Theme.Color.accent : .white)
                }
            }
            .frame(width: 30, height: 30)

            // Dot if today
            Circle()
                .fill(isToday ? Theme.Color.accent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add measurement sheet

private struct AddMeasurementSheet: View {
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
                #if os(macOS)
                Section { Button("Cancel") { dismiss() } }
                #endif
                Section("Weight (kg)") {
                    TextField("e.g. 75.5", text: $weightText)
                        .keyboardType(.decimalPad)
                }
                Section("Body fat % (optional)") {
                    TextField("e.g. 18", text: $fatText)
                        .keyboardType(.decimalPad)
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
    FitnessHomeView()
        .environment(AppEnvironment(useInMemory: true))
}
