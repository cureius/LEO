import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { ArrowLeft, ChevronLeft, ChevronRight, Download, PanelRightClose, PanelRightOpen } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PdfViewer } from '@/components/pdf/PdfViewer'
import { HighlightsSidebar } from '@/components/pdf/HighlightsSidebar'
import { ProjectTasksPanel } from '@/components/pdf/ProjectTasksPanel'
import { ThemeSwitcher, loadPdfTheme, savePdfTheme, type PdfTheme } from '@/components/pdf/ThemeSwitcher'
import { getProjectPdf, type ProjectPdf } from '@/domain/projectPdfs'
import { addHighlight, listHighlights, type PdfHighlight } from '@/domain/pdfHighlights'
import { exportAnnotatedPdf } from '@/domain/pdfExport'

/** In-app reader for one PDF: continuous-scroll rendering (PdfViewer), a
 *  3-way reading theme, and a highlights sidebar. Highlighting and export
 *  are the point of this page — see PdfViewer.tsx for the render/selection
 *  mechanics and domain/pdfExport.ts for the "burn highlights into a real
 *  PDF copy" export. */
export function PdfViewerPage() {
  const { name, pdfId } = useParams<{ name: string; pdfId: string }>()
  const projectName = decodeURIComponent(name ?? '')

  const [pdf, setPdf] = useState<ProjectPdf | undefined>(undefined)
  const [highlights, setHighlights] = useState<PdfHighlight[]>([])
  const [page, setPage] = useState(1)
  const [numPages, setNumPages] = useState<number | undefined>(undefined)
  const [theme, setTheme] = useState<PdfTheme>(() => loadPdfTheme())
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [sidebarTab, setSidebarTab] = useState<'highlights' | 'tasks'>('highlights')
  const [exporting, setExporting] = useState(false)

  useEffect(() => {
    if (!pdfId) return
    let cancelled = false
    Promise.all([getProjectPdf(pdfId), listHighlights(pdfId)])
      .then(([loadedPdf, loadedHighlights]) => {
        if (cancelled) return
        setPdf(loadedPdf ?? undefined)
        setHighlights(loadedHighlights)
      })
      .catch((err) => toast.error("Couldn't load PDF", { description: err instanceof Error ? err.message : String(err) }))
    return () => {
      cancelled = true
    }
  }, [pdfId])

  function handleThemeChange(next: PdfTheme) {
    setTheme(next)
    savePdfTheme(next)
  }

  async function handleAddHighlight(input: Omit<Parameters<typeof addHighlight>[0], 'pdfId'>) {
    if (!pdf) return
    const created = await addHighlight({ ...input, pdfId: pdf.id })
    setHighlights((prev) => [...prev, created])
  }

  async function handleExport() {
    if (!pdf) return
    setExporting(true)
    try {
      await exportAnnotatedPdf(pdf, highlights)
    } catch (err) {
      toast.error("Couldn't export PDF", { description: err instanceof Error ? err.message : String(err) })
    } finally {
      setExporting(false)
    }
  }

  if (!pdf) {
    return <div className="p-6 text-sm text-text-secondary">{pdf === undefined ? 'Loading…' : 'PDF not found.'}</div>
  }

  return (
    <div className="flex h-screen flex-col">
      <div className="flex items-center justify-between gap-3 border-b border-divider bg-surface px-4 py-2">
        <div className="flex min-w-0 items-center gap-3">
          <Link
            to={`/projects/${encodeURIComponent(projectName)}/pdfs`}
            className="inline-flex shrink-0 items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
          >
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            PDFs
          </Link>
          <span className="truncate text-sm font-medium text-text-primary">{pdf.fileName}</span>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1">
            <Button type="button" size="icon-sm" variant="ghost" disabled={page <= 1} onClick={() => setPage((p) => p - 1)} aria-label="Previous page">
              <ChevronLeft className="h-4 w-4" aria-hidden="true" />
            </Button>
            <span className="min-w-16 text-center text-xs text-text-secondary">
              {page} / {numPages ?? pdf.pageCount ?? '…'}
            </span>
            <Button
              type="button"
              size="icon-sm"
              variant="ghost"
              disabled={numPages !== undefined && page >= numPages}
              onClick={() => setPage((p) => p + 1)}
              aria-label="Next page"
            >
              <ChevronRight className="h-4 w-4" aria-hidden="true" />
            </Button>
          </div>

          <ThemeSwitcher value={theme} onChange={handleThemeChange} />

          <Button type="button" size="sm" variant="outline" disabled={exporting} onClick={() => void handleExport()}>
            <Download className="h-3.5 w-3.5" aria-hidden="true" />
            {exporting ? 'Exporting…' : 'Export'}
          </Button>

          <Button type="button" size="icon-sm" variant="ghost" onClick={() => setSidebarOpen((v) => !v)} aria-label="Toggle sidebar">
            {sidebarOpen ? <PanelRightClose className="h-4 w-4" aria-hidden="true" /> : <PanelRightOpen className="h-4 w-4" aria-hidden="true" />}
          </Button>
        </div>
      </div>

      <div className="flex min-h-0 flex-1">
        <div className="h-full min-w-0 flex-1">
          <PdfViewer
            pdf={pdf}
            theme={theme}
            page={page}
            onNumPages={setNumPages}
            onPageChange={setPage}
            highlights={highlights}
            onAddHighlight={handleAddHighlight}
          />
        </div>
        {sidebarOpen && (
          <div className="flex w-96 shrink-0 flex-col border-l border-divider bg-surface">
            <div className="flex gap-0.5 border-b border-divider p-2">
              <Button type="button" size="sm" variant={sidebarTab === 'highlights' ? 'default' : 'ghost'} onClick={() => setSidebarTab('highlights')}>
                Highlights{highlights.length > 0 ? ` (${highlights.length})` : ''}
              </Button>
              <Button type="button" size="sm" variant={sidebarTab === 'tasks' ? 'default' : 'ghost'} onClick={() => setSidebarTab('tasks')}>
                Tasks
              </Button>
            </div>
            <div className="min-h-0 flex-1">
              {sidebarTab === 'highlights' ? (
                <HighlightsSidebar highlights={highlights} onJumpToPage={setPage} onChanged={setHighlights} />
              ) : (
                <ProjectTasksPanel projectName={projectName} />
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
