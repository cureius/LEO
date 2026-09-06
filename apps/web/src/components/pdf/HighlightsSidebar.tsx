import { useState } from 'react'
import { toast } from 'sonner'
import { Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { deleteHighlight, updateHighlightNote, type PdfHighlight } from '@/domain/pdfHighlights'

const DOT_CLASSES: Record<string, string> = {
  yellow: 'bg-yellow-400',
  green: 'bg-green-400',
  blue: 'bg-blue-400',
  pink: 'bg-pink-400',
}

export function HighlightsSidebar({
  highlights,
  onJumpToPage,
  onChanged,
}: {
  highlights: PdfHighlight[]
  onJumpToPage: (page: number) => void
  onChanged: (highlights: PdfHighlight[]) => void
}) {
  const [editingId, setEditingId] = useState<string | undefined>(undefined)
  const [draftNote, setDraftNote] = useState('')

  async function handleDelete(id: string) {
    try {
      await deleteHighlight(id)
      onChanged(highlights.filter((h) => h.id !== id))
    } catch (err) {
      toast.error("Couldn't delete highlight", { description: err instanceof Error ? err.message : String(err) })
    }
  }

  async function handleSaveNote(id: string) {
    try {
      await updateHighlightNote(id, draftNote)
      onChanged(highlights.map((h) => (h.id === id ? { ...h, note: draftNote.trim() || undefined } : h)))
      setEditingId(undefined)
    } catch (err) {
      toast.error("Couldn't save note", { description: err instanceof Error ? err.message : String(err) })
    }
  }

  if (highlights.length === 0) {
    return <p className="h-full p-4 text-sm text-text-secondary">Select text in the PDF to add a highlight.</p>
  }

  return (
    <div className="flex h-full flex-col gap-3 overflow-y-auto p-4">
      {highlights.map((h) => (
        <div key={h.id} className="rounded-leo-md border border-divider bg-surface p-3">
          <div className="mb-1 flex items-center justify-between gap-2">
            <button
              type="button"
              onClick={() => onJumpToPage(h.pageNumber)}
              className="flex items-center gap-1.5 text-xs text-text-secondary hover:text-text-primary"
            >
              <span className={`h-2.5 w-2.5 rounded-full ${DOT_CLASSES[h.color] ?? 'bg-yellow-400'}`} />
              Page {h.pageNumber}
            </button>
            <Button type="button" size="icon-xs" variant="ghost" onClick={() => void handleDelete(h.id)} aria-label="Delete highlight">
              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
            </Button>
          </div>
          <p className="line-clamp-3 text-sm text-text-primary">"{h.quote}"</p>

          {editingId === h.id ? (
            <div className="mt-2 flex flex-col gap-1.5">
              <Textarea value={draftNote} onChange={(e) => setDraftNote(e.target.value)} rows={2} placeholder="Add a note…" />
              <div className="flex gap-1.5">
                <Button type="button" size="xs" onClick={() => void handleSaveNote(h.id)}>
                  Save
                </Button>
                <Button type="button" size="xs" variant="ghost" onClick={() => setEditingId(undefined)}>
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => {
                setEditingId(h.id)
                setDraftNote(h.note ?? '')
              }}
              className="mt-1 text-xs text-text-secondary hover:text-text-primary"
            >
              {h.note ? h.note : 'Add note'}
            </button>
          )}
        </div>
      ))}
    </div>
  )
}
