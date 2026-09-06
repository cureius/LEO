import exercisesData from './data/exercises.json'

/**
 * Port of LEO/Domain/Fitness/Exercise.swift's MuscleGroup/Equipment/
 * ExerciseDifficulty/Exercise types, backed by the SAME bundled data file
 * native ships (LEO/Resources/Fitness/exercises.json, copied verbatim to
 * ./data/exercises.json) — both platforms generate workout plans from
 * identical exercise data now, not two separately hand-maintained lists.
 */
export type MuscleGroup =
  | 'chest' | 'back' | 'shoulders' | 'biceps' | 'triceps' | 'forearms'
  | 'quads' | 'hamstrings' | 'glutes' | 'calves' | 'core' | 'fullBody' | 'cardio'

export type Equipment = 'bodyweight' | 'dumbbells' | 'barbell' | 'machine' | 'cable' | 'band' | 'kettlebell' | 'pullUpBar'

export type ExerciseDifficulty = 'beginner' | 'intermediate' | 'advanced'

export type Exercise = {
  id: string
  name: string
  muscleGroups: MuscleGroup[]
  equipment: Equipment[]
  metValue: number
  defaultSets: number
  defaultReps: number
  defaultDurationMin: number | null
  difficulty: ExerciseDifficulty
  instructions: string
  videoSearchQuery: string
}

export const EXERCISE_CATALOG: Exercise[] = exercisesData as Exercise[]

/**
 * A small representative recipe catalog — NOT a port of the real Swift
 * recipes.json (2700+ lines; propose_meal_plan's richness was out of scope
 * for this pass, only propose_workout_plan's was). Enough for
 * propose_meal_plan to generate a real, usable diff.
 */
export const RECIPE_CATALOG = [
  { id: 'r001', name: 'Chicken & Rice Bowl', kcal: 550 },
  { id: 'r004', name: 'Protein Smoothie', kcal: 380 },
  { id: 'r010', name: 'Paneer & Roti', kcal: 620 },
  { id: 'r014', name: 'Egg & Oats', kcal: 420 },
] as const
