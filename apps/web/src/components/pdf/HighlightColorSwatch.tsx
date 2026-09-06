import { HIGHLIGHT_COLORS, type HighlightColor } from '@/domain/pdfHighlights'

/** A fixed 4-color highlighter palette — deliberately separate from
 *  ui/ColorSwatchPicker.tsx's TAG_COLORS: highlighter ink and project tag
 *  color are different domains that happen to both be "pick a color". */
const SWATCH_CLASSES: Record<HighlightColor, string> = {
  yellow: 'bg-yellow-300',
  green: 'bg-green-300',
  blue: 'bg-blue-300',
  pink: 'bg-pink-300',
}

export function HighlightColorSwatch({ value, onChange }: { value: HighlightColor; onChange: (color: HighlightColor) => void }) {
  return (
    <div className="flex items-center gap-1.5">
      {HIGHLIGHT_COLORS.map((color) => (
        <button
          key={color}
          type="button"
          onClick={() => onChange(color)}
          aria-label={color}
          aria-pressed={value === color}
          className={`h-6 w-6 rounded-full ${SWATCH_CLASSES[color]} ${value === color ? 'ring-2 ring-accent ring-offset-2 ring-offset-surface' : ''}`}
        />
      ))}
    </div>
  )
}
