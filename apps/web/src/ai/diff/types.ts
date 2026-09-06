/**
 * Plain JSON, no base64/refdate — confirmed from ProposeTools.swift and
 * DiffReviewSheet.swift. The AI never writes directly, ever: propose tools
 * only ever build one of these for user review; applying an accepted diff
 * goes through the same addItem/updateItem/deleteItem mutations any manual
 * edit uses (applyDiff.ts).
 */
export type DiffPayload = { changes: DiffChange[]; rationale: string }

export type DiffChange = {
  itemID: string
  kind: 'add' | 'update' | 'delete'
  field: string
  newValue: string
  /** Only present when kind === 'add'. */
  pendingItem?: PendingNewItem
}

/**
 * `type` is wider than task/event/reminder — confirmed from
 * ProposeWorkoutPlanTool.swift/ProposeMealPlanTool.swift, which emit
 * "workout"/"meal" through this exact same shape, plus the real `kind`
 * column values in supabase/migrations/0001_init.sql.
 */
export type PendingNewItem = {
  title: string
  type: 'task' | 'event' | 'reminder' | 'workout' | 'meal'
  start?: string
  end?: string
  notes?: string
  /** Structured exercise data for `type === 'workout'` — mirrors the fix to
   *  PendingNewItem.swift's equivalent: without this, propose_workout_plan
   *  could only carry exercises as a flattened notes string, and the applied
   *  item ended up with an empty plannedExercises array. */
  exercises?: { name: string; sets: number; reps: number; weightKg?: number }[]
  estimatedKcal?: number
}
