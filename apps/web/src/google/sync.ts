import { toast } from 'sonner'
import { getConnections, getValidAccessToken, markConnectionHealth, type GoogleConnection } from './connection'
import { GoogleInvalidGrantError } from './oauth'
import { listGoogleEvents, type GoogleEvent } from './calendarApi'
import { googleEventToItem } from './mapping'
import { findLinkedItemId, saveLink, removeLink } from './links'
import { addItem, updateItem, deleteItem, errorMessage } from '@/sync/mutations'
import { useSyncStore } from '@/sync/store'
import type { EventItem } from '@/domain/types'

// -30/+90 days — wide enough to cover "what did I do recently" and
// "what's coming up" without pulling someone's entire calendar history on
// every pass; matches the rough shape of get_past_items'/get_week's
// windows elsewhere in the app rather than inventing a new convention.
const WINDOW_PAST_DAYS = 30
const WINDOW_FUTURE_DAYS = 90

// A recurring event's occurrences are still fetched across the full
// -30/+90 window above (Google returns every one of them within range), but
// only ones starting within this many days are actually worth materializing
// as a LEO item — a daily standup 80 days out is Google's problem to
// remember, not a row LEO needs sitting in the DB today. One-off events are
// NOT subject to this — they still get the full window, unchanged.
const RECURRING_FUTURE_WINDOW_DAYS = 14

function eventStartDate(event: GoogleEvent): Date {
  return new Date(event.start.dateTime ?? event.start.date ?? Date.now())
}

/** True only for an occurrence of a recurring series (`recurringEventId`
 *  set) whose start is further out than we bother pre-materializing. */
function isRecurringInstanceBeyondWindow(event: GoogleEvent, now: number): boolean {
  if (!event.recurringEventId) return false
  return eventStartDate(event).getTime() > now + RECURRING_FUTURE_WINDOW_DAYS * 86_400_000
}

/** One full pull pass for ONE connection: list events in the window, upsert
 *  each as a linked LEO EventItem, and mirror Google-side cancellations as
 *  local deletes. Safe to call repeatedly/concurrently-ish — every write
 *  goes through the same addItem/updateItem/deleteItem the rest of the app
 *  uses, so a mid-sync failure leaves things in a state the normal
 *  optimistic-write rollback already knows how to handle, not a
 *  half-applied sync-specific mess. */
async function syncOneConnection(connection: GoogleConnection): Promise<void> {
  const accessToken = await getValidAccessToken(connection)
  const now = Date.now()
  const events = await listGoogleEvents(accessToken, connection.calendarId, {
    timeMin: new Date(now - WINDOW_PAST_DAYS * 86_400_000).toISOString(),
    timeMax: new Date(now + WINDOW_FUTURE_DAYS * 86_400_000).toISOString(),
  })

  const items = useSyncStore.getState().items

  for (const event of events) {
    const linkedId = findLinkedItemId(connection.id, event.id)

    if (event.status === 'cancelled') {
      if (linkedId) {
        const existing = items.get(linkedId)
        // skipGooglePush: this delete originated FROM Google (the event is
        // already cancelled there) — pushing a delete back would be a
        // pointless round trip against an event that's already gone.
        if (existing) await deleteItem(existing, { skipGooglePush: true })
        await removeLink(linkedId)
      }
      continue
    }

    if (isRecurringInstanceBeyondWindow(event, now)) {
      // Too far out to be worth a row yet. If it was already materialized
      // under a previous sync (or before this cap existed), remove it now —
      // safe because it hasn't happened and hasn't been edited, and it'll
      // simply reappear once it's back within RECURRING_FUTURE_WINDOW_DAYS.
      // If it was never linked, there's nothing to create in the first
      // place. Either way, non-recurring events never reach this branch.
      if (linkedId) {
        const existing = items.get(linkedId)
        if (existing) await deleteItem(existing, { skipGooglePush: true })
        await removeLink(linkedId)
      }
      continue
    }

    const existing = linkedId ? (items.get(linkedId) as EventItem | undefined) : undefined

    if (linkedId && !existing) {
      // Stale link: it points at an item that no longer exists locally
      // (deleted directly, or a push-back delete's Google-API call failed
      // AFTER the item was already removed but BEFORE removeLink ran —
      // deleteItem's push-back is fire-and-forget-with-a-toast, so the
      // item-delete itself "succeeds" from the user's POV even when this
      // half happens). Confirmed live: leaving it in place made every
      // subsequent sync pass try to create a fresh item for this event and
      // collide with this exact row on (connection_id, google_event_id) —
      // forever, not just once. Removing it here makes that self-healing
      // instead of a manual "go delete the dangling row" support ask.
      await removeLink(linkedId)
    }

    if (existing) {
      // Google's own `updated` timestamp, not ours — if this event hasn't
      // changed on Google's side since the link was last refreshed, there's
      // nothing to pull; re-applying it anyway would spuriously bump the
      // local item's updatedAt on every sync pass even when nothing changed.
      const link = useSyncStore.getState().googleLinks.get(linkedId!)
      if (link?.googleUpdatedAt && event.updated && event.updated <= link.googleUpdatedAt) continue
      // skipGooglePush: same reasoning as above — this update came FROM
      // Google, pushing it right back would be a no-op round trip at best.
      await updateItem(googleEventToItem(event, existing), { skipGooglePush: true })
      await saveLink(linkedId!, connection.id, event.id, event.updated, event.recurringEventId)
    } else {
      // No skipGooglePush needed here: addItem has no such option because
      // the link (saveLink, next line) doesn't exist yet at the moment this
      // runs, so updateItem's own googleLinks lookup would find nothing even
      // if this were routed through it — see updateItem's doc comment.
      const created = googleEventToItem(event)
      await addItem(created)
      await saveLink(created.id, connection.id, event.id, event.updated, event.recurringEventId)
    }
  }
}

