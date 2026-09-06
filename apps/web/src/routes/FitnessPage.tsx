import { useMemo, useState } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { CheckSquare, Trash2, X } from 'lucide-react'
import { WorkoutRow } from '@/components/fitness/WorkoutRow'
import { MealRow } from '@/components/fitness/MealRow'
import { FitnessOverview } from '@/components/fitness/FitnessOverview'
import { Button } from '@/components/ui/button'
import { selectItemsArray, selectMeasurementsArray, useSyncStore } from '@/sync/store'
import { deleteItem } from '@/sync/mutations'
import { anchorSortDate } from '@/wire/anchor'
import { formatDayHeading } from '@/domain/fitnessDisplay'
import type { MealItem, WorkoutItem } from '@/domain/types'

function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

type DayGroup = { date: Date | null; workouts: WorkoutItem[]; meals: MealItem[] }

/**
 * Redesigned from a flat "every workout ever" list + "every meal ever" list
 * (no dates, no context, raw `<input type="checkbox">`) into: a Body/Today
 * overview surfacing the bodyProfile/measurements data that already syncs
 * down but had no UI anywhere, plus a single day-grouped log (most recent
 * first) — a fitness log reads naturally as a diary, not two disjoint
 * lifetime lists.
 */
export function FitnessPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const measurements = useSyncStore(useShallow(selectMeasurementsArray))
  const bodyProfile = useSyncStore((s) => s.bodyProfile)
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)

  const [selectMode, setSelectMode] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [deleting, setDeleting] = useState(false)

  const workouts = items.filter((i): i is WorkoutItem => i.kind === 'workout')
  const meals = items.filter((i): i is MealItem => i.kind === 'meal')

  const allIds = useMemo(() => [...workouts, ...meals].map((i) => i.id), [workouts, meals])
  const allSelected = allIds.length > 0 && allIds.every((id) => selectedIds.has(id))

  function toggleSelect(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleSelectAll() {
    setSelectedIds(allSelected ? new Set() : new Set(allIds))
  }

  function exitSelectMode() {
    setSelectMode(false)
    setSelectedIds(new Set())
  }

  async function handleDeleteSelected() {
    setDeleting(true)
    try {
      const toDelete = items.filter((i) => selectedIds.has(i.id))
      await Promise.all(toDelete.map((i) => deleteItem(i)))
    } finally {
      setDeleting(false)
      exitSelectMode()
    }
  }

  const today = new Date()
  const todayWorkouts = workouts.filter((w) => {
    const d = anchorSortDate(w.anchor)
    return d ? isSameDay(d, today) : false
  })
  const todayMeals = meals.filter((m) => {
    const d = anchorSortDate(m.anchor)
    return d ? isSameDay(d, today) : false
  })

  const groups = useMemo(() => {
    const map = new Map<string, DayGroup>()
    function bucket(item: WorkoutItem | MealItem) {
      const d = anchorSortDate(item.anchor)
      const key = d ? startOfDay(d).toDateString() : 'unscheduled'
      let group = map.get(key)
      if (!group) {
        group = { date: d ? startOfDay(d) : null, workouts: [], meals: [] }
        map.set(key, group)
      }
      if (item.kind === 'workout') group.workouts.push(item)
      else group.meals.push(item)
    }
    workouts.forEach(bucket)
    meals.forEach(bucket)

    for (const group of map.values()) {
      const byTime = (a: WorkoutItem | MealItem, b: WorkoutItem | MealItem) =>
        (anchorSortDate(a.anchor)?.getTime() ?? 0) - (anchorSortDate(b.anchor)?.getTime() ?? 0)
      group.workouts.sort(byTime)
      group.meals.sort(byTime)
    }

    return Array.from(map.values()).sort((a, b) => {
      if (!a.date && !b.date) return 0
      if (!a.date) return -1
      if (!b.date) return 1
      return b.date.getTime() - a.date.getTime()
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workouts, meals])

  const isEmpty = workouts.length === 0 && meals.length === 0

  return (
    <div className="p-6">
      <div className="mb-1 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-text-primary">Fitness</h1>
        {!isEmpty &&
          (selectMode ? (
            <div className="flex items-center gap-2">
              <Button variant="ghost" size="sm" onClick={toggleSelectAll} className="gap-1.5 text-text-secondary">
                <CheckSquare className="h-3.5 w-3.5" aria-hidden="true" />
                {allSelected ? 'Deselect all' : 'Select all'}
              </Button>
              <span className="text-sm text-text-secondary">{selectedIds.size} selected</span>
              <Button variant="ghost" size="sm" onClick={exitSelectMode} className="gap-1.5 text-text-secondary">
                <X className="h-3.5 w-3.5" aria-hidden="true" />
                Cancel
              </Button>
              <Button
                variant="destructive"
                size="sm"
                onClick={() => void handleDeleteSelected()}
                disabled={selectedIds.size === 0 || deleting}
                className="gap-1.5"
              >
                <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                {deleting ? 'Deleting…' : `Delete${selectedIds.size > 0 ? ` (${selectedIds.size})` : ''}`}
              </Button>
            </div>
          ) : (
            <Button variant="ghost" size="sm" onClick={() => setSelectMode(true)} className="gap-1.5 text-text-secondary">
              <CheckSquare className="h-3.5 w-3.5" aria-hidden="true" />
              Select
            </Button>
          ))}
      </div>
      <p className="mb-4 text-sm text-text-secondary">Workouts and meals — create plans via Ask LEO.</p>

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && (
        <FitnessOverview
          bodyProfile={bodyProfile}
          measurements={measurements}
          todayWorkouts={todayWorkouts}
          todayMeals={todayMeals}
        />
      )}

      {initialLoadComplete && isEmpty && (
        <p className="text-sm text-text-secondary">
          No workouts or meals yet. Ask LEO can generate a plan, or log one on iPhone/Mac.
        </p>
      )}

      <div className="flex flex-col gap-6">
        {groups.map((group) => (
          <section key={group.date ? group.date.toISOString() : 'unscheduled'}>
            <h2 className="mb-2 text-xs font-medium tracking-wide text-text-secondary uppercase">
              {formatDayHeading(group.date, today)}
            </h2>
            <ul className="flex flex-col gap-2">
              {group.workouts.map((w) => (
                <WorkoutRow
                  key={w.id}
                  item={w}
                  selectMode={selectMode}
                  selected={selectedIds.has(w.id)}
                  onToggleSelect={() => toggleSelect(w.id)}
                />
              ))}
              {group.meals.map((m) => (
                <MealRow
                  key={m.id}
                  item={m}
                  selectMode={selectMode}
                  selected={selectedIds.has(m.id)}
                  onToggleSelect={() => toggleSelect(m.id)}
                />
              ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  )
}
