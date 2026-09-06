import { supabase } from '@/lib/supabaseClient'

/**
 * One markdown doc per (user, project name) — see migration
 * 0009_project_notes.sql's doc comment for why this is a separate table
 * rather than a field on the tag itself (there's no tag registry row to put
 * it on). Fetched ad hoc by ProjectDetailPage, not part of the sync engine —
 * same treatment as google/connection.ts's Google Calendar connections.
 */

export async function getProjectNotes(projectName: string): Promise<string> {
  const { data, error } = await supabase.from('project_notes').select('notes').eq('project_name', projectName).maybeSingle()
  if (error) throw error
  return data?.notes ?? ''
}

export async function saveProjectNotes(projectName: string, notes: string): Promise<void> {
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) throw new Error('Not signed in')

  const { error } = await supabase.from('project_notes').upsert({ user_id: userId, project_name: projectName, notes }, { onConflict: 'user_id,project_name' })
  if (error) throw error
}
