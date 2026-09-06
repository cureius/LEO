import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowLeft, FileText, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PdfUploadButton } from '@/components/pdf/PdfUploadButton'
import { deleteProjectPdf, listProjectPdfs, type ProjectPdf } from '@/domain/projectPdfs'

function formatSize(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function formatUploadedAt(date: Date): string {
  return date.toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

/** A project's PDF library — upload, browse, open in the in-app reader
 *  (PdfViewerPage), or delete. Reached from ProjectDetailPage's header link.
 *  Files and metadata live in Supabase (Storage bucket + project_pdfs
 *  table, migration 0011) via domain/projectPdfs.ts — same "ad hoc, outside
 *  the sync engine" treatment as project notes. */
export function ProjectPdfsPage() {
  const { name } = useParams<{ name: string }>()
  const projectName = decodeURIComponent(name ?? '')
  const navigate = useNavigate()

  const [pdfs, setPdfs] = useState<ProjectPdf[] | undefined>(undefined)
  const [deletingId, setDeletingId] = useState<string | undefined>(undefined)

  useEffect(() => {
    let cancelled = false
    listProjectPdfs(projectName)
      .then((result) => {
        if (!cancelled) setPdfs(result)
      })
      .catch((err) => {
        if (!cancelled) toast.error("Couldn't load PDFs", { description: err instanceof Error ? err.message : String(err) })
      })
    return () => {
      cancelled = true
    }
  }, [projectName])

  async function handleDelete(pdf: ProjectPdf) {
    setDeletingId(pdf.id)
    try {
      await deleteProjectPdf(pdf)
      setPdfs((prev) => prev?.filter((p) => p.id !== pdf.id))
    } catch (err) {
      toast.error("Couldn't delete PDF", { description: err instanceof Error ? err.message : String(err) })
    } finally {
      setDeletingId(undefined)
    }
  }

  return (
    <div className="p-6">
      <Link
        to={`/projects/${encodeURIComponent(projectName)}`}
        className="mb-3 inline-flex w-fit items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
      >
        <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
        {projectName}
      </Link>

      <div className="mb-4 flex items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-text-primary">PDFs</h1>
        <PdfUploadButton projectName={projectName} onUploaded={(pdf) => setPdfs((prev) => [pdf, ...(prev ?? [])])} />
      </div>

      {pdfs === undefined && <p className="text-sm text-text-secondary">Loading…</p>}
      {pdfs?.length === 0 && <p className="text-sm text-text-secondary">No PDFs uploaded to "{projectName}" yet.</p>}

      {pdfs && pdfs.length > 0 && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {pdfs.map((pdf) => (
            <div
              key={pdf.id}
              role="button"
              tabIndex={0}
              onClick={() => navigate(`/projects/${encodeURIComponent(projectName)}/pdfs/${pdf.id}`)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') navigate(`/projects/${encodeURIComponent(projectName)}/pdfs/${pdf.id}`)
              }}
              className="flex cursor-pointer flex-col gap-2 rounded-leo-md border border-divider bg-surface p-4 text-left hover:border-accent"
            >
              <div className="flex items-start justify-between gap-2">
                <FileText className="h-5 w-5 shrink-0 text-text-secondary" aria-hidden="true" />
                <Button
                  type="button"
                  size="icon-xs"
                  variant="ghost"
                  disabled={deletingId === pdf.id}
                  onClick={(e) => {
                    e.stopPropagation()
                    void handleDelete(pdf)
                  }}
                  aria-label={`Delete ${pdf.fileName}`}
                >
                  <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                </Button>
              </div>
              <p className="truncate text-sm font-medium text-text-primary" title={pdf.fileName}>
                {pdf.fileName}
              </p>
              <p className="text-xs text-text-secondary">
                {pdf.pageCount ? `${pdf.pageCount} page${pdf.pageCount === 1 ? '' : 's'} · ` : ''}
                {formatSize(pdf.sizeBytes)}
              </p>
              <p className="text-xs text-text-secondary">Uploaded {formatUploadedAt(pdf.createdAt)}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
