import { useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import { getDocument, TextLayer, type PDFDocumentProxy, type PDFPageProxy } from '@/lib/pdfjs'
import { getPdfSignedUrl, type ProjectPdf } from '@/domain/projectPdfs'
import type { HighlightColor, HighlightRect, PdfHighlight } from '@/domain/pdfHighlights'
import { HighlightColorSwatch } from '@/components/pdf/HighlightColorSwatch'
import { PDF_THEME_FILTERS, type PdfTheme } from '@/components/pdf/ThemeSwitcher'
import '@/components/pdf/pdfTextLayer.css'

const SCALE = 1.5

// Highlight marks live OUTSIDE the theme-filtered layer (see the render
// below) so Night's invert(1) hue-rotate(180deg) never touches them —
// inside it, yellow/green/blue/pink all got rotated into washed-out,
// barely-distinguishable colors. Night also needs its OWN palette, not
// just the light one with a blend trick: Night's page text renders
// near-white (it's inverted black-on-white), and a bright pastel highlight
// behind white text is a low-contrast pairing regardless of how it's
// composited (tried mix-blend-mode: screen — technically brighter, but
// white-on-bright-yellow is still hard to read). A dark, saturated fill
// reads correctly instead — but a flat fill alone made the 4 colors hard
// to tell apart at a glance (dark amber vs. dark rose look similar in low
// light), so Night also gets a bright bottom border in the true hue: the
// fill carries contrast, the border carries color identity.
const HIGHLIGHT_BG: Record<PdfTheme, Record<HighlightColor, string>> = {
  light: {
    yellow: 'rgba(250, 204, 21, 0.45)',
    green: 'rgba(74, 222, 128, 0.45)',
    blue: 'rgba(96, 165, 250, 0.45)',
    pink: 'rgba(244, 114, 182, 0.45)',
  },
  sepia: {
    yellow: 'rgba(250, 204, 21, 0.45)',
    green: 'rgba(74, 222, 128, 0.45)',
    blue: 'rgba(96, 165, 250, 0.45)',
    pink: 'rgba(244, 114, 182, 0.45)',
  },
  night: {
    yellow: 'rgba(133, 77, 14, 0.55)',
    green: 'rgba(6, 95, 70, 0.55)',
    blue: 'rgba(29, 78, 216, 0.55)',
    pink: 'rgba(157, 23, 77, 0.55)',
  },
}

const HIGHLIGHT_BORDER_NIGHT: Record<HighlightColor, string> = {
  yellow: 'rgb(250, 204, 21)',
  green: 'rgb(52, 211, 153)',
  blue: 'rgb(96, 165, 250)',
  pink: 'rgb(244, 114, 182)',
}

type PendingSelection = { rects: HighlightRect[]; quote: string; x: number; y: number }

// How far outside the viewport a page is pre-rendered, so scrolling never
// shows a blank flash — big enough to cover a fast scroll-wheel flick.
const RENDER_ROOT_MARGIN = '1200px 0px'

/** Renders one page of `pdf` (via pdf.js) with a persisted highlight overlay
 *  and a native text-selection layer for making new highlights. Coordinates
 *  are normalized to page fractions (0..1) so they survive across renders
 *  at a different scale — see domain/pdfHighlights.ts. */
export function PdfViewer({
  pdf,
  theme,
  page,
  onNumPages,
  onPageChange,
  highlights,
  onAddHighlight,
}: {
  pdf: ProjectPdf
  theme: PdfTheme
  page: number
  onNumPages: (n: number) => void
  onPageChange: (n: number) => void
  highlights: PdfHighlight[]
  onAddHighlight: (input: { pageNumber: number; rects: HighlightRect[]; color: HighlightColor; quote: string }) => Promise<void>
}) {
  const [doc, setDoc] = useState<PDFDocumentProxy | undefined>(undefined)
  const [numPages, setNumPages] = useState(0)
  const containerRef = useRef<HTMLDivElement>(null)
  const pageElsRef = useRef<Map<number, HTMLDivElement>>(new Map())
  const lastReportedPageRef = useRef(1)
  const ignoreObserverUntilRef = useRef(0)

  useEffect(() => {
    let cancelled = false
    getPdfSignedUrl(pdf)
      .then((url) => getDocument({ url }).promise)
      .then((loaded) => {
        if (cancelled) return
        setDoc(loaded)
        setNumPages(loaded.numPages)
        onNumPages(loaded.numPages)
      })
      .catch((err) => toast.error("Couldn't open PDF", { description: err instanceof Error ? err.message : String(err) }))
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pdf.id])

  // Tracks which page is most visible while the user scrolls, and reports
  // it up so the header's page indicator / prev-next buttons stay in sync.
  useEffect(() => {
    const container = containerRef.current
    if (!doc || numPages === 0 || !container) return

    const ratios = new Map<number, number>()
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const n = Number((entry.target as HTMLElement).dataset.page)
          ratios.set(n, entry.isIntersecting ? entry.intersectionRatio : 0)
        }
        if (Date.now() < ignoreObserverUntilRef.current) return
        let best = lastReportedPageRef.current
        let bestRatio = 0
        for (const [n, r] of ratios) {
          if (r > bestRatio) {
            bestRatio = r
            best = n
          }
        }
        if (bestRatio > 0 && best !== lastReportedPageRef.current) {
          lastReportedPageRef.current = best
          onPageChange(best)
        }
      },
      { root: container, threshold: [0, 0.25, 0.5, 0.75, 1] },
    )
    for (const el of pageElsRef.current.values()) observer.observe(el)
    return () => observer.disconnect()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [doc, numPages])

  // Scrolls to `page` when it changes from outside (prev/next buttons, a
  // highlight jump) — but not when it's just an echo of our own scroll.
  useEffect(() => {
    if (page === lastReportedPageRef.current) return
    const el = pageElsRef.current.get(page)
    if (!el) return
    ignoreObserverUntilRef.current = Date.now() + 700
    lastReportedPageRef.current = page
    el.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [page])

  if (!doc) {
    return <div className="h-full overflow-auto bg-surface-elevated p-6" />
  }

  return (
    <div ref={containerRef} className="h-full overflow-auto bg-surface-elevated p-6">
      <div className="flex flex-col items-center gap-6">
        {Array.from({ length: numPages }, (_, i) => i + 1).map((pageNumber) => (
          <PdfPage
            key={pageNumber}
            doc={doc}
            pageNumber={pageNumber}
            theme={theme}
            highlights={highlights.filter((h) => h.pageNumber === pageNumber)}
            onAddHighlight={onAddHighlight}
            registerEl={(el) => {
              if (el) pageElsRef.current.set(pageNumber, el)
              else pageElsRef.current.delete(pageNumber)
            }}
          />
        ))}
      </div>
    </div>
  )
}

