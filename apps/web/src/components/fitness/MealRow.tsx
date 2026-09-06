import { useState } from 'react'
import { Circle, Trash2, UtensilsCrossed } from 'lucide-react'
import { updateItem, toggleComplete, deleteItem } from '@/sync/mutations'
import { recipeName } from '@/domain/fitnessDisplay'
import { Input } from '@/components/ui/input'
import { Checkbox } from '@/components/ui/checkbox'
import { cn } from '@/lib/utils'
import type { MealItem } from '@/domain/types'

type Props = {
  item: MealItem
  selectMode?: boolean
  selected?: boolean
  onToggleSelect?: () => void
}

export function MealRow({ item, selectMode = false, selected = false, onToggleSelect }: Props) {
  const done = item.completion.type !== 'open'
  const [kcalInput, setKcalInput] = useState(item.actualKcal?.toString() ?? '')
  const overTarget = item.actualKcal !== undefined && item.actualKcal > item.targetKcal

  function saveKcal() {
    const parsed = Number(kcalInput)
    if (kcalInput === '' || Number.isNaN(parsed)) return
    if (parsed === item.actualKcal) return
    void updateItem({ ...item, actualKcal: parsed })
  }

  return (
    <li className="flex flex-col gap-2.5 rounded-leo-md border border-divider bg-surface px-3 py-3">
      <div className="flex items-start gap-3">
        {selectMode ? (
          <Checkbox
            checked={selected}
            onCheckedChange={() => onToggleSelect?.()}
            aria-label={`Select "${item.title}"`}
            className="mt-1 shrink-0"
          />
        ) : (
          <button
            type="button"
            onClick={() => void toggleComplete(item)}
            aria-label={`Mark "${item.title}" ${done ? 'not done' : 'done'}`}
            className="mt-0.5 shrink-0 rounded-full p-0.5 hover:bg-surface-elevated"
          >
            {done ? (
              <UtensilsCrossed className="h-5 w-5 text-success" strokeWidth={2.5} />
            ) : (
              <Circle className="h-5 w-5 text-text-secondary" />
            )}
          </button>
        )}

        <div className="flex flex-1 flex-col gap-1">
          <div className="flex items-start justify-between gap-2">
            <span className={cn('text-sm font-medium text-text-primary', done && 'text-text-secondary line-through')}>
              {item.title}
            </span>
            {!selectMode && (
              <button
                type="button"
                onClick={() => void deleteItem(item)}
                aria-label={`Delete "${item.title}"`}
                className="shrink-0 rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated hover:text-danger"
              >
                <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            )}
          </div>

          <span className="text-xs text-text-secondary">
            {recipeName(item.recipeID)} · {item.servings} serving{item.servings === 1 ? '' : 's'}
          </span>

          <div className="flex flex-wrap items-center gap-1.5">
            <span
              className={cn(
                'rounded-leo-pill px-2 py-0.5 text-[11px] font-medium',
                overTarget ? 'bg-warning/15 text-warning' : 'bg-accent-muted text-text-primary'
              )}
            >
              {item.actualKcal ?? item.targetKcal} / {item.targetKcal} kcal
            </span>
            {item.loggedMacros && (
              <span className="text-[11px] text-text-secondary">
                P{Math.round(item.loggedMacros.proteinG)}g · C{Math.round(item.loggedMacros.carbG)}g · F
                {Math.round(item.loggedMacros.fatG)}g
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="flex items-center gap-2 pl-8">
        <label htmlFor={`kcal-${item.id}`} className="text-xs whitespace-nowrap text-text-secondary">
          Actual kcal
        </label>
        <Input
          id={`kcal-${item.id}`}
          type="number"
          className="h-8 w-24"
          value={kcalInput}
          onChange={(e) => setKcalInput(e.target.value)}
          onBlur={saveKcal}
          onKeyDown={(e) => e.key === 'Enter' && saveKcal()}
        />
      </div>
    </li>
  )
}
