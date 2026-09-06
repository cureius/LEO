import { useMemo, useState } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { TagChip } from '@/components/ui/TagChip'
import { TAG_COLORS } from '@/domain/tagColors'
import { selectItemsArray, useSyncStore } from '@/sync/store'
import type { Tag } from '@/domain/types'

/** Tags are embedded per-item, not a separate synced table (see wire/items.ts
 *  — each item carries its own {id, name, colorRaw} copy) — there's no
 *  canonical registry to query. "Known tags" here is derived by scanning
 *  every item currently in the store and deduping by NAME, since two items
 *  independently tagged "Website Redesign" may end up with different ids —
 *  matching by name (not id) is what makes reusing an existing "project"
 *  actually group correctly, both here and in ProjectsPage.tsx. */
function pickColor(usedCount: number): Tag['colorRaw'] {
  return TAG_COLORS[usedCount % TAG_COLORS.length]
}

export function TagEditor({ tags, onChange }: { tags: Tag[]; onChange: (tags: Tag[]) => void }) {
  const items = useSyncStore(useShallow(selectItemsArray))
  const [input, setInput] = useState('')
  const [focused, setFocused] = useState(false)

  const knownTags = useMemo(() => {
    const map = new Map<string, Tag>()
    for (const item of items) {
      const itemTags = 'tags' in item ? item.tags : []
      for (const t of itemTags) if (!map.has(t.name)) map.set(t.name, t)
    }
    return Array.from(map.values()).sort((a, b) => a.name.localeCompare(b.name))
  }, [items])

  const available = knownTags.filter((t) => !tags.some((existing) => existing.name === t.name))
  // Shown on focus even before typing — not just a filter-as-you-type list —
  // so re-using an existing project is a click away instead of having to
  // remember and retype its exact name.
  const trimmedInput = input.trim().toLowerCase()
  const suggestions = focused ? (trimmedInput ? available.filter((t) => t.name.toLowerCase().includes(trimmedInput)) : available) : []

  function addTag(tag: Tag) {
    onChange([...tags, tag])
    setInput('')
  }

  function addFromInput() {
    const trimmed = input.trim()
    if (!trimmed) return
    if (tags.some((t) => t.name.toLowerCase() === trimmed.toLowerCase())) {
      setInput('')
      return
    }
    // Reuse an existing tag's id/color if the name matches one already in
    // use elsewhere — otherwise this "project" silently fragments into
    // multiple differently-colored tags that don't group together.
    const existing = knownTags.find((t) => t.name.toLowerCase() === trimmed.toLowerCase())
    addTag(existing ?? { id: crypto.randomUUID(), name: trimmed, colorRaw: pickColor(knownTags.length) })
  }

  function removeTag(id: string) {
    onChange(tags.filter((t) => t.id !== id))
  }

  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor="tag-editor-input">Tags / Project</Label>
      {tags.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {tags.map((t) => (
            <TagChip key={t.id} tag={t} onRemove={() => removeTag(t.id)} />
          ))}
        </div>
      )}
      <div className="relative">
        <Input
          id="tag-editor-input"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              addFromInput()
            }
          }}
          placeholder="Add a tag or project…"
        />
        {suggestions.length > 0 && (
          <ul className="absolute z-10 mt-1 w-full overflow-hidden rounded-leo-sm border border-divider bg-surface shadow-md">
            {suggestions.slice(0, 8).map((t) => (
              <li key={t.id}>
                {/* preventDefault on mousedown, not just onClick, keeps the
                    input focused through the click — otherwise the input's
                    onBlur fires first, `focused` flips false, and this list
                    unmounts before the click can ever land on it. */}
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => addTag(t)}
                  className="flex w-full items-center px-2 py-1.5 text-left hover:bg-surface-elevated"
                >
                  <TagChip tag={t} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
