import { useState, type FormEvent } from 'react'
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { DateTimePicker } from '@/components/ui/DateTimePicker'
import { Label } from '@/components/ui/label'
import { addItem } from '@/sync/mutations'
import { requestAlarmPermissionIfNeeded } from '@/alarms/scheduler'
import type { AlarmItem } from '@/domain/types'

/**
 * Creation only — an alarm is a regular DomainItem with a `.point` anchor,
 * so it already renders through the normal Today/Inbox ItemRow list once
 * created. A separate "upcoming alarms" list here would just duplicate that.
 */
export function AlarmQuickAdd({ embedded = false }: { embedded?: boolean }) {
  const [title, setTitle] = useState('')
  const [when, setWhen] = useState('')

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const trimmed = title.trim()
    if (!trimmed || !when) return
    await requestAlarmPermissionIfNeeded()
    setTitle('')
    setWhen('')

    const now = new Date()
    const item: AlarmItem = {
      kind: 'alarm',
      id: crypto.randomUUID(),
      title: trimmed,
      createdAt: now,
      updatedAt: now,
      importance: 3,
      anchor: { type: 'point', date: when },
      completion: { type: 'open' },
      tags: [],
      soundProfileRaw: 'alarm_default',
      escalates: false,
    }
    void addItem(item)
  }

  const form = (
    <form onSubmit={handleSubmit} className="flex flex-wrap items-end gap-2">
      <TextField
        label="Alarm"
        className="min-w-[160px] flex-1"
        placeholder="Wake up"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
      />
      <div className="flex flex-col gap-1.5">
        <Label>Time</Label>
        <DateTimePicker value={when} onChange={setWhen} className="min-w-[220px]" />
      </div>
      <Button type="submit">Set alarm</Button>
    </form>
  )

  if (embedded) return form

  return (
    <section className="mt-6 rounded-leo-md border border-divider bg-surface p-3">
      <h2 className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Set an alarm</h2>
      {form}
    </section>
  )
}
