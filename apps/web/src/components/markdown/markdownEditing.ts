/**
 * Pure text-transform helpers behind MarkdownField's toolbar/keybindings —
 * kept free of React and the DOM (just string in, string + new selection
 * out) so the cursor-math is testable without mounting a textarea. The
 * component layer (MarkdownField.tsx) owns reading/writing the real
 * textarea's selectionStart/selectionEnd and refocusing it afterward.
 */

export type EditResult = { value: string; selectionStart: number; selectionEnd: number }

function lineBounds(value: string, start: number, end: number): { lineStart: number; lineEnd: number } {
  const lineStart = value.lastIndexOf('\n', start - 1) + 1
  const nextBreak = value.indexOf('\n', end)
  const lineEnd = nextBreak === -1 ? value.length : nextBreak
  return { lineStart, lineEnd }
}

export function insertText(value: string, selStart: number, selEnd: number, text: string): EditResult {
  const next = value.slice(0, selStart) + text + value.slice(selEnd)
  const pos = selStart + text.length
  return { value: next, selectionStart: pos, selectionEnd: pos }
}

/** Bold/italic: wraps the selection in `marker` on both sides, or unwraps
 *  it if the selection is already framed by exactly that marker — the
 *  same toggle-on-reapply behavior as every rich text editor's B/I button. */
export function toggleWrap(value: string, selStart: number, selEnd: number, marker: string): EditResult {
  const before = value.slice(Math.max(0, selStart - marker.length), selStart)
  const after = value.slice(selEnd, selEnd + marker.length)
  if (before === marker && after === marker) {
    const next = value.slice(0, selStart - marker.length) + value.slice(selStart, selEnd) + value.slice(selEnd + marker.length)
    return { value: next, selectionStart: selStart - marker.length, selectionEnd: selEnd - marker.length }
  }
  const selected = value.slice(selStart, selEnd)
  const next = value.slice(0, selStart) + marker + selected + marker + value.slice(selEnd)
  return { value: next, selectionStart: selStart + marker.length, selectionEnd: selStart + marker.length + selected.length }
}

const HEADING_RE = /^(#{1,6})\s+/

/** Headings are a per-line concept, not a block one — always acts on the
 *  single line the caret/selection starts in, regardless of how much text
 *  is selected. Reapplying the same level clears it back to plain text;
 *  applying a different level swaps the marker. */
export function toggleHeading(value: string, selStart: number, level: number): EditResult {
  const { lineStart, lineEnd } = lineBounds(value, selStart, selStart)
  const line = value.slice(lineStart, lineEnd)
  const match = line.match(HEADING_RE)
  const bare = match ? line.slice(match[0].length) : line
  const alreadyThisLevel = match !== null && match[1].length === level
  const nextLine = alreadyThisLevel ? bare : '#'.repeat(level) + ' ' + bare
  const next = value.slice(0, lineStart) + nextLine + value.slice(lineEnd)
  const pos = lineStart + nextLine.length
  return { value: next, selectionStart: pos, selectionEnd: pos }
}

const BULLET_RE = /^(\s*)[-*]\s+/
const NUMBERED_RE = /^(\s*)\d+\.\s+/

function stripListMarker(line: string): string {
  return line.replace(BULLET_RE, '$1').replace(NUMBERED_RE, '$1')
}

/** Bullet/numbered list: acts on every line touched by the selection (a
 *  multi-line select turns each line into a list item), toggling off if
 *  every non-blank line in range already has that marker. Numbered lists
 *  are renumbered from 1 on apply so pasting/reordering never leaves stale
 *  numbers. Switching list type on an already-listed block replaces the
 *  other marker instead of stacking both. */
function toggleList(value: string, selStart: number, selEnd: number, isMarked: (line: string) => boolean, makeMarker: (n: number) => string): EditResult {
  const { lineStart, lineEnd } = lineBounds(value, selStart, selEnd)
  const block = value.slice(lineStart, lineEnd)
  const lines = block.split('\n')
  const nonBlank = lines.filter((l) => l.trim() !== '')
  const allMarked = nonBlank.length > 0 && nonBlank.every(isMarked)
  let n = 0
  const nextLines = lines.map((l) => {
    if (l.trim() === '') return l
    const bare = stripListMarker(l)
    if (allMarked) return bare
    n += 1
    return makeMarker(n) + bare
  })
  const nextBlock = nextLines.join('\n')
  const next = value.slice(0, lineStart) + nextBlock + value.slice(lineEnd)
  return { value: next, selectionStart: lineStart, selectionEnd: lineStart + nextBlock.length }
}

export function toggleBulletList(value: string, selStart: number, selEnd: number): EditResult {
  return toggleList(
    value,
    selStart,
    selEnd,
    (l) => BULLET_RE.test(l),
    () => '- ',
  )
}

export function toggleNumberedList(value: string, selStart: number, selEnd: number): EditResult {
  return toggleList(
    value,
    selStart,
    selEnd,
    (l) => NUMBERED_RE.test(l),
    (n) => `${n}. `,
  )
}

/** A 2-column GFM table skeleton — markdown has no real multi-column
 *  layout primitive, but the app's Markdown renderer already supports GFM
 *  tables (remark-gfm), so this is the one construct that actually renders
 *  side by side rather than just being a labeling convention. */
export function insertColumns(value: string, selStart: number, selEnd: number): EditResult {
  return insertText(value, selStart, selEnd, '\n\n| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n\n')
}

/** A thematic break (`---`) — the closest markdown has to a page break,
 *  and what the Markdown renderer (remark-gfm) turns into an `<hr>`. */
export function insertPageBreak(value: string, selStart: number, selEnd: number): EditResult {
  return insertText(value, selStart, selEnd, '\n\n---\n\n')
}
