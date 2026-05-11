import Foundation

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - Domain ↔ UserBodyProfile

extension UserBodyProfile {
    static func from(_ stored: StoredBodyProfile) -> UserBodyProfile {
        let allergies = (try? jsonDecoder.decode([String].self, from: stored.allergiesData)) ?? []
        let intolerances = (try? jsonDecoder.decode([String].self, from: stored.intolerancesData)) ?? []
        let flagRaws = (try? jsonDecoder.decode([String].self, from: stored.medicalFlagsData)) ?? []
        let medicalFlags = flagRaws.compactMap { MedicalFlag(rawValue: $0) }
        return UserBodyProfile(
            heightCm: stored.heightCm,
            weightKg: stored.weightKg,
            sex: BiologicalSex(rawValue: stored.sexRaw) ?? .other,
            birthDate: stored.birthDate,
            bodyFatPct: stored.bodyFatPct,
            activityLevel: ActivityLevel(rawValue: stored.activityLevelRaw) ?? .moderate,
            goalWeightKg: stored.goalWeightKg,
            goalPhysique: GoalPhysique(rawValue: stored.goalPhysiqueRaw) ?? .maintain,
            targetDate: stored.targetDate,
            dietType: DietType(rawValue: stored.dietTypeRaw) ?? .omnivore,
            allergies: allergies,
            intolerances: intolerances,
            medicalFlags: medicalFlags,
            unitPreference: UnitPreference(rawValue: stored.unitPreferenceRaw) ?? .metric
        )
    }
}

extension StoredBodyProfile {
    convenience init(from profile: UserBodyProfile) {
        let allergiesData = (try? jsonEncoder.encode(profile.allergies)) ?? "[]".data(using: .utf8)!
        let intolerancesData = (try? jsonEncoder.encode(profile.intolerances)) ?? "[]".data(using: .utf8)!
        let flagRaws = profile.medicalFlags.map(\.rawValue)
        let medicalFlagsData = (try? jsonEncoder.encode(flagRaws)) ?? "[]".data(using: .utf8)!
        self.init(
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
            sexRaw: profile.sex.rawValue,
            birthDate: profile.birthDate,
            bodyFatPct: profile.bodyFatPct,
            activityLevelRaw: profile.activityLevel.rawValue,
            goalWeightKg: profile.goalWeightKg,
            goalPhysiqueRaw: profile.goalPhysique.rawValue,
            targetDate: profile.targetDate,
            dietTypeRaw: profile.dietType.rawValue,
            allergiesData: allergiesData,
            intolerancesData: intolerancesData,
            medicalFlagsData: medicalFlagsData,
            unitPreferenceRaw: profile.unitPreference.rawValue
        )
    }
}

// MARK: - Domain ↔ BodyMeasurement

extension BodyMeasurement {
    static func from(_ stored: StoredMeasurement) -> BodyMeasurement {
        BodyMeasurement(
            id: stored.id,
            date: stored.date,
            weightKg: stored.weightKg,
            bodyFatPct: stored.bodyFatPct,
            source: MeasurementSource(rawValue: stored.sourceRaw) ?? .manual
        )
    }
}

extension StoredMeasurement {
    convenience init(from m: BodyMeasurement) {
        self.init(
            id: m.id,
            date: m.date,
            weightKg: m.weightKg,
            bodyFatPct: m.bodyFatPct,
            sourceRaw: m.source.rawValue
        )
    }
}

// MARK: - Domain ↔ WorkoutItem

extension WorkoutItem {
    static func from(_ stored: StoredWorkoutItem) throws -> WorkoutItem {
        let planned = (try? jsonDecoder.decode([PlannedExercise].self, from: stored.plannedExercisesData)) ?? []
        let actual = stored.actualExercisesData.flatMap { try? jsonDecoder.decode([LoggedExercise].self, from: $0) }
        return WorkoutItem(
            id: stored.id,
            title: stored.title,
            notes: stored.notes,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            plannedExercises: planned,
            estimatedKcal: stored.estimatedKcal,
            actualKcal: stored.actualKcal,
            actualExercises: actual,
            healthKitWorkoutID: stored.healthKitWorkoutID
        )
    }
}

extension StoredWorkoutItem {
    convenience init(from item: WorkoutItem) throws {
        let plannedData = (try? jsonEncoder.encode(item.plannedExercises)) ?? "[]".data(using: .utf8)!
        let actualData = item.actualExercises.flatMap { try? jsonEncoder.encode($0) }
        try self.init(
            id: item.id,
            title: item.title,
            notes: item.notes,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            plannedExercisesData: plannedData,
            estimatedKcal: item.estimatedKcal,
            actualKcal: item.actualKcal,
            actualExercisesData: actualData,
            healthKitWorkoutID: item.healthKitWorkoutID
        )
    }
}

// MARK: - Domain ↔ MealItem

extension MealItem {
    static func from(_ stored: StoredMealItem) throws -> MealItem {
        let macros = stored.loggedMacrosData.flatMap { try? jsonDecoder.decode(Macros.self, from: $0) }
        return MealItem(
            id: stored.id,
            title: stored.title,
            notes: stored.notes,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            importance: Importance(rawValue: stored.importanceRaw) ?? .normal,
            anchor: try Anchor.decoded(from: stored.anchorData),
            completion: try Completion.decoded(from: stored.completionData),
            tags: stored.tags?.map(Tag.from) ?? [],
            recipeID: stored.recipeID,
            servings: stored.servings,
            targetKcal: stored.targetKcal,
            actualKcal: stored.actualKcal,
            loggedMacros: macros,
            healthKitCorrelationID: stored.healthKitCorrelationID
        )
    }
}

extension StoredMealItem {
    convenience init(from item: MealItem) throws {
        let macrosData = item.loggedMacros.flatMap { try? jsonEncoder.encode($0) }
        try self.init(
            id: item.id,
            title: item.title,
            notes: item.notes,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            importanceRaw: item.importance.rawValue,
            anchorData: item.anchor.encoded(),
            completionData: item.completion.encoded(),
            recipeID: item.recipeID,
            servings: item.servings,
            targetKcal: item.targetKcal,
            actualKcal: item.actualKcal,
            loggedMacrosData: macrosData,
            healthKitCorrelationID: item.healthKitCorrelationID
        )
    }
}