/** One pass across EVERY connected Google account. allSettled, not
 *  Promise.all — one account's token being broken/revoked must not stop
 *  every OTHER connected account from syncing (same reasoning as
 *  DebugSection's bulk-delete fix). Failures are collected and thrown
 *  together so callers that want to know still can, without the
 *  first-connection-fails-blocks-everything problem. */
async function runSyncPass(): Promise<void> {
  const connections = await getConnections()
  if (connections.length === 0) return // nothing connected — not an error

  const results = await Promise.allSettled(connections.map((c) => syncOneConnection(c)))

  // Persist per-connection health so a dead refresh token shows up as a
  // "Reconnect" affordance in Settings instead of only a transient toast —
  // GoogleInvalidGrantError means Google itself rejected the refresh token
  // (expired/revoked), which no retry will fix; any other failure is
  // recorded for visibility but doesn't flag the connection as broken,
  // since it's more likely a transient network/API hiccup.
  await Promise.all(
    results.map((result, i) => {
      const connection = connections[i]
      if (result.status === 'fulfilled') {
        return connection.needsReauth || connection.lastSyncError
          ? markConnectionHealth(connection.id, { needsReauth: false, lastSyncError: null })
          : undefined
      }
      const isInvalidGrant = result.reason instanceof GoogleInvalidGrantError
      return markConnectionHealth(connection.id, {
        needsReauth: isInvalidGrant || connection.needsReauth,
        lastSyncError: errorMessage(result.reason),
      })
    }),
  )

  const failures = results
    .map((result, i) => ({ result, connection: connections[i] }))
    .filter((x): x is { result: PromiseRejectedResult; connection: GoogleConnection } => x.result.status === 'rejected')

  if (failures.length > 0) {
    // errorMessage(), not String(reason) — confirmed live: Supabase's
    // PostgrestError (thrown via `if (error) throw error` all over
    // connection.ts/links.ts) is a plain object, not an Error instance, so
    // String()-coercing it produced the literal useless "[object Object]"
    // in these logs — hiding the actual "column ... does not exist" message
    // that would have pointed straight at the real cause.
    const detail = failures.map((f) => `${f.connection.googleEmail ?? f.connection.id}: ${errorMessage(f.result.reason)}`).join('; ')
    throw new Error(`Sync failed for ${failures.length} of ${connections.length} account(s) — ${detail}`)
  }
}

// Confirmed live: the 5-minute poller firing while a manual "Sync now" (or
// React StrictMode's dev-only double-effect-mount) was still mid-flight let
// two passes race — both decided the same not-yet-linked Google event
// needed a new local item, both created one, and the second's saveLink()
// hit google_calendar_links_event_idx's unique constraint after the fact
// (5 duplicate LEO items for one Google event, confirmed against a real
// report). Coalescing concurrent callers onto the SAME in-flight promise
// closes the actual race for every same-tab trigger (poller vs. button vs.
// StrictMode) — it does not cover two separate browser TABS syncing at once,
// which would need a cross-tab/server-side lock; not attempted here since
// that's a much rarer case than the one actually hit.
let inFlightSync: Promise<void> | null = null

export function syncGoogleCalendar(): Promise<void> {
  if (!inFlightSync) {
    inFlightSync = runSyncPass().finally(() => {
      inFlightSync = null
    })
  }
  return inFlightSync
}

const POLL_INTERVAL_MS = 5 * 60_000
let intervalId: ReturnType<typeof setInterval> | null = null

function runSyncSilently() {
  syncGoogleCalendar().catch((err) => {
    console.error('[google-calendar] sync failed:', err)
  })
}

/** Mirrors alarms/scheduler.ts's start/stop shape. A browser tab has no
 *  background execution, same limitation as the alarm scheduler — this
 *  only runs while the tab is actually open. */
export function startGoogleCalendarSync(): void {
  if (intervalId) return
  runSyncSilently()
  intervalId = setInterval(runSyncSilently, POLL_INTERVAL_MS)
}

export function stopGoogleCalendarSync(): void {
  if (intervalId) clearInterval(intervalId)
  intervalId = null
}

/** Explicit "Sync now" — unlike the silent background poll, surfaces a
 *  failure so a broken connection (revoked access, expired refresh token)
 *  doesn't just fail quietly forever in the background. */
export async function syncGoogleCalendarNow(): Promise<void> {
  try {
    await syncGoogleCalendar()
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    toast.error("Couldn't sync Google Calendar", { description: message })
    throw err
  }
}
