/**
 * Jira issue descriptions come back as Atlassian Document Format (ADF), a
 * ProseMirror-style JSON tree — not HTML, not Markdown. Converting to
 * Markdown (rather than rendering ADF's HTML export via `expand=
 * renderedFields` + dangerouslySetInnerHTML) means the existing Markdown
 * component handles it with zero new trust surface: this codebase has no
 * `dangerouslySetInnerHTML` anywhere, and injecting a third party's raw
 * HTML would be the first. Best-effort, not a full ADF renderer — media/
 * tables/panels degrade to something readable rather than being rendered
 * exactly, which is the right tradeoff for a read-only ticket viewer.
 */

export type AdfNode = {
  type: string
  text?: string
  marks?: { type: string; attrs?: Record<string, unknown> }[]
  content?: AdfNode[]
  attrs?: Record<string, unknown>
}

function markWrap(text: string, marks: AdfNode['marks']): string {
  if (!marks || marks.length === 0) return text
  let wrapped = text
  for (const mark of marks) {
    if (mark.type === 'strong') wrapped = `**${wrapped}**`
    else if (mark.type === 'em') wrapped = `*${wrapped}*`
    else if (mark.type === 'code') wrapped = `\`${wrapped}\``
    else if (mark.type === 'strike') wrapped = `~~${wrapped}~~`
    else if (mark.type === 'link' && typeof mark.attrs?.href === 'string') wrapped = `[${wrapped}](${mark.attrs.href})`
  }
  return wrapped
}

function inlineText(node: AdfNode): string {
  if (node.type === 'text') return markWrap(node.text ?? '', node.marks)
  if (node.type === 'hardBreak') return '\n'
  if (node.type === 'mention') return typeof node.attrs?.text === 'string' ? node.attrs.text : '@mention'
  if (node.type === 'emoji') return typeof node.attrs?.shortName === 'string' ? node.attrs.shortName : ''
  if (node.type === 'date') return typeof node.attrs?.timestamp === 'string' ? node.attrs.timestamp : ''
  if (node.content) return node.content.map(inlineText).join('')
  return ''
}

function listItems(items: AdfNode[], ordered: boolean, depth: number): string {
  const indent = '  '.repeat(depth)
  return items
    .map((item, i) => {
      const marker = ordered ? `${i + 1}.` : '-'
      const body = (item.content ?? []).map((child) => blockNode(child, depth + 1)).join('\n')
      return `${indent}${marker} ${body.trim()}`
    })
    .join('\n')
}

function blockNode(node: AdfNode, depth = 0): string {
  switch (node.type) {
    case 'paragraph':
      return (node.content ?? []).map(inlineText).join('')
    case 'heading': {
      const level = typeof node.attrs?.level === 'number' ? node.attrs.level : 1
      return `${'#'.repeat(Math.min(Math.max(level, 1), 6))} ${(node.content ?? []).map(inlineText).join('')}`
    }
    case 'bulletList':
      return listItems(node.content ?? [], false, depth)
    case 'orderedList':
      return listItems(node.content ?? [], true, depth)
    case 'codeBlock': {
      const lang = typeof node.attrs?.language === 'string' ? node.attrs.language : ''
      const code = (node.content ?? []).map(inlineText).join('')
      return `\`\`\`${lang}\n${code}\n\`\`\``
    }
    case 'blockquote':
      return (node.content ?? [])
        .map((child) => blockNode(child, depth))
        .join('\n')
        .split('\n')
        .map((line) => `> ${line}`)
        .join('\n')
    case 'rule':
      return '---'
    case 'panel':
      // Info/warning/error panels don't have a Markdown equivalent —
      // rendered as a plain blockquote so the content still reads, just
      // without the colored panel chrome.
      return (node.content ?? [])
        .map((child) => blockNode(child, depth))
        .join('\n')
        .split('\n')
        .map((line) => `> ${line}`)
        .join('\n')
    case 'table':
      // Best-effort: one line per row, cells joined by " | ", no header
      // separator — a real Markdown table needs consistent column counts
      // ADF doesn't guarantee, so this favors "readable" over "valid GFM."
      return (node.content ?? [])
        .map((row) => (row.content ?? []).map((cell) => (cell.content ?? []).map((c) => blockNode(c, depth)).join(' ')).join(' | '))
        .join('\n')
    case 'mediaSingle':
    case 'mediaGroup':
      return '*[attachment]*'
    default:
      if (node.content) return node.content.map((child) => blockNode(child, depth)).join('\n\n')
      return inlineText(node)
  }
}

/** Entry point — `doc` is ADF's root node type, content is a list of block
 *  nodes separated by blank lines (standard Markdown paragraph spacing). */
export function adfToMarkdown(doc: AdfNode | null | undefined): string {
  if (!doc?.content) return ''
  return doc.content
    .map((node) => blockNode(node))
    .filter((block) => block.trim().length > 0)
    .join('\n\n')
}
