import { supabase } from '@/lib/supabaseClient'

/** One highlighted passage on one page of a project_pdfs row (migration
 *  0011). Rects are fractions (0..1, top-left origin) of the rendered page,
 *  independent of zoom/scale — see PdfViewer.tsx for how a text selection
 *  is turned into these, and domain/pdfExport.ts for how they're mapped
 *  onto pdf-lib's bottom-left-origin page space for the annotated export. */

export const HIGHLIGHT_COLORS = ['yellow', 'green', 'blue', 'pink'] as const
export type HighlightColor = (typeof HIGHLIGHT_COLORS)[number]

export type HighlightRect = { x: number; y: number; width: number; height: number }

export type PdfHighlight = {
  id: string
  pdfId: string
  pageNumber: number
  rects: HighlightRect[]
  color: HighlightColor
  quote: string
  note: string | undefined
  createdAt: Date
}

type PdfHighlightRow = {
  id: string
  pdf_id: string
  page_number: number
  rects: HighlightRect[]
  color: string
  quote: string
  note: string | null
  created_at: string
}

const COLUMNS = 'id, pdf_id, page_number, rects, color, quote, note, created_at'

function rowToHighlight(row: PdfHighlightRow): PdfHighlight {
  return {
    id: row.id,
    pdfId: row.pdf_id,
    pageNumber: row.page_number,
    rects: row.rects,
    color: (HIGHLIGHT_COLORS as readonly string[]).includes(row.color) ? (row.color as HighlightColor) : 'yellow',
    quote: row.quote,
    note: row.note ?? undefined,
    createdAt: new Date(row.created_at),
  }
}

async function currentUserId(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const userId = data.session?.user.id
  if (!userId) throw new Error('Not signed in')
  return userId
}

export async function listHighlights(pdfId: string): Promise<PdfHighlight[]> {
  const { data, error } = await supabase.from('pdf_highlights').select(COLUMNS).eq('pdf_id', pdfId).order('page_number', { ascending: true })
  if (error) throw error
  return (data as PdfHighlightRow[]).map(rowToHighlight)
}

export async function addHighlight(input: {
  pdfId: string
  pageNumber: number
  rects: HighlightRect[]
  color: HighlightColor
  quote: string
}): Promise<PdfHighlight> {
  const userId = await currentUserId()
  const { data, error } = await supabase
    .from('pdf_highlights')
    .insert({
      user_id: userId,
      pdf_id: input.pdfId,
      page_number: input.pageNumber,
      rects: input.rects,
      color: input.color,
      quote: input.quote,
    })
    .select(COLUMNS)
    .single()
  if (error) throw error
  return rowToHighlight(data as PdfHighlightRow)
}

export async function updateHighlightNote(id: string, note: string): Promise<void> {
  const { error } = await supabase.from('pdf_highlights').update({ note: note.trim() || null }).eq('id', id)
  if (error) throw error
}

export async function deleteHighlight(id: string): Promise<void> {
  const { error } = await supabase.from('pdf_highlights').delete().eq('id', id)
  if (error) throw error
}
