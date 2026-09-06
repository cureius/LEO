import { useState } from 'react'
import { AlarmClock, ListTodo } from 'lucide-react'
import { QuickAddForm } from './QuickAddForm'
import { AlarmQuickAdd } from './AlarmQuickAdd'
import { cn } from '@/lib/utils'

type Mode = 'task' | 'alarm'

/**
 * Groups task and alarm creation into one prominent card at the top of
 * Today, instead of QuickAddForm living at the top and AlarmQuickAdd being
 * the very last thing on the page, past Scheduled/Backlog/Completed — easy
 * to create a task, easy to never notice alarm creation exists at all.
 * Reuses QuickAddForm/AlarmQuickAdd as-is (both stay usable standalone —
 * QuickAddForm is still used directly by InboxPage) rather than duplicating
 * their form logic.
 */
export function QuickAddSection({ defaultDate }: { defaultDate?: Date }) {
  const [mode, setMode] = useState<Mode>('task')

  return (
    <section className="mb-4 rounded-leo-md border border-divider bg-surface p-3">
      <div className="mb-3 flex gap-1 rounded-leo-md bg-surface-elevated p-1">
        {(
          [
            { value: 'task' as const, label: 'Task', Icon: ListTodo },
            { value: 'alarm' as const, label: 'Alarm', Icon: AlarmClock },
          ]
        ).map(({ value, label, Icon }) => (
          <button
            key={value}
            type="button"
            onClick={() => setMode(value)}
            aria-pressed={mode === value}
            className={cn(
              'flex flex-1 items-center justify-center gap-1.5 rounded-leo-sm py-1.5 text-xs font-medium transition-colors',
              mode === value ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
            )}
          >
            <Icon className="h-3.5 w-3.5" aria-hidden="true" />
            {label}
          </button>
        ))}
      </div>

      {mode === 'task' ? <QuickAddForm defaultDate={defaultDate} /> : <AlarmQuickAdd embedded />}
    </section>
  )
}
