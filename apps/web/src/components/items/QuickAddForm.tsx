import { useState, type FormEvent } from 'react'
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { DateTimePicker } from '@/components/ui/DateTimePicker'
import { Label } from '@/components/ui/label'
import { addItem } from '@/sync/mutations'
import { endOfDay } from '@/domain/dates'
import type { Anchor } from '@/wire/anchor'
import type { EventItem, Tag, TaskItem } from '@/domain/types'

const ONE_HOUR_MS = 60 * 60 * 1000

/**
 * Deliberately scoped down for v1: creates a task with an optional due time,
 * not a full anchor-picker/tag-editor. A richer item-detail editor (reminder
 * creation, notes, tags) is a real, separate chunk of UI surface — cut here
 * so Phase 4 could ship the navigation + realtime list + habit check-ins,
 * rather than stall on a form that isn't this phase's point. `allowEventKind`
 * is the one exception: PdfViewerPage's task panel needed a way to create an
 * event (a start/end time block) without leaving the reader, so a minimal
 * Task/Event toggle was added rather than building a second form.
 */
export function QuickAddForm({
  defaultUntimed = false,
  defaultDate,
  defaultTag,
  allowEventKind = false,
}: {
  defaultUntimed?: boolean
  defaultDate?: Date
  /** ProjectDetailPage's "add a task" — pre-tags the new task with the
   *  project being viewed instead of leaving it unfiled. */
  defaultTag?: Tag
  /** Shows a Task/Event toggle; Event swaps the single "when" field for a
   *  start/end pair and creates an EventItem instead. */
  allowEventKind?: boolean
}) {
  const [kind, setKind] = useState<'task' | 'event'>('task')
  const [title, setTitle] = useState('')
  const [when, setWhen] = useState('')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const trimmed = title.trim()
    if (!trimmed) return

    const now = new Date()

    if (kind === 'event') {
      if (!start) return
      const endDate = end ? new Date(end) : new Date(new Date(start).getTime() + ONE_HOUR_MS)
      const item: EventItem = {
        kind: 'event',
        id: crypto.randomUUID(),
        title: trimmed,
        createdAt: now,
        updatedAt: now,
        importance: 1,
        anchor: { type: 'timeBlock', start, end: endDate.toISOString() },
        completion: { type: 'open' },
        tags: defaultTag ? [defaultTag] : [],
        attendees: [],
      }
      void addItem(item)
      setTitle('')
      setStart('')
      setEnd('')
      return
    }

    // Precedence: an explicit time the user picked always wins; failing
    // that, a task added while viewing a specific day (TodayPage's
    // DateNavigator) lands on THAT day's end rather than the untimed
    // backlog — "add a task while looking at Tuesday" reads as "for
    // Tuesday," not "for whenever." Inbox's QuickAddForm never passes
    // defaultDate, so its untimed-by-default behavior is unchanged.
    const anchor: Anchor =
      when && !defaultUntimed
        ? { type: 'dueAt', date: when }
        : defaultDate && !defaultUntimed
          ? { type: 'dueAt', date: endOfDay(defaultDate).toISOString() }
          : { type: 'untimed' }

    const item: TaskItem = {
      kind: 'task',
      id: crypto.randomUUID(),
      title: trimmed,
      createdAt: now,
      updatedAt: now,
      importance: 1,
      anchor,
      completion: { type: 'open' },
      tags: defaultTag ? [defaultTag] : [],
    }
    void addItem(item)
    setTitle('')
    setWhen('')
  }

  return (
    <form onSubmit={handleSubmit} className="mb-4 flex flex-wrap items-end gap-2">
      {allowEventKind && (
        <div className="flex items-center gap-0.5 rounded-md border border-divider p-0.5">
          <Button type="button" size="xs" variant={kind === 'task' ? 'default' : 'ghost'} onClick={() => setKind('task')}>
            Task
          </Button>
          <Button type="button" size="xs" variant={kind === 'event' ? 'default' : 'ghost'} onClick={() => setKind('event')}>
            Event
          </Button>
        </div>
      )}

      <TextField
        label={kind === 'event' ? 'Add an event' : 'Add a task'}
        className="min-w-[200px] flex-1"
        placeholder={kind === 'event' ? "What's happening?" : 'What needs doing?'}
        value={title}
        onChange={(e) => setTitle(e.target.value)}
      />

      {kind === 'event' ? (
        <>
          <div className="flex flex-col gap-1.5">
            <Label>Starts</Label>
            <DateTimePicker value={start} onChange={setStart} className="min-w-[220px]" />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Ends (optional)</Label>
            <DateTimePicker value={end} onChange={setEnd} className="min-w-[220px]" placeholder="Defaults to 1 hour" />
          </div>
        </>
      ) : (
        !defaultUntimed && (
          <div className="flex flex-col gap-1.5">
            <Label>When (optional)</Label>
            <DateTimePicker
              value={when}
              onChange={setWhen}
              className="min-w-[220px]"
              placeholder={defaultDate ? 'Defaults to end of day' : undefined}
            />
          </div>
        )
      )}

      <Button type="submit">Add</Button>
    </form>
  )
}
