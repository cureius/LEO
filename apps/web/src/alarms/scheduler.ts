import { useSyncStore, selectItemsArray } from '@/sync/store'
import { anchorSortDate } from '@/wire/anchor'
import { playAlarmSound } from './sounds'
import type { AlarmItem, DomainItem } from '@/domain/types'

/**
 * Port of the plan's §8 design: recompute the single nearest armed FUTURE
 * alarm on every store change, clear any existing timer, set one new one.
 * Deliberately does NOT schedule N independent timers for N future alarms —
 * that invites timer-leak/drift bugs for no benefit, since only the
 * soonest one can ever fire next.
 *
 * A browser tab has no background execution — this can only ever fire
 * while the tab is open, unlike native's `UNNotificationRequest` OS-level
 * scheduling. AlarmBanner.tsx makes that limitation visible, not silent.
 */
let timeoutId: ReturnType<typeof setTimeout> | null = null
let storeUnsubscribe: (() => void) | null = null
let armedCount = 0
const armedCountListeners = new Set<(count: number) => void>()

export function subscribeArmedCount(listener: (count: number) => void): () => void {
  armedCountListeners.add(listener)
  listener(armedCount)
  return () => armedCountListeners.delete(listener)
}

function setArmedCount(count: number) {
  if (count === armedCount) return
  armedCount = count
  for (const l of armedCountListeners) l(count)
}

function findArmedAlarms(items: DomainItem[]): AlarmItem[] {
  const now = Date.now()
  const armed: AlarmItem[] = []
  for (const item of items) {
    if (item.kind !== 'alarm' || item.completion.type !== 'open') continue
    const date = anchorSortDate(item.anchor)
    if (date && date.getTime() > now) armed.push(item)
  }
  return armed
}

function scheduleNext() {
  if (timeoutId) {
    clearTimeout(timeoutId)
    timeoutId = null
  }
  const armed = findArmedAlarms(selectItemsArray(useSyncStore.getState()))
  setArmedCount(armed.length)
  if (armed.length === 0) return

  const nearest = armed.reduce((min, a) => {
    const aDate = anchorSortDate(a.anchor)!.getTime()
    const minDate = anchorSortDate(min.anchor)!.getTime()
    return aDate < minDate ? a : min
  })
  const delay = anchorSortDate(nearest.anchor)!.getTime() - Date.now()
  timeoutId = setTimeout(() => void fireAlarm(nearest), Math.max(0, delay))
}

async function fireAlarm(alarm: AlarmItem) {
  if (Notification.permission === 'granted' && document.visibilityState === 'hidden') {
    new Notification(`⏰ ${alarm.title}`, { tag: alarm.id })
  }
  playAlarmSound(alarm.soundProfileRaw)
  scheduleNext() // recompute for whatever's next after this one fires
}

export function startAlarmScheduler() {
  if (storeUnsubscribe) return // already running — idempotent start
  scheduleNext()
  storeUnsubscribe = useSyncStore.subscribe(() => scheduleNext())
}

export function stopAlarmScheduler() {
  if (timeoutId) {
    clearTimeout(timeoutId)
    timeoutId = null
  }
  if (storeUnsubscribe) {
    storeUnsubscribe()
    storeUnsubscribe = null
  }
  setArmedCount(0)
}

/** Gated behind first alarm creation, not app load — don't ask before there's a reason. */
export async function requestAlarmPermissionIfNeeded(): Promise<void> {
  if (typeof Notification === 'undefined') return
  if (Notification.permission === 'default') {
    await Notification.requestPermission()
  }
}
