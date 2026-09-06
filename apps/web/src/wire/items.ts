import { refDateToJSDate, jsDateToRefDate } from './dates'
import { decodeAnchor, encodeAnchor, decodeCompletion, encodeCompletion } from './anchor'
import { decodeBase64Json, encodeJsonBase64 } from './base64'
import type {
  AlarmSound,
  DomainItem,
  ExternalRef,
  ItemKind,
  LoggedExercise,
  Macros,
  PlannedExercise,
  Tag,
} from '@/domain/types'

// ---------------------------------------------------------------------------
// Raw wire shapes — field names and structure exactly as they appear in the
// JSON produced by Swift's SnapshotDTO.swift (LEO/Persistence/Backup/SnapshotDTO.swift).
// All dates here are Cocoa reference-date floats (see dates.ts); anchorB64/
// completionB64 are base64 sub-blobs (see anchor.ts).
// ---------------------------------------------------------------------------

type WireTag = { id: string; name: string; colorRaw: string }

type WireExternalRef = { source: 'eventKit'; identifier: string; lastSeen: number }

type WireItemBase = {
  id: string
  title: string
  notes?: string
  createdAt: number
  updatedAt: number
  importanceRaw: number
  anchorB64: string
  completionB64: string
}

type WireTask = WireItemBase & {
  tags: WireTag[]
  deadline?: number
  estimatedDurationSeconds?: number
  rruleRaw?: string
}

type WireEvent = WireItemBase & {
  tags: WireTag[]
  location?: string
  attendees: string[]
  externalRef?: WireExternalRef
  rruleRaw?: string
}

type WireReminder = WireItemBase & {
  tags: WireTag[]
  leadTime?: number
  externalRef?: WireExternalRef
  rruleRaw?: string
}

type WireAlarm = WireItemBase & {
  tags: WireTag[]
  soundProfileRaw: string
  escalates: boolean
  rruleRaw?: string
}

// No `tags` field — confirmed absent from SnapshotHabitInstance.
type WireHabitInstance = WireItemBase & {
  habitID: string
  targetDurationSeconds?: number
}

type WireWorkout = WireItemBase & {
  tags: WireTag[]
  plannedExercisesB64: string
  estimatedKcal: number
  actualKcal?: number
  actualExercisesB64?: string
  healthKitWorkoutID?: string
}

type WireMeal = WireItemBase & {
  tags: WireTag[]
  recipeID: string
  servings: number
  targetKcal: number
  actualKcal?: number
  loggedMacrosB64?: string
  healthKitCorrelationID?: string
}

// ---------------------------------------------------------------------------
// Shared field mapping
// ---------------------------------------------------------------------------

function decodeBaseFields(w: WireItemBase) {
  return {
    id: w.id,
    title: w.title,
    notes: w.notes,
    createdAt: refDateToJSDate(w.createdAt),
    updatedAt: refDateToJSDate(w.updatedAt),
    importance: w.importanceRaw,
    anchor: decodeAnchor(w.anchorB64),
    completion: decodeCompletion(w.completionB64),
  }
}

function encodeBaseFields(item: {
  id: string
  title: string
  notes?: string
  createdAt: Date
  updatedAt: Date
  importance: number
  anchor: DomainItem['anchor']
  completion: DomainItem['completion']
}): WireItemBase {
  return {
    id: item.id,
    title: item.title,
    notes: item.notes,
    createdAt: jsDateToRefDate(item.createdAt),
    updatedAt: jsDateToRefDate(item.updatedAt),
    importanceRaw: item.importance,
    anchorB64: encodeAnchor(item.anchor),
    completionB64: encodeCompletion(item.completion),
  }
}

function decodeTags(tags: WireTag[]): Tag[] {
  return tags.map((t) => ({ id: t.id, name: t.name, colorRaw: t.colorRaw as Tag['colorRaw'] }))
}

function encodeTags(tags: Tag[]): WireTag[] {
  return tags.map((t) => ({ id: t.id, name: t.name, colorRaw: t.colorRaw }))
}

