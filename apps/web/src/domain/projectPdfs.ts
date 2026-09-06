import { supabase } from '@/lib/supabaseClient'
import { getDocument } from '@/lib/pdfjs'

/**
 * Per-project PDF library — same ad-hoc-table treatment as
 * domain/projectNotes.ts (fetched directly, not part of the sync engine),
 * keyed by (user_id, project_name). Bytes live in Storage bucket
 * 'project-pdfs' at '{user_id}/{id}.pdf' (see migration 0011); this module
 * owns both the metadata row and the matching Storage object together so
 * callers never have one without the other.
 */

export type ProjectPdf = {
  id: string
  projectName: string
  fileName: string
  storagePath: string
  sizeBytes: number
  pageCount: number | undefined
  createdAt: Date
  updatedAt: Date
}

type ProjectPdfRow = {
  id: string
  project_name: string
  file_name: string
  storage_path: string
  size_bytes: number
  page_count: number | null
  created_at: string
  updated_at: string
}

const COLUMNS = 'id, project_name, file_name, storage_path, size_bytes, page_count, created_at, updated_at'

function rowToPdf(row: ProjectPdfRow): ProjectPdf {
  return {
    id: row.id,
    projectName: row.project_name,
    fileName: row.file_name,
    storagePath: row.storage_path,
    sizeBytes: row.size_bytes,
    pageCount: row.page_count ?? undefined,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
  }
}

async function currentUserId(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user.id
  if (!userId) throw new Error('Not signed in')
  return userId
}

export async function listProjectPdfs(projectName: string): Promise<ProjectPdf[]> {
  const { data, error } = await supabase
    .from('project_pdfs')
    .select(COLUMNS)
    .eq('project_name', projectName)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data as ProjectPdfRow[]).map(rowToPdf)
}

export async function getProjectPdf(id: string): Promise<ProjectPdf | null> {
  const { data, error } = await supabase.from('project_pdfs').select(COLUMNS).eq('id', id).maybeSingle()
  if (error) throw error
  return data ? rowToPdf(data as ProjectPdfRow) : null
}

/** Counts pages by loading the file through pdf.js once — the only reason
 *  this needs the bytes client-side before the DB row exists at all. */
async function countPages(bytes: ArrayBuffer): Promise<number | undefined> {
  try {
    const doc = await getDocument({ data: bytes }).promise
    return doc.numPages
  } catch {
    return undefined
  }
}

/** Uploads to Storage first, then inserts the metadata row — if the row
 *  insert fails the orphaned Storage object is harmless (never referenced,
 *  cleaned up by re-upload or manual sweep) whereas the reverse order could
 *  leave a metadata row pointing at bytes that never landed. */
export async function uploadProjectPdf(projectName: string, file: File): Promise<ProjectPdf> {
  const userId = await currentUserId()
  const id = crypto.randomUUID()
  const storagePath = `${userId}/${id}.pdf`

  const bytes = await file.arrayBuffer()
  // pdf.js takes ownership of (and can detach) the buffer it's given, so
  // count pages from a copy — countPages() must never see the same buffer
  // that's about to be uploaded below, or the upload would send 0 bytes.
  const pageCount = await countPages(bytes.slice(0))

  const { error: uploadError } = await supabase.storage.from('project-pdfs').upload(storagePath, bytes, { contentType: 'application/pdf' })
  if (uploadError) throw uploadError

  const { data, error } = await supabase
    .from('project_pdfs')
    .insert({
      id,
      user_id: userId,
      project_name: projectName,
      file_name: file.name,
      storage_path: storagePath,
      size_bytes: file.size,
      page_count: pageCount ?? null,
    })
    .select(COLUMNS)
    .single()
  if (error) throw error
  return rowToPdf(data as ProjectPdfRow)
}

export async function deleteProjectPdf(pdf: ProjectPdf): Promise<void> {
  const { error: storageError } = await supabase.storage.from('project-pdfs').remove([pdf.storagePath])
  if (storageError) throw storageError
  const { error } = await supabase.from('project_pdfs').delete().eq('id', pdf.id)
  if (error) throw error
}

// Short-lived — regenerated per view/export rather than cached, since the
// bucket is private and there's no long-lived state to keep it in sync with.
const SIGNED_URL_TTL_SECONDS = 60 * 10

export async function getPdfSignedUrl(pdf: ProjectPdf): Promise<string> {
  const { data, error } = await supabase.storage.from('project-pdfs').createSignedUrl(pdf.storagePath, SIGNED_URL_TTL_SECONDS)
  if (error) throw error
  return data.signedUrl
}
