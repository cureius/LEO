import { X } from 'lucide-react'
import { tagColorClasses } from '@/domain/tagColors'
import type { Tag } from '@/domain/types'

/** Colored tag pill — ItemRow previously rendered tags through the generic
 *  Chip component, which ignores `colorRaw` entirely (only 3 fixed tones);
 *  this is the first place a tag's actual color is ever shown. */
export function TagChip({ tag, onRemove }: { tag: Tag; onRemove?: () => void }) {
  return (
    <span className={`inline-flex items-center gap-1 whitespace-nowrap rounded-leo-pill px-2 py-0.5 text-xs font-medium ${tagColorClasses(tag.colorRaw)}`}>
      {tag.name}
      {onRemove && (
        <button type="button" onClick={onRemove} aria-label={`Remove tag "${tag.name}"`} className="-m-0.5 rounded-full p-0.5 hover:opacity-70">
          <X className="h-3 w-3" aria-hidden="true" />
        </button>
      )}
    </span>
  )
}
