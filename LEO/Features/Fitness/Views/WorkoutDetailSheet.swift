import SwiftUI

// MARK: - Session state models

struct ExerciseSessionState: Identifiable {
    let id: String  // exerciseID
    var exercise: Exercise?
    let planned: PlannedExercise
    var sets: [SetState]

    struct SetState: Identifiable {
        let id: Int           // 1-based set number
        var repsActual: Int?
        var weightKg: Double?
        var isDone: Bool = false
        let repsPlanned: Int
        let weightPlanned: Double?
    }

    init(planned: PlannedExercise, exercise: Exercise?) {
        self.id = planned.exerciseID
        self.planned = planned
        self.exercise = exercise
        let count = max(1, planned.sets)
        self.sets = (1...count).map { i in
            SetState(
                id: i,
                repsActual: planned.reps,
                weightKg: planned.weightKg,
                isDone: false,
                repsPlanned: planned.reps,
                weightPlanned: planned.weightKg
            )
        }
    }

    var completedSetsCount: Int { sets.filter(\.isDone).count }
    var isFullyDone: Bool { sets.allSatisfy(\.isDone) }
}

// MARK: - Main sheet

struct WorkoutDetailSheet: View {
    let workout: WorkoutItem
    let onComplete: (WorkoutItem) -> Void
    var onUncomplete: ((WorkoutItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [ExerciseSessionState] = []
    @State private var isLoading = true
    @State private var elapsedSeconds = 0
    @State private var restSecondsLeft: Int? = nil

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var totalSets: Int    { exercises.flatMap(\.sets).count }
    private var doneSets: Int     { exercises.flatMap(\.sets).filter(\.isDone).count }
    private var canFinish: Bool   { doneSets > 0 }
    private var allDone: Bool     { doneSets == totalSets && totalSets > 0 }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    sessionBody
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if workout.isCompleted {
                        Button("Undo") {
                            var reset = workout
                            reset.completion = .open
                            onUncomplete?(reset)
                            dismiss()
                        }
                        .foregroundStyle(Theme.Color.warning)
                    } else {
                        Button(allDone ? "Finish" : "Finish early") {
                            finishWorkout()
                        }
                        .bold()
                        .disabled(!canFinish)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadExercises() }
        .onReceive(clock) { _ in
            elapsedSeconds += 1
            if let r = restSecondsLeft {
                restSecondsLeft = r > 0 ? r - 1 : nil
            }
        }
    }

    // MARK: - Session body

    private var sessionBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionHeader
                if let rest = restSecondsLeft {
                    restTimerBanner(rest)
                }
                ForEach($exercises) { $ex in
                    ExerciseCard(state: $ex, onSetDone: { startRest() })
                }
                finishButton
            }
            .padding(.vertical, 16)
        }
        .background(Theme.Color.background)
    }

    // MARK: - Session header

    private var sessionHeader: some View {
        HStack(spacing: 0) {
            statCell(
                value: formatClock(elapsedSeconds),
                label: "Elapsed",
                color: Theme.Color.accent,
                mono: true
            )
            dividerLine
            statCell(
                value: "\(doneSets)/\(totalSets)",
                label: "Sets",
                color: Theme.Color.textPrimary,
                mono: false
            )
            dividerLine
            statCell(
                value: "~\(workout.estimatedKcal)",
                label: "kcal",
                color: Theme.Color.warning,
                mono: false
            )
        }
        .padding(.vertical, 14)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private var dividerLine: some View {
        Rectangle().fill(Theme.Color.divider).frame(width: 1, height: 44)
    }

    private func statCell(value: String, label: String, color: Color, mono: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(mono
                      ? .system(size: 22, weight: .bold, design: .monospaced)
                      : .system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rest timer banner

    private func restTimerBanner(_ seconds: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(seconds) / 90)
                    .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Rest")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(formatClock(seconds))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Color.accent)
            }
            Spacer()
            Button("Skip") {
                withAnimation { restSecondsLeft = nil }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Color.surface)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.Color.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Finish button

    private var finishButton: some View {
        Button(action: finishWorkout) {
            HStack(spacing: 8) {
                Image(systemName: allDone ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                Text(allDone ? "Finish Workout" : "Finish Early (\(doneSets)/\(totalSets) sets)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canFinish
                        ? (allDone ? Theme.Color.success : Theme.Color.accent)
                        : Theme.Color.surface)
            .foregroundStyle(canFinish ? .white : Theme.Color.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!canFinish)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: allDone)
    }

    // MARK: - Actions

    private func startRest(seconds: Int = 90) {
        withAnimation { restSecondsLeft = seconds }
    }

    private func finishWorkout() {
        var completed = workout
        completed.completion = .completed(at: .now)

        // Write actual per-exercise logged data
        completed.actualExercises = exercises.compactMap { ex -> LoggedExercise? in
            let done = ex.sets.filter(\.isDone)
            guard !done.isEmpty else { return nil }
            let weights = done.compactMap(\.weightKg)
            let avgWeight = weights.isEmpty ? ex.planned.weightKg
                : weights.reduce(0, +) / Double(weights.count)
            let avgReps = done.compactMap(\.repsActual).reduce(0, +) / done.count
            return LoggedExercise(
                exerciseID: ex.id,
                setsCompleted: done.count,
                repsCompleted: avgReps,
                weightKg: avgWeight
            )
        }

        // Scale kcal by completion ratio
        let ratio = totalSets > 0 ? Double(doneSets) / Double(totalSets) : 1
        completed.actualKcal = Int(Double(workout.estimatedKcal) * ratio)

        onComplete(completed)
        dismiss()
    }

    // MARK: - Load

    private func loadExercises() async {
        let rows = await workout.plannedExercises.asyncMap { planned in
            let ex = await FitnessLibrary.shared.exercise(id: planned.exerciseID)
            return ExerciseSessionState(planned: planned, exercise: ex)
        }
        exercises = rows
        isLoading = false
    }

    // MARK: - Helpers

    private func formatClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Exercise card

private struct ExerciseCard: View {
    @Binding var state: ExerciseSessionState
    let onSetDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Completion ring
                ZStack {
                    Circle()
                        .stroke(Theme.Color.surface, lineWidth: 3)
                        .frame(width: 36, height: 36)
                    let ratio = state.sets.isEmpty ? 0
                        : CGFloat(state.completedSetsCount) / CGFloat(state.sets.count)
                    Circle()
                        .trim(from: 0, to: ratio)
                        .stroke(
                            state.isFullyDone ? Theme.Color.success : Theme.Color.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                        .animation(.spring(duration: 0.4), value: ratio)
                    if state.isFullyDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Color.success)
                    } else {
                        Text("\(state.completedSetsCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Color.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.exercise?.name ?? "Exercise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.isFullyDone ? Theme.Color.textSecondary : Theme.Color.textPrimary)

                    if let ex = state.exercise, !ex.muscleGroups.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(ex.muscleGroups.prefix(3), id: \.self) { muscle in
                                Text(muscle.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.Color.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.Color.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Text("\(state.planned.sets) × \(state.planned.reps)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Column headers
            HStack {
                Text("SET")
                    .frame(width: 38, alignment: .leading)
                Spacer()
                Text("REPS")
                    .frame(width: 68, alignment: .center)
                Text("KG")
                    .frame(width: 68, alignment: .center)
                Spacer().frame(width: 40)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.Color.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.Color.surface.opacity(0.6))

            // Set rows
            ForEach($state.sets) { $set in
                Divider().padding(.leading, 16)
                SetRow(set: $set, onDone: onSetDone)
            }

            // Instructions hint
            if let instructions = state.exercise?.instructions, !instructions.isEmpty {
                Divider()
                Text(instructions.prefix(120) + (instructions.count > 120 ? "…" : ""))
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    state.isFullyDone ? Theme.Color.success.opacity(0.4) : Theme.Color.divider,
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Set row

private struct SetRow: View {
    @Binding var set: ExerciseSessionState.SetState
    let onDone: () -> Void

    @State private var repsText: String
    @State private var weightText: String

    init(set: Binding<ExerciseSessionState.SetState>, onDone: @escaping () -> Void) {
        self._set = set
        self.onDone = onDone
        let s = set.wrappedValue
        self._repsText  = State(initialValue: s.repsActual.map(String.init) ?? String(s.repsPlanned))
        self._weightText = State(initialValue: s.weightKg.map { String(format: "%.1f", $0) }
                                    ?? s.weightPlanned.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set label
            Text("Set \(set.id)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(set.isDone ? Theme.Color.success : Theme.Color.textSecondary)
                .frame(width: 38, alignment: .leading)

            Spacer()

            // Reps field
            inputField(text: $repsText, placeholder: "\(set.repsPlanned)", keyboard: .numberPad) {
                set.repsActual = Int(repsText)
            }
            .frame(width: 68)

            // Weight field
            inputField(text: $weightText, placeholder: "—", keyboard: .decimalPad) {
                set.weightKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
            }
            .frame(width: 68)

            // Done toggle — tap to check, tap again or long-press to undo
            Button {
                let wasChecked = set.isDone
                withAnimation(.spring(duration: 0.3)) { set.isDone.toggle() }
                if !wasChecked { onDone() }   // only start rest on completion, not on undo
            } label: {
                ZStack {
                    Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundStyle(set.isDone ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.35))
                    // Subtle undo badge when done
                    if set.isDone {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Color.success.opacity(0.7))
                            .offset(x: 10, y: -10)
                    }
                }
                .scaleEffect(set.isDone ? 1.05 : 1)
                .animation(.spring(duration: 0.3), value: set.isDone)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .contextMenu {
                if set.isDone {
                    Button("Mark as incomplete", systemImage: "arrow.uturn.backward.circle") {
                        withAnimation(.spring(duration: 0.3)) { set.isDone = false }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(set.isDone ? Theme.Color.success.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: set.isDone)
    }

    private func inputField(
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType,
        onChange: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .semibold))
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(set.isDone ? Theme.Color.success.opacity(0.08) : Theme.Color.background)
            )
            .onChange(of: text.wrappedValue) { _, _ in onChange() }
    }
}

// MARK: - Helpers

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self { results.append(await transform(element)) }
        return results
    }
}

extension WorkoutItem: Swift.Identifiable {}
