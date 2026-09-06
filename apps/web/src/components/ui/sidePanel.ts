import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'

/**
 * Shared shape for every right-docked detail panel (ItemDetailPanel, Jira's
 * issue detail) — pulled out once two callers needed the identical
 * positioning/animation rather than each hand-copying it.
 *
 * Mobile keeps the existing full-width bottom sheet (the native iOS/Android
 * modal convention — see responsiveDialog.ts's doc comment, which every
 * OTHER dialog in the app still uses as-is). This diverges only at `sm:`
 * and up: docked to the right edge, full height, instead of a centered
 * floating box — which is why it isn't folded into that shared constant.
 */
export const SIDE_PANEL_CONTENT =
  'fixed inset-x-0 bottom-0 top-auto z-50 flex max-h-[85vh] w-full max-w-full flex-col rounded-t-leo-lg bg-surface shadow-xl transition-transform duration-200 ease-out pb-[env(safe-area-inset-bottom)] ' +
  'sm:inset-y-0 sm:top-0 sm:bottom-0 sm:right-0 sm:left-auto sm:h-full sm:max-h-full sm:w-[420px] lg:w-[480px] sm:rounded-none sm:rounded-l-leo-lg sm:pb-0'
export const SIDE_PANEL_HIDDEN = 'translate-y-full sm:translate-y-0 sm:translate-x-full'
export const SIDE_PANEL_SHOWN = 'translate-y-0 sm:translate-y-0 sm:translate-x-0'

/** Slides the panel in (and fades its overlay in) on mount rather than
 *  appearing instantly. Radix's own exit-animation hook (Presence) doesn't
 *  apply here: every caller unmounts the panel directly on close (`{open &&
 *  <Panel .../>}`) rather than flipping Dialog.Root's `open` prop — the
 *  same instant-mount/unmount every other dialog in the app already uses —
 *  so only the entrance is animated, not the exit. */
export function useSidePanelEntrance(): { contentClass: string; overlayClass: string } {
  const [mounted, setMounted] = useState(false)
  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true))
    return () => cancelAnimationFrame(id)
  }, [])
  return {
    contentClass: mounted ? SIDE_PANEL_SHOWN : SIDE_PANEL_HIDDEN,
    overlayClass: cn('transition-opacity duration-200', mounted ? 'opacity-100' : 'opacity-0'),
  }
}
