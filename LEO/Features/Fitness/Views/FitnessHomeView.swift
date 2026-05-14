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
                // Kcal hero card
                kcalHeroCard(vm: vm)

                // Today's workout
                if let workout = vm.todayWorkouts.first {
                    workoutCard(workout, vm: vm)
                } else {
                    emptyWorkoutCard
                }

                // Today's meals
                if !vm.todayMeals.isEmpty {
                    mealStrip(vm.todayMeals, vm: vm)
                }

                // Weekly adherence
                weeklyAdherenceCard(vm: vm)

                // Measurements chart preview
                measurementsPreviewCard(vm: vm)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Cards

    private func kcalHeroCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Today's Energy")
                        .font(Theme.Typography.body.bold())
                    Spacer()
                    if let p = vm.profile {
                        let target = Int(BodyMath.dailyKcalTarget(profile: p).dailyKcal)
                        Text("Target: \(target) kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }

                HStack(spacing: 24) {
                    VStack {
                        Text("\(vm.kcalIn)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.Color.accent)
                        Text("In")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Text("−")
                        .font(.title2)
                        .foregroundStyle(Theme.Color.textSecondary)
                    VStack {
                        Text("\(vm.kcalOut)")
                            .font(.system(size: 28, weight: .bold))
                        Text("Out")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    Text("=")
                        .font(.title2)
                        .foregroundStyle(Theme.Color.textSecondary)
                    VStack {
                        let delta = vm.kcalDelta
                        Text("\(delta > 0 ? "+" : "")\(delta)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(delta > 200 ? Theme.Color.warning : Theme.Color.success)
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }
        }
    }

    private func workoutCard(_ workout: WorkoutItem, vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title)
                        .font(Theme.Typography.body.bold())
                    Text("\(workout.plannedExercises.count) exercises • ~\(workout.estimatedKcal) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    if let start = workout.anchor.sortDate {
                        Text(start, style: .time)
                            .font(.caption2)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                Spacer()
                if workout.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Color.success)
                        .font(.title2)
                } else {
                    Button("Start") { showWorkoutDetail = workout }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private var emptyWorkoutCard: some View {
        Button {
            showGeneratePlan = true
        } label: {
            LEOCard {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(Theme.Color.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workout today")
                            .font(Theme.Typography.body.bold())
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Tap to generate a personalized plan")
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

    private func mealStrip(_ meals: [MealItem], vm: FitnessHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Meals")
                .font(Theme.Typography.body.bold())
                .padding(.horizontal, 4)

            ForEach(meals) { meal in
                LEOCard {
                    HStack {
                        Image(systemName: "fork.knife")
                            .font(.title3)
                            .foregroundStyle(Theme.Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title)
                                .font(Theme.Typography.body)
                            Text("\(meal.displayKcal) kcal • \(meal.servings.formatted(.number.precision(.fractionLength(1)))) serving(s)")
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                            if let d = meal.anchor.sortDate {
                                Text(d, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
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

    private func weeklyAdherenceCard(vm: FitnessHomeViewModel) -> some View {
        LEOCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly adherence")
                        .font(Theme.Typography.body.bold())
                    let done = vm.weekWorkouts.filter(\.isCompleted).count
                    let total = vm.weekWorkouts.count
                    Text("\(done)/\(total) sessions completed")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Theme.Color.surface, lineWidth: 8)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: vm.weekAdherenceRatio)
                        .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(vm.weekAdherenceRatio * 100))%")
                        .font(.caption.bold())
                }
            }
        }
    }

    private func measurementsPreviewCard(vm: FitnessHomeViewModel) -> some View {
        Button { showMeasurements = true } label: {
            LEOCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body measurements")
                            .font(Theme.Typography.body.bold())
                            .foregroundStyle(Theme.Color.textPrimary)
                        if let latest = vm.measurements.first {
                            Text("\(latest.weightKg.formatted(.number.precision(.fractionLength(1)))) kg · \(latest.date, style: .date)")
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
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add measurement sheet

private struct AddMeasurementSheet: View {
    let onSave: (Double, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var fatText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    TextField("e.g. 75.5 (kg)", text: $weightText)
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
                        guard let kg = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return }
                        let fat = Double(fatText.replacingOccurrences(of: ",", with: "."))
                        onSave(kg, fat)
                        dismiss()
                    }
                    .disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
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
