import { describe, expect, it } from 'vitest'
import { adfToMarkdown, type AdfNode } from '../adf'

function doc(...content: AdfNode[]): AdfNode {
  return { type: 'doc', content }
}
function paragraph(...content: AdfNode[]): AdfNode {
  return { type: 'paragraph', content }
}
function text(value: string, marks?: AdfNode['marks']): AdfNode {
  return { type: 'text', text: value, marks }
}

describe('adfToMarkdown', () => {
  it('returns empty string for null/undefined/content-less docs', () => {
    expect(adfToMarkdown(null)).toBe('')
    expect(adfToMarkdown(undefined)).toBe('')
    expect(adfToMarkdown({ type: 'doc' })).toBe('')
  })

  it('joins paragraphs with a blank line between them', () => {
    const result = adfToMarkdown(doc(paragraph(text('First')), paragraph(text('Second'))))
    expect(result).toBe('First\n\nSecond')
  })

  it('applies strong/em/code/strike/link marks', () => {
    const result = adfToMarkdown(
      doc(
        paragraph(
          text('bold', [{ type: 'strong' }]),
          text(' '),
          text('italic', [{ type: 'em' }]),
          text(' '),
          text('code', [{ type: 'code' }]),
          text(' '),
          text('gone', [{ type: 'strike' }]),
          text(' '),
          text('link', [{ type: 'link', attrs: { href: 'https://example.com' } }]),
        ),
      ),
    )
    expect(result).toBe('**bold** *italic* `code` ~~gone~~ [link](https://example.com)')
  })

  it('renders a heading with its level', () => {
    const result = adfToMarkdown(doc({ type: 'heading', attrs: { level: 2 }, content: [text('Title')] }))
    expect(result).toBe('## Title')
  })

  it('renders a bullet list as "- " items', () => {
    const result = adfToMarkdown(
      doc({
        type: 'bulletList',
        content: [
          { type: 'listItem', content: [paragraph(text('One'))] },
          { type: 'listItem', content: [paragraph(text('Two'))] },
        ],
      }),
    )
    expect(result).toBe('- One\n- Two')
  })

  it('renders an ordered list with numeric markers', () => {
    const result = adfToMarkdown(
      doc({
        type: 'orderedList',
        content: [
          { type: 'listItem', content: [paragraph(text('First'))] },
          { type: 'listItem', content: [paragraph(text('Second'))] },
        ],
      }),
    )
    expect(result).toBe('1. First\n2. Second')
  })

  it('converts a hardBreak to a newline within a paragraph', () => {
    const result = adfToMarkdown(doc(paragraph(text('Line one'), { type: 'hardBreak' }, text('Line two'))))
    expect(result).toBe('Line one\nLine two')
  })

  it('fences a codeBlock with its language', () => {
    const result = adfToMarkdown(doc({ type: 'codeBlock', attrs: { language: 'ts' }, content: [text('const x = 1')] }))
    expect(result).toBe('```ts\nconst x = 1\n```')
  })

  it('prefixes blockquote lines with ">"', () => {
    const result = adfToMarkdown(doc({ type: 'blockquote', content: [paragraph(text('Quoted'))] }))
    expect(result).toBe('> Quoted')
  })

  it('falls back to attrs.text for a mention', () => {
    const result = adfToMarkdown(doc(paragraph({ type: 'mention', attrs: { text: '@jane' } })))
    expect(result).toBe('@jane')
  })

  it('recurses into unrecognized node types that still have content', () => {
    const result = adfToMarkdown(doc({ type: 'expand', content: [paragraph(text('Inside an expand'))] }))
    expect(result).toBe('Inside an expand')
  })
})
