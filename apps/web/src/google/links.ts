import { supabase } from '@/lib/supabaseClient'
import { useSyncStore } from '@/sync/store'

type LinkRow = {
  item_id: string
  connection_id: string
  google_event_id: string
  google_updated_at: string | null
  google_recurring_event_id: string | null
}

/** Populates the store's googleLinks cache from Supabase — called once on
 *  app load (see AppShell.tsx), same shape as the initial items/habits
 *  fetch in sync/engine.ts but kept separate since this table has nothing
 *  to do with the core item sync path. */
export async function loadGoogleLinks(): Promise<void> {
  const { data, error } = await supabase
    .from('google_calendar_links')
    .select('item_id, connection_id, google_event_id, google_updated_at, google_recurring_event_id')
  if (error) throw error
  const store = useSyncStore.getState()
  for (const row of data as LinkRow[]) {
    store.upsertGoogleLink(row.item_id, {
      connectionId: row.connection_id,
      googleEventId: row.google_event_id,
      googleUpdatedAt: row.google_updated_at ?? undefined,
      googleRecurringEventId: row.google_recurring_event_id ?? undefined,
    })
  }
}

/** Scoped to ONE connection — event ids are only unique per Google account
 *  (see migration 0004's unique index), so matching across every connected
 *  account risks pairing an event with the wrong one if two accounts ever
 *  produced colliding ids. */
export function findLinkedItemId(connectionId: string, googleEventId: string): string | undefined {
  const links = useSyncStore.getState().googleLinks
  for (const [itemId, link] of links) {
    if (link.connectionId === connectionId && link.googleEventId === googleEventId) return itemId
  }
  return undefined
}

async function currentUserId(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user.id
  if (!userId) throw new Error('Not signed in')
  return userId
}

export async function saveLink(
  itemId: string,
  connectionId: string,
  googleEventId: string,
  googleUpdatedAt?: string,
  googleRecurringEventId?: string,
): Promise<void> {
  const userId = await currentUserId()
  const { error } = await supabase.from('google_calendar_links').upsert({
    item_id: itemId,
    user_id: userId,
    connection_id: connectionId,
    google_event_id: googleEventId,
    google_updated_at: googleUpdatedAt ?? null,
    google_recurring_event_id: googleRecurringEventId ?? null,
  })
  if (error) throw error
  useSyncStore.getState().upsertGoogleLink(itemId, { connectionId, googleEventId, googleUpdatedAt, googleRecurringEventId })
}

export async function removeLink(itemId: string): Promise<void> {
  const { error } = await supabase.from('google_calendar_links').delete().eq('item_id', itemId)
  if (error) throw error
  useSyncStore.getState().removeGoogleLink(itemId)
}

/** Every link for ONE connection, gone in one shot — used when
 *  disconnecting that account: the mapping is meaningless without a
 *  connection to push against, and leaving stale rows around would make a
 *  future reconnect see "already linked" for events that were never
 *  touched during the disconnected period. Scoped to connectionId, not the
 *  whole user, so disconnecting one account never touches another
 *  connected account's links. */
export async function removeLinksForConnection(connectionId: string): Promise<void> {
  const { error } = await supabase.from('google_calendar_links').delete().eq('connection_id', connectionId)
  if (error) throw error
  const store = useSyncStore.getState()
  for (const [itemId, link] of store.googleLinks) {
    if (link.connectionId === connectionId) store.removeGoogleLink(itemId)
  }
}
