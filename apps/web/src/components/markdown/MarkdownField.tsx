import { useRef, useState, type KeyboardEvent } from 'react'
import { Bold, Heading1, Heading2, Heading3, Italic, List, ListOrdered, SeparatorHorizontal, TableColumnsSplit } from 'lucide-react'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { Markdown } from './Markdown'
import {
  insertColumns,
  insertPageBreak,
  toggleBulletList,
  toggleHeading,
  toggleNumberedList,
  toggleWrap,
  type EditResult,
} from './markdownEditing'
import { cn } from '@/lib/utils'

const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform ?? navigator.userAgent)
const MOD = isMac ? '⌘' : 'Ctrl'

type ToolbarAction = {
  label: string
  shortcut: string
  icon: typeof Bold
  apply: (value: string, selStart: number, selEnd: number) => EditResult
  /** Matches the keyboard event that should trigger this action too, so
   *  the toolbar's tooltip and the actual keybinding can't drift apart. */
  matchesKey: (e: KeyboardEvent<HTMLTextAreaElement>) => boolean
}

const ACTIONS: ToolbarAction[] = [
  {
    label: 'Bold',
    shortcut: `${MOD}+B`,
    icon: Bold,
    apply: (v, s, e) => toggleWrap(v, s, e, '**'),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'b',
  },
  {
    label: 'Italic',
    shortcut: `${MOD}+I`,
    icon: Italic,
    apply: (v, s, e) => toggleWrap(v, s, e, '_'),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'i',
  },
  {
    label: 'Heading 1',
    shortcut: `${MOD}+Shift+1`,
    icon: Heading1,
    apply: (v, s) => toggleHeading(v, s, 1),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.shiftKey && e.key === '1',
  },
  {
    label: 'Heading 2',
    shortcut: `${MOD}+Shift+2`,
    icon: Heading2,
    apply: (v, s) => toggleHeading(v, s, 2),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.shiftKey && e.key === '2',
  },
  {
    label: 'Heading 3',
    shortcut: `${MOD}+Shift+3`,
    icon: Heading3,
    apply: (v, s) => toggleHeading(v, s, 3),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.shiftKey && e.key === '3',
  },
  {
    label: 'Bullet list',
    // Matches Google Docs/Word's binding for the same thing — the one
    // list shortcut people are likeliest to already have muscle memory for.
    shortcut: `${MOD}+Shift+8`,
    icon: List,
    apply: (v, s, e) => toggleBulletList(v, s, e),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.shiftKey && e.key === '8',
  },
  {
    label: 'Numbered list',
    shortcut: `${MOD}+Shift+7`,
    icon: ListOrdered,
    apply: (v, s, e) => toggleNumberedList(v, s, e),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.shiftKey && e.key === '7',
  },
  {
    label: 'Columns (table)',
    shortcut: `${MOD}+Alt+T`,
    icon: TableColumnsSplit,
    apply: (v, s, e) => insertColumns(v, s, e),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.altKey && e.key.toLowerCase() === 't',
  },
  {
    label: 'Page break',
    shortcut: `${MOD}+Alt+Enter`,
    icon: SeparatorHorizontal,
    apply: (v, s, e) => insertPageBreak(v, s, e),
    matchesKey: (e) => (e.metaKey || e.ctrlKey) && e.altKey && e.key === 'Enter',
  },
]

/**
 * A labeled Write/Preview pair (GitHub's markdown-editor convention) rather
 * than a live side-by-side split — a split pane needs real width to be
 * worth it (project notes get it via a wide card; ItemDetailPanel's dock
 * only sometimes has it, see its own expand toggle), so one toggle that
 * works at every width was the simpler shared shape. Raw text is what's
 * actually persisted; Preview is purely a render of the same string
 * through the shared Markdown component.
 *
 * The Write side gets a small formatting toolbar (ACTIONS above) plus
 * matching keybindings — both drive the same pure string-transform helpers
 * in markdownEditing.ts, so toolbar clicks and keystrokes can't disagree
 * about what a given action does.
 */
export function MarkdownField({
  id,
  label,
  value,
  onChange,
  rows = 3,
  placeholder,
}: {
  id: string
  label: string
  value: string
  onChange: (next: string) => void
  rows?: number
  placeholder?: string
}) {
  const [tab, setTab] = useState<'write' | 'preview'>('write')
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  function runAction(action: ToolbarAction) {
    const el = textareaRef.current
    if (!el) return
    const result = action.apply(value, el.selectionStart, el.selectionEnd)
    onChange(result.value)
    requestAnimationFrame(() => {
      el.focus()
      el.setSelectionRange(result.selectionStart, result.selectionEnd)
    })
  }

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    const action = ACTIONS.find((a) => a.matchesKey(e))
    if (!action) return
    e.preventDefault()
    runAction(action)
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <Label htmlFor={id}>{label}</Label>
        <div className="flex gap-1 rounded-leo-sm bg-surface-elevated p-0.5">
          {(['write', 'preview'] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={cn(
                'rounded-leo-sm px-2 py-0.5 text-xs font-medium capitalize transition-colors',
                tab === t ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
              )}
            >
              {t}
            </button>
          ))}
        </div>
      </div>
      {tab === 'write' ? (
        <>
          <div className="flex flex-wrap gap-0.5 rounded-leo-sm border border-divider bg-surface-elevated p-0.5">
            {ACTIONS.map((action) => (
              <button
                key={action.label}
                type="button"
                title={`${action.label} (${action.shortcut})`}
                aria-label={action.label}
                // Formatting a selection must not steal focus from the
                // textarea first — mousedown fires before the textarea's
                // blur, so preventDefault here keeps the selection intact.
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => runAction(action)}
                className="rounded-leo-sm p-1.5 text-text-secondary hover:bg-surface hover:text-text-primary"
              >
                <action.icon className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            ))}
          </div>
          <Textarea
            id={id}
            ref={textareaRef}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={handleKeyDown}
            rows={rows}
            placeholder={placeholder}
            className="font-mono text-sm"
          />
        </>
      ) : value.trim() ? (
        <div className="rounded-md border border-input px-3 py-2" style={{ minHeight: `${rows * 1.5}rem` }}>
          <Markdown text={value} className="text-sm" />
        </div>
      ) : (
        <p className="text-sm text-text-secondary italic" style={{ minHeight: `${rows * 1.5}rem` }}>
          Nothing to preview yet.
        </p>
      )}
    </div>
  )
}
