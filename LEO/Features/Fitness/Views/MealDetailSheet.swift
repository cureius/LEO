import SwiftUI

struct MealDetailSheet: View {
    let meal: MealItem
    let onComplete: (MealItem, Double?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recipe: Recipe?
    @State private var servings: Double
    @State private var isLoading = true

    init(meal: MealItem, onComplete: @escaping (MealItem, Double?) -> Void) {
        self.meal = meal
        self.onComplete = onComplete
        _servings = State(initialValue: meal.servings)
    }

    var adjustedKcal: Int {
        guard let r = recipe else { return meal.targetKcal }
        return Int(Double(r.kcalPerServing) * servings)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle(meal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadRecipe() }
    }

    private var content: some View {
        List {
            // Kcal + servings adjuster
            Section("Serving size") {
                Stepper(
                    value: $servings,
                    in: 0.5...4.0,
                    step: 0.5
                ) {
                    HStack {
                        Text("\(servings.formatted(.number.precision(.fractionLength(1)))) serving(s)")
                        Spacer()
                        Text("\(adjustedKcal) kcal")
                            .foregroundStyle(Theme.Color.accent)
                    }
                }
            }

            if let r = recipe {
                Section("Macros per serving") {
                    LabeledContent("Protein", value: "\(Int(r.macros.proteinG * servings)) g")
                    LabeledContent("Carbs",   value: "\(Int(r.macros.carbG * servings)) g")
                    LabeledContent("Fat",     value: "\(Int(r.macros.fatG * servings)) g")
                }

                Section("Ingredients") {
                    ForEach(r.ingredients, id: \.name) { ing in
                        HStack {
                            Text(ing.name)
                            Spacer()
                            Text(scaled(amount: ing.amount, factor: servings))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                }

                Section("Instructions") {
                    Text(r.instructions)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            if let notes = meal.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }

            Section {
                Button {
                    onComplete(meal, servings)
                    dismiss()
                } label: {
                    Label("Log \(adjustedKcal) kcal eaten", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(meal.isCompleted)

                if meal.isCompleted {
                    Text("Already logged")
                        .foregroundStyle(Theme.Color.success)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func loadRecipe() async {
        recipe = await FitnessLibrary.shared.recipe(id: meal.recipeID)
        isLoading = false
    }

    private func scaled(amount: String, factor: Double) -> String {
        // Simple heuristic: try to find a leading number and scale it
        let pattern = #"^(\d+\.?\d*)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: amount, range: NSRange(amount.startIndex..., in: amount)),
              let numRange = Range(match.range(at: 1), in: amount),
              let num = Double(amount[numRange]) else { return amount }
        let unitRange = Range(match.range(at: 2), in: amount)
        let unit = unitRange.map { String(amount[$0]) } ?? ""
        let scaled = num * factor
        return "\(scaled.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

extension MealItem: Swift.Identifiable {}
