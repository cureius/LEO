import type { RealtimeChannel } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabaseClient'
import { useSyncStore } from './store'
import { decodeItemRow } from '@/wire/items'
import { decodeHabitPayload } from '@/wire/habits'
import { decodeBodyProfilePayload, decodeMeasurementPayload } from '@/wire/fitness'

// ---------------------------------------------------------------------------
// Echo suppression — a realtime event for a row THIS tab just pushed must not
// re-apply as if it were a genuinely new remote change (which would be a
// no-op today, but matters once Phase 2 adds writes). Two different
// mechanisms because items carry a payload-level `updatedAt` and habits do
// not (confirmed absent from SnapshotHabit) — see wire/habits.ts.
// ---------------------------------------------------------------------------

const pendingByUpdatedAt = new Map<string, number>() // items: id -> updatedAt ms just pushed
const pendingByHash = new Map<string, string>() // habits: id -> content hash just pushed

export function markItemPending(id: string, updatedAtMs: number) {
  pendingByUpdatedAt.set(id, updatedAtMs)
}
export function markHabitPending(id: string, hash: string) {
  pendingByHash.set(id, hash)
}

export async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

// ---------------------------------------------------------------------------
// Row shapes as returned by supabase-js
// ---------------------------------------------------------------------------

// `data` is `jsonb`: a REST select() returns it as a string (the Swift client
// writes a pre-serialized string), but a realtime postgres_changes payload
// for the same column arrives already parsed — see decodeItemRow's doc comment.
type ItemRow = {
  id: string
  kind: string
  data: string | Record<string, unknown>
  updated_at: string
  deleted_at: string | null
}
type HabitRow = { id: string; data: string | null; updated_at: string; deleted_at: string | null }
type MeasurementRow = { id: string; data: string | null; deleted_at: string | null }
type BodyProfileRow = { user_id: string; data: string | null }

// ---------------------------------------------------------------------------
// Apply functions — shared between the initial fetch and realtime events
// ---------------------------------------------------------------------------

function applyItemRow(row: ItemRow) {
  const store = useSyncStore.getState()

  if (row.deleted_at) {
    store.removeItem(row.id)
    return
  }

  const decoded = decodeItemRow(row.kind, row.data)
  if (!decoded) {
    // ~26 rows in the live DB are from an old, since-fixed native-app bug
    // (EventKit mirrors pushed before an exclusion fix). Skip and warn —
    // one bad row must never take down the whole sync.
    console.warn(`[sync] skipping undecodable item row id=${row.id} kind=${row.kind}`)
    return
  }

  const pendingAt = pendingByUpdatedAt.get(decoded.id)
  if (pendingAt !== undefined && decoded.updatedAt.getTime() <= pendingAt) {
    pendingByUpdatedAt.delete(decoded.id) // this is our own echo
    return
  }

  const local = store.getItem(decoded.id)
  if (!local || decoded.updatedAt > local.updatedAt) {
    store.upsertItem(decoded)
  }
}

async function applyHabitRow(row: HabitRow) {
  const store = useSyncStore.getState()

  if (row.deleted_at) {
    store.removeHabit(row.id)
    return
  }
  if (!row.data) return

  const hash = await sha256Hex(row.data)
  if (pendingByHash.get(row.id) === hash) {
    pendingByHash.delete(row.id) // our own echo
    return
  }

  const decoded = decodeHabitPayload(row.data)
  if (!decoded) {
    console.warn(`[sync] skipping undecodable habit row id=${row.id}`)
    return
  }
  store.upsertHabit(decoded)
}

function applyMeasurementRow(row: MeasurementRow) {
  const store = useSyncStore.getState()
  if (row.deleted_at || !row.data) return
  const decoded = decodeMeasurementPayload(row.data)
  if (!decoded) {
    console.warn(`[sync] skipping undecodable measurement row id=${row.id}`)
    return
  }
  store.upsertMeasurement(decoded)
}

function applyBodyProfileRow(row: BodyProfileRow) {
  if (!row.data) return
  const decoded = decodeBodyProfilePayload(row.data)
  if (!decoded) {
    console.warn(`[sync] skipping undecodable body_profiles row user_id=${row.user_id}`)
    return
  }
  useSyncStore.getState().setBodyProfile(decoded)
}