function decodeExternalRef(ref: WireExternalRef | undefined): ExternalRef | undefined {
  if (!ref) return undefined
  return { source: ref.source, identifier: ref.identifier, lastSeen: refDateToJSDate(ref.lastSeen) }
}

function encodeExternalRef(ref: ExternalRef | undefined): WireExternalRef | undefined {
  if (!ref) return undefined
  return { source: ref.source, identifier: ref.identifier, lastSeen: jsDateToRefDate(ref.lastSeen) }
}

// ---------------------------------------------------------------------------
// Per-kind decode
// ---------------------------------------------------------------------------

function decodeTask(w: WireTask): DomainItem {
  return {
    kind: 'task',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    deadline: w.deadline !== undefined ? refDateToJSDate(w.deadline) : undefined,
    estimatedDurationSeconds: w.estimatedDurationSeconds,
    rruleRaw: w.rruleRaw,
  }
}

function decodeEvent(w: WireEvent): DomainItem {
  return {
    kind: 'event',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    location: w.location,
    attendees: w.attendees,
    externalRef: decodeExternalRef(w.externalRef),
    rruleRaw: w.rruleRaw,
  }
}

function decodeReminder(w: WireReminder): DomainItem {
  return {
    kind: 'reminder',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    leadTime: w.leadTime,
    externalRef: decodeExternalRef(w.externalRef),
    rruleRaw: w.rruleRaw,
  }
}

function decodeAlarm(w: WireAlarm): DomainItem {
  return {
    kind: 'alarm',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    soundProfileRaw: w.soundProfileRaw as AlarmSound,
    escalates: w.escalates,
    rruleRaw: w.rruleRaw,
  }
}

function decodeHabitInstance(w: WireHabitInstance): DomainItem {
  return {
    kind: 'habitInstance',
    ...decodeBaseFields(w),
    habitID: w.habitID,
    targetDurationSeconds: w.targetDurationSeconds,
  }
}

function decodeWorkout(w: WireWorkout): DomainItem {
  return {
    kind: 'workout',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    plannedExercises: decodeBase64Json<PlannedExercise[]>(w.plannedExercisesB64),
    estimatedKcal: w.estimatedKcal,
    actualKcal: w.actualKcal,
    actualExercises: w.actualExercisesB64 ? decodeBase64Json<LoggedExercise[]>(w.actualExercisesB64) : undefined,
    healthKitWorkoutID: w.healthKitWorkoutID,
  }
}

function decodeMeal(w: WireMeal): DomainItem {
  return {
    kind: 'meal',
    ...decodeBaseFields(w),
    tags: decodeTags(w.tags),
    recipeID: w.recipeID,
    servings: w.servings,
    targetKcal: w.targetKcal,
    actualKcal: w.actualKcal,
    loggedMacros: w.loggedMacrosB64 ? decodeBase64Json<Macros>(w.loggedMacrosB64) : undefined,
    healthKitCorrelationID: w.healthKitCorrelationID,
  }
}

/**
 * Decode one `items` row's `data` column into a DomainItem.
 *
 * `data` is declared `jsonb` in the schema but the Swift client always
 * writes it as a pre-serialized JSON *string* (`JSONEncoder().encode(dto)`
 * assigned directly) — confirmed via a real REST `select()`, which returns
 * `data` as a string. Supabase Realtime's `postgres_changes` payload for the
 * same jsonb column, however, arrives already parsed into an object — caught
 * empirically when a REST-sourced row decoded fine but the identical row
 * decoded via realtime silently failed. Accept either shape here rather than
 * assuming one, so the two delivery paths don't need different callers.
 *
 * Returns `undefined` rather than throwing on an unrecognized `kind` or a
 * malformed payload — the cloud DB has ~26 rows from an old, since-fixed
 * native-app bug (EventKit mirrors pushed before an exclusion fix landed);
 * callers should skip-and-warn on `undefined`, never let one bad row take
 * down the whole sync.
 */
