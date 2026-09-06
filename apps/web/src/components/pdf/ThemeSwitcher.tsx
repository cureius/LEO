import { Button } from '@/components/ui/button'

export const PDF_THEMES = ['light', 'sepia', 'night'] as const
export type PdfTheme = (typeof PDF_THEMES)[number]

const THEME_LABELS: Record<PdfTheme, string> = { light: 'Light', sepia: 'Sepia', night: 'Night' }

/** CSS filter applied to the page-canvas container. `night` inverts the
 *  rendered page and re-inverts the hue so a white page becomes a genuine
 *  dark page (not just dimmed white) — the standard PDF-reader night trick. */
export const PDF_THEME_FILTERS: Record<PdfTheme, string> = {
  light: 'none',
  sepia: 'sepia(0.6) brightness(0.95)',
  night: 'invert(1) hue-rotate(180deg) brightness(0.9) contrast(0.9)',
}

const STORAGE_KEY = 'leo:pdf-theme'

export function loadPdfTheme(): PdfTheme {
  const stored = localStorage.getItem(STORAGE_KEY)
  return (PDF_THEMES as readonly string[]).includes(stored ?? '') ? (stored as PdfTheme) : 'light'
}

export function savePdfTheme(theme: PdfTheme): void {
  localStorage.setItem(STORAGE_KEY, theme)
}

export function ThemeSwitcher({ value, onChange }: { value: PdfTheme; onChange: (theme: PdfTheme) => void }) {
  return (
    <div className="inline-flex items-center gap-0.5 rounded-md border border-divider p-0.5">
      {PDF_THEMES.map((theme) => (
        <Button key={theme} type="button" size="sm" variant={value === theme ? 'default' : 'ghost'} onClick={() => onChange(theme)}>
          {THEME_LABELS[theme]}
        </Button>
      ))}
    </div>
  )
}
