import { useShallow } from 'zustand/react/shallow'
import { DebugSection, type DebugRecord } from '@/components/debug/DebugSection'
import { selectHabitsArray, selectItemsArray, selectMeasurementsArray, useSyncStore } from '@/sync/store'
import { addItem, updateItem, deleteItem, addHabit, deleteHabit, saveMeasurement, deleteMeasurement } from '@/sync/mutations'
import type { DomainItem, Habit, HabitInstanceItem, Measurement } from '@/domain/types'

/** Every Date-typed field per record type (see domain/types.ts) — JSON.parse
 *  gives these back as plain strings, not Date objects, so they're revived
 *  explicitly by key rather than guessing from string shape: Anchor/
 *  Completion's own `date`/`start`/`end` fields are also ISO strings but are
 *  NOT Date-typed (see wire/anchor.ts) — a blanket "revive anything that
 *  looks like a date" pass would wrongly convert those too. */
function reviveItemDates(raw: Record<string, unknown>): DomainItem {
  const result: Record<string, unknown> = { ...raw, createdAt: new Date(raw.createdAt as string), updatedAt: new Date(raw.updatedAt as string) }
  if (raw.deadline) result.deadline = new Date(raw.deadline as string)
  if (raw.externalRef && typeof raw.externalRef === 'object') {
    const ref = raw.externalRef as Record<string, unknown>
    result.externalRef = { ...ref, lastSeen: new Date(ref.lastSeen as string) }
  }
  return result as unknown as DomainItem
}

function reviveHabitDates(raw: Record<string, unknown>): Habit {
  return { ...raw, createdAt: new Date(raw.createdAt as string) } as unknown as Habit
}

function reviveMeasurementDates(raw: Record<string, unknown>): Measurement {
  return { ...raw, date: new Date(raw.date as string) } as unknown as Measurement
}

/**
 * Raw database admin — view/create/edit/delete every Item, Habit, and
 * Measurement, individually or in bulk. Built on the exact same
 * useSyncStore data and sync/mutations.ts functions the rest of the app
 * uses (addItem/updateItem/deleteItem, addHabit/deleteHabit,
 * saveMeasurement/deleteMeasurement) — this is a real, live-writing admin
 * surface, not a mock or a separate read path, which is the point of a
 * debug tool: what you see here IS the database.
 *
 * body_profiles is deliberately not included — it's a single row per user
 * (no list of "entries"), which doesn't fit the select/bulk-select shape
 * this page is built around; editing it would need its own one-off form.
 */
export function DebugPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const habits = useSyncStore(useShallow(selectHabitsArray))
  const measurements = useSyncStore(useShallow(selectMeasurementsArray))

  const itemRecords: DebugRecord[] = items.map((item) => ({
    id: item.id,
    label: `[${item.kind}] ${item.title}`,
    sublabel: item.id,
    raw: item,
  }))

  const habitRecords: DebugRecord[] = habits.map((habit) => ({
    id: habit.id,
    label: habit.name + (habit.isArchived ? ' (archived)' : ''),
    sublabel: habit.id,
    raw: habit,
  }))

  const measurementRecords: DebugRecord[] = measurements.map((m) => ({
    id: m.id,
    label: `${m.date instanceof Date ? m.date.toISOString() : String(m.date)} — ${m.source}`,
    sublabel: m.id,
    raw: m,
  }))

  async function saveItem(id: string | null, parsed: Record<string, unknown>) {
    const revived = reviveItemDates(parsed)
    if (id && useSyncStore.getState().items.has(id)) await updateItem(revived)
    else await addItem(revived)
  }

  async function saveHabit(id: string | null, parsed: Record<string, unknown>) {
    // addHabit upserts either way (see its own doc comment) — no separate
    // "update" mutation exists for habits, unlike items.
    void id
    await addHabit(reviveHabitDates(parsed))
  }

  async function saveMeasurementRecord(id: string | null, parsed: Record<string, unknown>) {
    void id
    await saveMeasurement(reviveMeasurementDates(parsed))
  }

  function habitInstancesFor(habitID: string): HabitInstanceItem[] {
    return items.filter((i): i is HabitInstanceItem => i.kind === 'habitInstance' && i.habitID === habitID)
  }

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-text-primary">Debug</h1>
      <p className="mb-4 text-sm text-text-secondary">
        Raw database view — every write here goes straight to Supabase, same as the real UI. No confirmation prompts.
      </p>

      <DebugSection
        title="Items"
        records={itemRecords}
        newTemplate={() => {
          const now = new Date()
          return {
            kind: 'task',
            id: crypto.randomUUID(),
            title: '',
            createdAt: now.toISOString(),
            updatedAt: now.toISOString(),
            importance: 1,
            anchor: { type: 'untimed' },
            completion: { type: 'open' },
            tags: [],
          }
        }}
        onSave={saveItem}
        onDelete={(r) => deleteItem(r.raw as DomainItem)}
      />

      <DebugSection
        title="Habits"
        records={habitRecords}
        newTemplate={() => ({
          id: crypto.randomUUID(),
          name: '',
          frequency: { type: 'daily' },
          forgiveness: { type: 'none' },
          recurrenceRuleRaw: '',
          createdAt: new Date().toISOString(),
          isArchived: false,
        })}
        onSave={saveHabit}
        onDelete={(r) => deleteHabit(r.raw as Habit, habitInstancesFor(r.id))}
      />

      <DebugSection
        title="Measurements"
        records={measurementRecords}
        newTemplate={() => ({
          id: crypto.randomUUID(),
          source: 'manual',
          date: new Date().toISOString(),
        })}
        onSave={saveMeasurementRecord}
        onDelete={(r) => deleteMeasurement(r.raw as Measurement)}
      />
    </div>
  )
}
