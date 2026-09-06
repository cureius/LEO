/** Port-adjacent to native's AppearanceMode (SettingsRootView.swift) — 'system'
 *  here means "no override," letting tokens.css's prefers-color-scheme media
 *  query decide, same as the web app's behavior before this existed at all. */
export type Theme = 'system' | 'light' | 'dark'

const THEME_STORAGE_KEY = 'leo_theme'

export function getTheme(): Theme {
  const raw = localStorage.getItem(THEME_STORAGE_KEY)
  return raw === 'light' || raw === 'dark' ? raw : 'system'
}

// index.html ships two <meta name="theme-color" media="(prefers-color-
// scheme: …)"> tags so the mobile browser/PWA status bar tracks the OS
// theme automatically — but that media-query mechanism only ever reflects
// the OS preference, not an explicit in-app override below. Captured once,
// lazily, so 'system' can restore the original per-scheme values after a
// previous override forced both tags to the same color.
let defaultThemeColors: { light?: string; dark?: string } | null = null

function captureDefaultThemeColors(): void {
  if (defaultThemeColors) return
  defaultThemeColors = {}
  document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
    const media = meta.getAttribute('media') ?? ''
    const content = meta.getAttribute('content')
    if (!content) return
    if (media.includes('dark')) defaultThemeColors!.dark = content
    else if (media.includes('light')) defaultThemeColors!.light = content
  })
}

/** Keeps the status bar color in sync with whichever theme is ACTUALLY
 *  active. For an explicit override, both meta tags get forced to the same
 *  color (computed from the just-applied `--leo-background` token) so the
 *  status bar matches even when it disagrees with the OS's own preference;
 *  for 'system' it restores each tag's original per-scheme value so the
 *  prefers-color-scheme mechanism resumes deciding on its own. */
function syncThemeColorMeta(theme: Theme): void {
  captureDefaultThemeColors()
  const metas = document.querySelectorAll('meta[name="theme-color"]')
  if (theme === 'system') {
    metas.forEach((meta) => {
      const media = meta.getAttribute('media') ?? ''
      const restore = media.includes('dark') ? defaultThemeColors?.dark : defaultThemeColors?.light
      if (restore) meta.setAttribute('content', restore)
    })
    return
  }
  const color = getComputedStyle(document.documentElement).getPropertyValue('--leo-background').trim()
  if (color) metas.forEach((meta) => meta.setAttribute('content', color))
}

/** Toggles the `data-theme` attribute tokens.css's `:root[data-theme="…"]`
 *  overrides key off — higher specificity than the plain `:root` and
 *  `@media (prefers-color-scheme: dark)` blocks, so this wins regardless of
 *  actual system preference. Absent entirely for 'system', which is what
 *  lets the media query resume deciding. */
export function applyTheme(theme: Theme): void {
  if (theme === 'system') document.documentElement.removeAttribute('data-theme')
  else document.documentElement.setAttribute('data-theme', theme)
  syncThemeColorMeta(theme)
}

export function setTheme(theme: Theme): void {
  if (theme === 'system') localStorage.removeItem(THEME_STORAGE_KEY)
  else localStorage.setItem(THEME_STORAGE_KEY, theme)
  applyTheme(theme)
}
