import type { TagColor } from './types'

/** Fixed palette per TagColor — literal color choices meant to look the same
 *  regardless of app theme, not tied to the semantic accent/danger tokens in
 *  tokens.css. Order here also drives new-tag color rotation (see
 *  TagEditor.tsx's pickColor). */
export const TAG_COLORS: TagColor[] = ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'indigo', 'purple', 'pink', 'gray']

const TAG_COLOR_CLASSES: Record<TagColor, string> = {
  red: 'bg-red-500/15 text-red-600 dark:text-red-400',
  orange: 'bg-orange-500/15 text-orange-600 dark:text-orange-400',
  yellow: 'bg-yellow-500/15 text-yellow-700 dark:text-yellow-400',
  green: 'bg-green-500/15 text-green-600 dark:text-green-400',
  teal: 'bg-teal-500/15 text-teal-600 dark:text-teal-400',
  blue: 'bg-blue-500/15 text-blue-600 dark:text-blue-400',
  indigo: 'bg-indigo-500/15 text-indigo-600 dark:text-indigo-400',
  purple: 'bg-purple-500/15 text-purple-600 dark:text-purple-400',
  pink: 'bg-pink-500/15 text-pink-600 dark:text-pink-400',
  gray: 'bg-gray-500/15 text-gray-600 dark:text-gray-400',
}

export function tagColorClasses(color: TagColor): string {
  return TAG_COLOR_CLASSES[color] ?? TAG_COLOR_CLASSES.gray
}

/** SVG fills (recharts bar/pie cells) take real color values, not Tailwind
 *  classes — this is the same palette as TAG_COLOR_CLASSES's `-500` shade,
 *  kept as a separate map rather than parsing classes at runtime. */
const TAG_COLOR_HEX: Record<TagColor, string> = {
  red: '#ef4444',
  orange: '#f97316',
  yellow: '#eab308',
  green: '#22c55e',
  teal: '#14b8a6',
  blue: '#3b82f6',
  indigo: '#6366f1',
  purple: '#a855f7',
  pink: '#ec4899',
  gray: '#6b7280',
}

export function tagColorHex(color: TagColor): string {
  return TAG_COLOR_HEX[color] ?? TAG_COLOR_HEX.gray
}
