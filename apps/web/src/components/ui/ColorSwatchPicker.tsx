import { TAG_COLORS, tagColorClasses } from '@/domain/tagColors'
import type { TagColor } from '@/domain/types'

/** Extracted from ProjectsPage.tsx so RulesDialog (target project color)
 *  and ProjectsPage (project color) share one implementation instead of
 *  two copies drifting apart. */
export function ColorSwatchPicker({ value, onChange }: { value: TagColor; onChange: (color: TagColor) => void }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {TAG_COLORS.map((color) => (
        <button
          key={color}
          type="button"
          onClick={() => onChange(color)}
          aria-label={color}
          aria-pressed={value === color}
          className={`h-6 w-6 rounded-full ${tagColorClasses(color)} ${value === color ? 'ring-2 ring-accent ring-offset-2 ring-offset-surface' : ''}`}
        />
      ))}
    </div>
  )
}
