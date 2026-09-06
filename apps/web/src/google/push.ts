import { getValidAccessToken, getConnectionById } from './connection'
import { updateGoogleEvent, deleteGoogleEvent } from './calendarApi'
import { itemToGoogleEvent } from './mapping'
import { saveLink, removeLink } from './links'
import { useSyncStore } from '@/sync/store'
import type { EventItem } from '@/domain/types'

/**
 * Push-back half of two-way sync — called from sync/mutations.ts's
 * updateItem/deleteItem whenever the item being written has a Google link.
 * Deliberately its own module rather than living in google/sync.ts: sync.ts
 * (the pull side) needs to call addItem/updateItem/deleteItem FROM
 * mutations.ts, and mutations.ts needs to call these push functions — put
 * both directions in one file and that's a circular import between
 * mutations.ts and google/sync.ts. This module only touches
 * connection/calendarApi/links/store, never mutations.ts, so both sides can
 * import it without a cycle.
 */

export async function pushEventUpdateToGoogle(item: EventItem): Promise<void> {
  const link = useSyncStore.getState().googleLinks.get(item.id)
  if (!link) return

  const connection = await getConnectionById(link.connectionId)
  if (!connection) return // that account was disconnected since this item was linked — nothing to push to

  const accessToken = await getValidAccessToken(connection)
  const updated = await updateGoogleEvent(accessToken, connection.calendarId, link.googleEventId, itemToGoogleEvent(item))
  await saveLink(item.id, link.connectionId, link.googleEventId, updated.updated)
}

export async function pushEventDeleteToGoogle(itemId: string): Promise<void> {
  const link = useSyncStore.getState().googleLinks.get(itemId)
  if (!link) return

  const connection = await getConnectionById(link.connectionId)
  if (!connection) return

  const accessToken = await getValidAccessToken(connection)
  await deleteGoogleEvent(accessToken, connection.calendarId, link.googleEventId)
  await removeLink(itemId)
}
