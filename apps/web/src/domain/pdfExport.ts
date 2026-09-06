import { PDFDocument, rgb } from 'pdf-lib'
import type { ProjectPdf } from '@/domain/projectPdfs'
import { getPdfSignedUrl } from '@/domain/projectPdfs'
import type { HighlightColor, PdfHighlight } from '@/domain/pdfHighlights'

// Same 4 swatches as HighlightColorSwatch.tsx, in pdf-lib's 0..1 rgb() — kept
// as a separate map since that component deals in Tailwind classes, not
// float triples.
const HIGHLIGHT_RGB: Record<HighlightColor, ReturnType<typeof rgb>> = {
  yellow: rgb(0.98, 0.85, 0.15),
  green: rgb(0.4, 0.85, 0.45),
  blue: rgb(0.4, 0.7, 0.98),
  pink: rgb(0.98, 0.6, 0.75),
}

const HIGHLIGHT_OPACITY = 0.4

/** Downloads a copy of `pdf` with every highlight burned in as a translucent
 *  rectangle on its page. Rects are stored as page fractions (0..1,
 *  top-left origin — see domain/pdfHighlights.ts); pdf-lib's page space is
 *  points with a bottom-left origin, so y flips per rect. */
export async function exportAnnotatedPdf(pdf: ProjectPdf, highlights: PdfHighlight[]): Promise<void> {
  const signedUrl = await getPdfSignedUrl(pdf)
  const bytes = await fetch(signedUrl).then((r) => r.arrayBuffer())
  const doc = await PDFDocument.load(bytes)
  const pages = doc.getPages()

  for (const highlight of highlights) {
    const page = pages[highlight.pageNumber - 1]
    if (!page) continue
    const { width: pageWidth, height: pageHeight } = page.getSize()
    const color = HIGHLIGHT_RGB[highlight.color] ?? HIGHLIGHT_RGB.yellow

    for (const rect of highlight.rects) {
      page.drawRectangle({
        x: rect.x * pageWidth,
        y: pageHeight - (rect.y + rect.height) * pageHeight,
        width: rect.width * pageWidth,
        height: rect.height * pageHeight,
        color,
        opacity: HIGHLIGHT_OPACITY,
      })
    }
  }

  const outBytes = await doc.save()
  const blob = new Blob([outBytes.buffer as ArrayBuffer], { type: 'application/pdf' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = pdf.fileName.replace(/\.pdf$/i, '') + ' (highlighted).pdf'
  a.click()
  URL.revokeObjectURL(url)
}
