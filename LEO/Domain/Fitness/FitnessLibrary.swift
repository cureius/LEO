import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "fitness-library")

/// Reads the bundled exercises.json and recipes.json, decodes them once, and exposes filtered queries.
/// Singleton actor; call `.shared` everywhere.
actor FitnessLibrary {
    static let shared = FitnessLibrary()

    private var _exercises: [Exercise]?
    private var _recipes: [Recipe]?

    // MARK: - Public API

    func exercises(filter: ExerciseFilter = ExerciseFilter()) async -> [Exercise] {
        let all = await loadExercises()
        guard !filter.isEmpty else { return all }
        return all.filter { filter.matches($0) }
    }

    func exercise(id: String) async -> Exercise? {
        await loadExercises().first { $0.id == id }
    }

    func recipes(filter: RecipeFilter = RecipeFilter()) async -> [Recipe] {
        let all = await loadRecipes()
        return all.filter { filter.matches($0) }
    }

    func recipe(id: String) async -> Recipe? {
        await loadRecipes().first { $0.id == id }
    }

    func validateExerciseIDs(_ ids: [String]) async -> [String] {
        let valid = Set(await loadExercises().map(\.id))
        return ids.filter { !valid.contains($0) }
    }

    func validateRecipeIDs(_ ids: [String]) async -> [String] {
        let valid = Set(await loadRecipes().map(\.id))
        return ids.filter { !valid.contains($0) }
    }

    // MARK: - Private loading

    private func loadExercises() async -> [Exercise] {
        if let cached = _exercises { return cached }
        let loaded = Self.decode([Exercise].self, resource: "exercises", ext: "json") ?? []
        _exercises = loaded
        logger.info("Loaded \(loaded.count) exercises")
        return loaded
    }

    private func loadRecipes() async -> [Recipe] {
        if let cached = _recipes { return cached }
        let loaded = Self.decode([Recipe].self, resource: "recipes", ext: "json") ?? []
        _recipes = loaded
        logger.info("Loaded \(loaded.count) recipes")
        return loaded
    }

    private static func decode<T: Decodable>(_ type: T.Type, resource: String, ext: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Fitness") else {
            logger.error("Missing bundle resource: Fitness/\(resource).\(ext)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Decode error for \(resource): \(error)")
            return nil
        }
    }
}
