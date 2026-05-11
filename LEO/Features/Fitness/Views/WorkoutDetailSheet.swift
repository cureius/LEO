import SwiftUI

struct WorkoutDetailSheet: View {
    let workout: WorkoutItem
    let onComplete: (WorkoutItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [ExerciseRowState] = []
    @State private var showLogActuals = false
    @State private var isLoading = true

    struct ExerciseRowState: Identifiable {
        let id: String
        var exercise: Exercise?
        let planned: PlannedExercise
        var isChecked: Bool = false
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    exerciseList
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadExercises() }
    }

    private var exerciseList: some View {
        List {
            if let notes = workout.notes, !notes.isEmpty {
                Section {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Section("Exercises") {
                ForEach($exercises) { $row in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            row.isChecked.toggle()
                        } label: {
                            Image(systemName: row.isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(row.isChecked ? Theme.Color.accent : Theme.Color.textSecondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.exercise?.name ?? "Exercise")
                                .font(Theme.Typography.body)
                                .strikethrough(row.isChecked)
                            Text("\(row.planned.sets) sets × \(row.planned.reps) reps" + (row.planned.weightKg.map { " @ \($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "") + (row.planned.durationMin.map { " · \($0)min" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                            if let ex = row.exercise, !ex.instructions.isEmpty {
                                Text(ex.instructions.prefix(80) + (ex.instructions.count > 80 ? "…" : ""))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Color.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Text("Est. \(workout.estimatedKcal) kcal burned")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Section {
                Button {
                    var completed = workout
                    completed.completion = .completed(at: .now)
                    completed.actualKcal = workout.estimatedKcal
                    onComplete(completed)
                    dismiss()
                } label: {
                    Label("Mark complete (\(workout.estimatedKcal) kcal)", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if workout.isCompleted {
                    Text("Already completed")
                        .foregroundStyle(Theme.Color.success)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func loadExercises() async {
        let rows = await workout.plannedExercises.asyncMap { planned in
            let ex = await FitnessLibrary.shared.exercise(id: planned.exerciseID)
            return ExerciseRowState(id: planned.exerciseID, exercise: ex, planned: planned)
        }
        exercises = rows
        isLoading = false
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self { results.append(await transform(element)) }
        return results
    }
}

extension WorkoutItem: Swift.Identifiable {}