// ---------------------------------------------------------------------------
// Initial fetch + delta re-fetch
//
// Postgres logical replication (what Realtime rides on) does not replay
// events missed while disconnected. `lastSyncCursor` plus an authoritative
// REST re-fetch on reconnect closes that gap — this is why the Swift app
// layers `syncOnForeground()` on top of realtime rather than trusting
// realtime alone; see LEO/Sync/SupabaseSync.swift.
// ---------------------------------------------------------------------------

let lastSyncCursor = new Date(0).toISOString()

async function fetchSince(cursor: string) {
  const [itemsRes, habitsRes, measurementsRes, profileRes] = await Promise.all([
    supabase.from('items').select('id, kind, data, updated_at, deleted_at').gt('updated_at', cursor),
    supabase.from('habits').select('id, data, updated_at, deleted_at').gt('updated_at', cursor),
    supabase.from('measurements').select('id, data, deleted_at'),
    supabase.from('body_profiles').select('user_id, data'),
  ])

  if (itemsRes.error) throw itemsRes.error
  if (habitsRes.error) throw habitsRes.error
  if (measurementsRes.error) throw measurementsRes.error
  if (profileRes.error) throw profileRes.error

  for (const row of itemsRes.data as ItemRow[]) applyItemRow(row)
  for (const row of habitsRes.data as HabitRow[]) await applyHabitRow(row)
  for (const row of measurementsRes.data as MeasurementRow[]) applyMeasurementRow(row)
  for (const row of profileRes.data as BodyProfileRow[]) applyBodyProfileRow(row)

  const maxItemsUpdated = (itemsRes.data as ItemRow[]).reduce((max, r) => (r.updated_at > max ? r.updated_at : max), cursor)
  const maxHabitsUpdated = (habitsRes.data as HabitRow[]).reduce((max, r) => (r.updated_at > max ? r.updated_at : max), cursor)
  lastSyncCursor = maxItemsUpdated > maxHabitsUpdated ? maxItemsUpdated : maxHabitsUpdated
}

// ---------------------------------------------------------------------------
// Realtime channel — one per session, module-level singleton so React
// StrictMode's dev-mode double-invoke can't create two subscriptions.
// ---------------------------------------------------------------------------

let channel: RealtimeChannel | null = null
let visibilityHandlerAttached = false

async function handleVisibilityChange() {
  if (document.visibilityState === 'visible') {
    try {
      await fetchSince(lastSyncCursor)
    } catch (err) {
      console.error('[sync] visibility re-fetch failed', err)
    }
  }
}

export async function startSync(userId: string) {
  const store = useSyncStore.getState()
  store.setConnectionStatus('connecting')

  // Initial full load.
  try {
    await fetchSince(new Date(0).toISOString())
    store.setInitialLoadComplete()
  } catch (err) {
    console.error('[sync] initial load failed', err)
    store.setConnectionStatus('disconnected')
    return
  }

  if (channel) {
    await supabase.removeChannel(channel)
    channel = null
  }

  channel = supabase
    .channel('leo-sync')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'items', filter: `user_id=eq.${userId}` },
      (payload) => applyItemRow(payload.new as ItemRow),
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'habits', filter: `user_id=eq.${userId}` },
      (payload) => void applyHabitRow(payload.new as HabitRow),
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'measurements', filter: `user_id=eq.${userId}` },
      (payload) => applyMeasurementRow(payload.new as MeasurementRow),
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'body_profiles', filter: `user_id=eq.${userId}` },
      (payload) => applyBodyProfileRow(payload.new as BodyProfileRow),
    )
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        store.setConnectionStatus('connected')
        // A channel that just (re)subscribed may have missed events while
        // it was down — close that gap the same way foreground does.
        void fetchSince(lastSyncCursor).catch((err) => console.error('[sync] post-subscribe re-fetch failed', err))
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        store.setConnectionStatus('disconnected')
      }
    })

  if (!visibilityHandlerAttached) {
    document.addEventListener('visibilitychange', handleVisibilityChange)
    visibilityHandlerAttached = true
  }
}

/** Full re-fetch of everything, bypassing the delta cursor — for a manual
 *  "hard refresh" action rather than the normal incremental sync path. */
export async function refreshAll() {
  await fetchSince(new Date(0).toISOString())
}

export async function stopSync() {
  if (channel) {
    await supabase.removeChannel(channel)
    channel = null
  }
  if (visibilityHandlerAttached) {
    document.removeEventListener('visibilitychange', handleVisibilityChange)
    visibilityHandlerAttached = false
  }
  lastSyncCursor = new Date(0).toISOString()
  useSyncStore.getState().reset()
}
