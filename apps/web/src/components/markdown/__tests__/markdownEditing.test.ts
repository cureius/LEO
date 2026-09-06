import { describe, expect, it } from 'vitest'
import { insertColumns, insertPageBreak, insertText, toggleBulletList, toggleHeading, toggleNumberedList, toggleWrap } from '../markdownEditing'

describe('toggleWrap', () => {
  it('wraps a selection with the marker on both sides', () => {
    const result = toggleWrap('hello world', 0, 5, '**')
    expect(result.value).toBe('**hello** world')
    expect(result.selectionStart).toBe(2)
    expect(result.selectionEnd).toBe(7)
  })

  it('unwraps when the selection is already framed by the marker', () => {
    const result = toggleWrap('**hello** world', 2, 7, '**')
    expect(result.value).toBe('hello world')
    expect(result.selectionStart).toBe(0)
    expect(result.selectionEnd).toBe(5)
  })
})

describe('toggleHeading', () => {
  it('adds a heading marker to the current line only', () => {
    const value = 'first\nsecond\nthird'
    const result = toggleHeading(value, value.indexOf('second'), 2)
    expect(result.value).toBe('first\n## second\nthird')
  })

  it('clears the heading when reapplying the same level', () => {
    const result = toggleHeading('## second', 3, 2)
    expect(result.value).toBe('second')
  })

  it('swaps to a different level instead of stacking markers', () => {
    const result = toggleHeading('## second', 3, 1)
    expect(result.value).toBe('# second')
  })
})

describe('toggleBulletList', () => {
  it('bullets every line touched by the selection', () => {
    const value = 'one\ntwo\nthree'
    const result = toggleBulletList(value, 0, value.length)
    expect(result.value).toBe('- one\n- two\n- three')
  })

  it('un-bullets when every line is already bulleted', () => {
    const value = '- one\n- two'
    const result = toggleBulletList(value, 0, value.length)
    expect(result.value).toBe('one\ntwo')
  })

  it('replaces a numbered marker instead of stacking both', () => {
    const value = '1. one\n2. two'
    const result = toggleBulletList(value, 0, value.length)
    expect(result.value).toBe('- one\n- two')
  })

  it('leaves blank lines in the selection untouched', () => {
    const value = 'one\n\ntwo'
    const result = toggleBulletList(value, 0, value.length)
    expect(result.value).toBe('- one\n\n- two')
  })
})

describe('toggleNumberedList', () => {
  it('numbers every line sequentially from 1', () => {
    const value = 'one\ntwo\nthree'
    const result = toggleNumberedList(value, 0, value.length)
    expect(result.value).toBe('1. one\n2. two\n3. three')
  })

  it('un-numbers when every line is already numbered', () => {
    const value = '1. one\n2. two'
    const result = toggleNumberedList(value, 0, value.length)
    expect(result.value).toBe('one\ntwo')
  })
})

describe('insertText / insertColumns / insertPageBreak', () => {
  it('inserts at the cursor and replaces any selection', () => {
    const result = insertText('hello world', 5, 11, '!')
    expect(result.value).toBe('hello!')
    expect(result.selectionStart).toBe(6)
    expect(result.selectionEnd).toBe(6)
  })

  it('inserts a 2-column GFM table skeleton', () => {
    const result = insertColumns('before after', 6, 6)
    expect(result.value).toContain('| Column 1 | Column 2 |')
    expect(result.value).toContain('| --- | --- |')
  })

  it('inserts a thematic break for a page break', () => {
    const result = insertPageBreak('before after', 6, 6)
    expect(result.value).toBe('before\n\n---\n\n after')
  })
})