function PdfPage({
  doc,
  pageNumber,
  theme,
  highlights,
  onAddHighlight,
  registerEl,
}: {
  doc: PDFDocumentProxy
  pageNumber: number
  theme: PdfTheme
  highlights: PdfHighlight[]
  onAddHighlight: (input: { pageNumber: number; rects: HighlightRect[]; color: HighlightColor; quote: string }) => Promise<void>
  registerEl: (el: HTMLDivElement | null) => void
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const textLayerRef = useRef<HTMLDivElement>(null)
  const pageContainerRef = useRef<HTMLDivElement>(null)
  const [pageSize, setPageSize] = useState({ width: 0, height: 0 })
  const [pending, setPending] = useState<PendingSelection | undefined>(undefined)
  const [shouldRender, setShouldRender] = useState(false)

  function setContainerEl(el: HTMLDivElement | null) {
    pageContainerRef.current = el
    registerEl(el)
  }

  // Lazily renders the page once it (or its RENDER_ROOT_MARGIN buffer)
  // scrolls into view, so a long PDF doesn't render every page up front.
  useEffect(() => {
    const el = pageContainerRef.current
    if (!el || shouldRender) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) setShouldRender(true)
      },
      { rootMargin: RENDER_ROOT_MARGIN },
    )
    observer.observe(el)
    return () => observer.disconnect()
  }, [shouldRender])

  useEffect(() => {
    if (!shouldRender) return
    let cancelled = false
    let pdfPage: PDFPageProxy | undefined

    async function render() {
      pdfPage = await doc.getPage(pageNumber)
      if (cancelled) return
      const viewport = pdfPage.getViewport({ scale: SCALE })

      const canvas = canvasRef.current
      const textLayerEl = textLayerRef.current
      if (!canvas || !textLayerEl) return
      canvas.width = viewport.width
      canvas.height = viewport.height
      setPageSize({ width: viewport.width, height: viewport.height })

      const ctx = canvas.getContext('2d')
      if (!ctx) return
      await pdfPage.render({ canvas, canvasContext: ctx, viewport }).promise
      if (cancelled) return

      textLayerEl.replaceChildren()
      textLayerEl.style.setProperty('--scale-factor', String(viewport.scale))
      textLayerEl.style.setProperty('--total-scale-factor', String(viewport.scale))
      const textLayer = new TextLayer({ textContentSource: pdfPage.streamTextContent(), container: textLayerEl, viewport })
      await textLayer.render()
    }

    render().catch((err) => toast.error("Couldn't render page", { description: err instanceof Error ? err.message : String(err) }))
    return () => {
      cancelled = true
    }
  }, [doc, pageNumber, shouldRender])

  function handleMouseUp() {
    const selection = window.getSelection()
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return
    const quote = selection.toString().trim()
    if (!quote) return
    const container = pageContainerRef.current
    if (!container) return
    const containerRect = container.getBoundingClientRect()
    if (containerRect.width === 0 || containerRect.height === 0) return

    const range = selection.getRangeAt(0)
    const clientRects = Array.from(range.getClientRects())
    const rects: HighlightRect[] = clientRects
      .filter((r) => r.width > 0 && r.height > 0)
      .map((r) => ({
        x: (r.left - containerRect.left) / containerRect.width,
        y: (r.top - containerRect.top) / containerRect.height,
        width: r.width / containerRect.width,
        height: r.height / containerRect.height,
      }))
    if (rects.length === 0) return
    if (!container.contains(range.commonAncestorContainer)) return

    const last = clientRects[clientRects.length - 1]
    setPending({ rects, quote, x: last.right - containerRect.left, y: last.top - containerRect.top })
  }

  async function pickColor(color: HighlightColor) {
    if (!pending) return
    const { rects, quote } = pending
    setPending(undefined)
    window.getSelection()?.removeAllRanges()
    try {
      await onAddHighlight({ pageNumber, rects, color, quote })
    } catch (err) {
      toast.error("Couldn't save highlight", { description: err instanceof Error ? err.message : String(err) })
    }
  }

  return (
    <div
      ref={setContainerEl}
      data-page={pageNumber}
      onMouseUp={handleMouseUp}
      className="relative shadow-md"
      style={shouldRender ? { width: pageSize.width, height: pageSize.height } : { width: '100%', maxWidth: 850, aspectRatio: '1 / 1.294' }}
    >
      {shouldRender && (
        <>
          <div className="absolute inset-0" style={{ filter: PDF_THEME_FILTERS[theme] }}>
            <canvas ref={canvasRef} />
            <div ref={textLayerRef} className="textLayer" />
          </div>

          {highlights.map((h) =>
            h.rects.map((r, i) => (
              <div
                key={`${h.id}-${i}`}
                title={h.note ?? h.quote}
                className="pointer-events-none absolute rounded-[2px]"
                style={{
                  left: `${r.x * 100}%`,
                  top: `${r.y * 100}%`,
                  width: `${r.width * 100}%`,
                  height: `${r.height * 100}%`,
                  backgroundColor: HIGHLIGHT_BG[theme][h.color],
                  borderBottom: theme === 'night' ? `2px solid ${HIGHLIGHT_BORDER_NIGHT[h.color]}` : undefined,
                }}
              />
            )),
          )}

          {pending && (
            <div
              className="absolute z-10 -translate-y-full rounded-md border border-divider bg-popover p-1.5 shadow-md"
              style={{ left: pending.x, top: pending.y }}
            >
              <HighlightColorSwatch value="yellow" onChange={(color) => void pickColor(color)} />
            </div>
          )}
        </>
      )}
    </div>
  )
}
