import { useState } from 'react'
import * as Dialog from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { RESPONSIVE_DIALOG_CONTENT, RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import { cn } from '@/lib/utils'

/**
 * Raw JSON editor for one record — deliberately not a generated form. A
 * debug tool that lets you inspect/edit ANY of Items/Habits/Measurements
 * (7 item kinds with different fields each, plus habits and measurements)
 * would need a different form per kind; a shared JSON textarea covers all
 * of them with one component, at the cost of expecting the person using it
 * to be comfortable reading/editing JSON — an acceptable trade for a
 * developer-facing tool, not something end-user UI should do.
 */
export function JsonEditorModal({
  title,
  initialValue,
  onSave,
  onClose,
}: {
  title: string
  initialValue: unknown
  onSave: (parsed: Record<string, unknown>) => Promise<void>
  onClose: () => void
}) {
  const [text, setText] = useState(() => JSON.stringify(initialValue, null, 2))
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    let parsed: unknown
    try {
      parsed = JSON.parse(text)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invalid JSON')
      return
    }
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      setError('Must be a JSON object, not an array or primitive.')
      return
    }
    setError(null)
    setSaving(true)
    try {
      await onSave(parsed as Record<string, unknown>)
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={RESPONSIVE_DIALOG_OVERLAY} />
        <Dialog.Content className={cn(RESPONSIVE_DIALOG_CONTENT, 'sm:max-w-2xl max-h-[85vh] overflow-y-auto bg-surface p-4 shadow-xl')}>
          <div className="mb-3 flex items-center justify-between">
            <Dialog.Title className="text-sm font-medium text-text-primary">{title}</Dialog.Title>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-1 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>

          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            spellCheck={false}
            className="h-96 w-full resize-none rounded-leo-sm border border-divider bg-surface-elevated p-3 font-mono text-xs text-text-primary outline-none focus:border-accent"
          />

          {error && <p className="mt-2 text-xs text-danger">{error}</p>}

          <div className="mt-3 flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button type="button" onClick={() => void handleSave()} disabled={saving}>
              {saving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
