import { supabase } from '@/lib/supabaseClient'

/**
 * One Jira connection per user — an Atlassian API token, not OAuth (see
 * api/jira-search.ts's doc comment for why that's the right tradeoff here).
 * Read-only, one-way: this module only ever reads/writes the connection
 * itself; actual issue data is never persisted (see jira/api.ts), fetched
 * fresh on every visit to the Jira page.
 */

export type JiraConnection = {
  siteUrl: string
  email: string
  apiToken: string
}

type ConnectionRow = {
  site_url: string
  email: string
  api_token: string
}

function rowToConnection(row: ConnectionRow): JiraConnection {
  return { siteUrl: row.site_url, email: row.email, apiToken: row.api_token }
}

/** Strips a scheme/trailing slash a user might paste in (e.g.
 *  "https://yourteam.atlassian.net/") down to the bare host the proxy's
 *  SITE_URL_PATTERN expects. */
export function normalizeSiteUrl(input: string): string {
  return input.trim().replace(/^https?:\/\//i, '').replace(/\/+$/, '')
}

export async function getJiraConnection(): Promise<JiraConnection | null> {
  const { data, error } = await supabase.from('jira_connections').select('site_url, email, api_token').maybeSingle()
  if (error) throw error
  return data ? rowToConnection(data as ConnectionRow) : null
}

export async function saveJiraConnection(connection: JiraConnection): Promise<void> {
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')

  const { error } = await supabase
    .from('jira_connections')
    .upsert({ user_id: userId, site_url: connection.siteUrl, email: connection.email, api_token: connection.apiToken }, { onConflict: 'user_id' })
  if (error) throw error
}

export async function disconnectJira(): Promise<void> {
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')

  const { error } = await supabase.from('jira_connections').delete().eq('user_id', userId)
  if (error) throw error
}
