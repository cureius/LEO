/**
 * Shared positioning classes for every raw `@radix-ui/react-dialog`
 * `Dialog.Content` in the app. On mobile a centered floating box (the old
 * universal treatment) reads as a web popup, not an app — this makes every
 * dialog a full-width bottom sheet that slides up from the edge instead,
 * which is the native iOS/Android modal convention. `sm:` and up reverts to
 * the original centered-box treatment. Callers still own their own
 * max-width (via an `sm:max-w-*` class — NOT a bare `max-w-*`, which would
 * also apply on mobile and defeat the full-width sheet) and inner padding.
 */
export const RESPONSIVE_DIALOG_OVERLAY = 'fixed inset-0 z-50 bg-black/40'

export const RESPONSIVE_DIALOG_CONTENT =
  'fixed inset-x-0 bottom-0 top-auto z-50 w-full max-w-full translate-x-0 translate-y-0 rounded-t-leo-lg rounded-b-none pb-[env(safe-area-inset-bottom)] ' +
  'sm:inset-x-auto sm:top-1/2 sm:bottom-auto sm:left-1/2 sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-leo-lg sm:pb-0'