export function decodeItemRow(kind: string, data: string | Record<string, unknown>): DomainItem | undefined {
  try {
    const raw = typeof data === 'string' ? JSON.parse(data) : data
    switch (kind as ItemKind) {
      case 'task':
        return decodeTask(raw as WireTask)
      case 'event':
        return decodeEvent(raw as WireEvent)
      case 'reminder':
        return decodeReminder(raw as WireReminder)
      case 'alarm':
        return decodeAlarm(raw as WireAlarm)
      case 'habitInstance':
        return decodeHabitInstance(raw as WireHabitInstance)
      case 'workout':
        return decodeWorkout(raw as WireWorkout)
      case 'meal':
        return decodeMeal(raw as WireMeal)
      default:
        return undefined
    }
  } catch {
    return undefined
  }
}

// ---------------------------------------------------------------------------
// Per-kind encode — used by the write path (Phase 2)
// ---------------------------------------------------------------------------

export function encodeItemPayload(item: DomainItem): { kind: ItemKind; json: string } {
  const base = encodeBaseFields(item)
  switch (item.kind) {
    case 'task':
      return {
        kind: 'task',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          deadline: item.deadline ? jsDateToRefDate(item.deadline) : undefined,
          estimatedDurationSeconds: item.estimatedDurationSeconds,
          rruleRaw: item.rruleRaw,
        } satisfies WireTask),
      }
    case 'event':
      return {
        kind: 'event',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          location: item.location,
          attendees: item.attendees,
          externalRef: encodeExternalRef(item.externalRef),
          rruleRaw: item.rruleRaw,
        } satisfies WireEvent),
      }
    case 'reminder':
      return {
        kind: 'reminder',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          leadTime: item.leadTime,
          externalRef: encodeExternalRef(item.externalRef),
          rruleRaw: item.rruleRaw,
        } satisfies WireReminder),
      }
    case 'alarm':
      return {
        kind: 'alarm',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          soundProfileRaw: item.soundProfileRaw,
          escalates: item.escalates,
          rruleRaw: item.rruleRaw,
        } satisfies WireAlarm),
      }
    case 'habitInstance':
      return {
        kind: 'habitInstance',
        json: JSON.stringify({
          ...base,
          habitID: item.habitID,
          targetDurationSeconds: item.targetDurationSeconds,
        } satisfies WireHabitInstance),
      }
    case 'workout':
      return {
        kind: 'workout',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          plannedExercisesB64: encodeJsonBase64(item.plannedExercises),
          estimatedKcal: item.estimatedKcal,
          actualKcal: item.actualKcal,
          actualExercisesB64: item.actualExercises ? encodeJsonBase64(item.actualExercises) : undefined,
          healthKitWorkoutID: item.healthKitWorkoutID,
        } satisfies WireWorkout),
      }
    case 'meal':
      return {
        kind: 'meal',
        json: JSON.stringify({
          ...base,
          tags: encodeTags(item.tags),
          recipeID: item.recipeID,
          servings: item.servings,
          targetKcal: item.targetKcal,
          actualKcal: item.actualKcal,
          loggedMacrosB64: item.loggedMacros ? encodeJsonBase64(item.loggedMacros) : undefined,
          healthKitCorrelationID: item.healthKitCorrelationID,
        } satisfies WireMeal),
      }
  }
}

/**
 * True for an event/reminder mirrored from the native EventKit integration.
 * The web client must never push these — each device mints its own random
 * `id` for the same calendar event and de-duplicates on `externalRef`
 * instead, so syncing them on `id` would return the event to its origin
 * device as a second, distinct copy. This mirrors a real bug fixed in the
 * native Swift app this session (LEO/Sync/SupabaseSync.swift's
 * isExternallyManagedItem) — see also domain/types.ts.
 */
export function isExternallyManaged(item: DomainItem): boolean {
  if (item.kind !== 'event' && item.kind !== 'reminder') return false
  return item.externalRef?.source === 'eventKit'
}
