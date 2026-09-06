import { useEffect, useState } from 'react'
import { Gauge } from 'lucide-react'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { getRoutingOverride, setRoutingOverride, type RoutingOverride } from '@/ai/router'
import { allRecords, recordsThisMonth, totalCostUSD, totalTokensThisMonth, type AIRequestRecord } from '@/ai/telemetry'
import { cn } from '@/lib/utils'

const ROUTING_OPTIONS: { value: RoutingOverride; label: string }[] = [
  { value: 'none', label: 'Auto' },
  { value: 'always_opus', label: 'Always Opus' },
  { value: 'prefer_cheap', label: 'Prefer cheap' },
]

function formatTimestamp(iso: string): string {
  const d = new Date(iso)
  const now = new Date()
  const diffMs = now.getTime() - d.getTime()
  const diffMin = Math.round(diffMs / 60_000)
  if (diffMin < 1) return 'just now'
  if (diffMin < 60) return `${diffMin}m ago`
  const diffHr = Math.round(diffMin / 60)
  if (diffHr < 24) return `${diffHr}h ago`
  return d.toLocaleDateString()
}

/**
 * Port of native's Settings → AI page (routing picker + "AI Usage" screen,
 * SettingsRootView.swift's AISettingsPage/AIUsageView) — web has no dedicated
 * Settings route, so this lives inline in ChatPage next to "Change API key"
 * rather than a separate page.
 */
export function AISettingsPanel() {
  const [override, setOverride] = useState<RoutingOverride>('none')
  const [records, setRecords] = useState<AIRequestRecord[]>([])
  const [monthlyTotal, setMonthlyTotal] = useState({ input: 0, output: 0 })
  const [open, setOpen] = useState(false)

  useEffect(() => {
    if (!open) return
    setOverride(getRoutingOverride())
    setRecords(allRecords())
    setMonthlyTotal(totalTokensThisMonth())
  }, [open])

  function handleOverrideChange(next: RoutingOverride) {
    setRoutingOverride(next)
    setOverride(next)
  }

  const monthlyCost = recordsThisMonth().reduce((sum, r) => sum + totalCostUSD(r), 0)
  const recent = [...records].reverse().slice(0, 20)

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label="AI usage and model routing"
          className="flex items-center gap-1.5 rounded-leo-sm px-2 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-elevated"
        >
          <Gauge className="h-3.5 w-3.5" aria-hidden="true" />
          AI Usage
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" sideOffset={6} className="w-80 p-4">
          <div className="mb-4">
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-text-secondary">Model routing</h3>
            <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
              {ROUTING_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => handleOverrideChange(opt.value)}
                  aria-pressed={override === opt.value}
                  className={cn(
                    'flex-1 rounded-leo-sm py-1 text-xs font-medium transition-colors',
                    override === opt.value ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
                  )}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div className="mb-3">
            <h3 className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-text-secondary">This month</h3>
            <div className="flex justify-between text-sm text-text-primary">
              <span>{monthlyTotal.input.toLocaleString()} in / {monthlyTotal.output.toLocaleString()} out</span>
              <span className="text-text-secondary">~${monthlyCost.toFixed(2)}</span>
            </div>
          </div>

          <div>
            <h3 className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-text-secondary">Recent requests</h3>
            {recent.length === 0 ? (
              <p className="text-xs text-text-secondary">No AI requests yet.</p>
            ) : (
              <ul className="flex max-h-48 flex-col gap-1.5 overflow-y-auto">
                {recent.map((r) => (
                  <li key={r.id} className="flex items-center justify-between text-xs">
                    <span className="font-medium text-text-primary">{r.model}</span>
                    <span className="text-text-secondary">
                      in:{r.inputTokens} out:{r.outputTokens} · {formatTimestamp(r.timestamp)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
      </PopoverContent>
    </Popover>
  )
}
