import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'
import { AlertTriangle, Bug, Calendar, Copy, Cpu, KeyRound, LogOut, Monitor, Moon, RefreshCw, Sparkles, Sun } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { TextField } from '@/components/ui/TextField'
import { cn } from '@/lib/utils'
import { useAuth } from '@/auth/useAuth'
import { supabase } from '@/lib/supabaseClient'
import { getTheme, setTheme, type Theme } from '@/theme/theme'
import { loadStoredApiKey, storeApiKey } from '@/ai/session/chatStore'
import { getProvider, setProvider, isWebGPUSupported, type AIProvider } from '@/ai/provider'
import { getRoutingOverride, setRoutingOverride, type RoutingOverride } from '@/ai/router'
import { allRecords, recordsThisMonth, totalCostUSD, totalTokensThisMonth, type AIRequestRecord } from '@/ai/telemetry'
import { isGoogleOAuthConfigured, buildGoogleAuthUrl, googleOAuthRedirectUri } from '@/google/oauth'
import { getConnections, disconnectGoogleCalendar, type GoogleConnection } from '@/google/connection'
import { syncGoogleCalendarNow } from '@/google/sync'
import { removeLinksForConnection } from '@/google/links'

const THEME_OPTIONS: { value: Theme; label: string; Icon: typeof Sun }[] = [
  { value: 'system', label: 'System', Icon: Monitor },
  { value: 'light', label: 'Light', Icon: Sun },
  { value: 'dark', label: 'Dark', Icon: Moon },
]

const ROUTING_OPTIONS: { value: RoutingOverride; label: string }[] = [
  { value: 'none', label: 'Auto' },
  { value: 'always_opus', label: 'Always Opus' },
  { value: 'prefer_cheap', label: 'Prefer cheap' },
]

function SettingsSection({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <section className="mb-6 rounded-leo-md border border-divider bg-surface p-4">
      <h2 className="text-sm font-semibold text-text-primary">{title}</h2>
      {description && <p className="mt-0.5 mb-3 text-xs text-text-secondary">{description}</p>}
      <div className={description ? '' : 'mt-3'}>{children}</div>
    </section>
  )
}

function formatTimestamp(iso: string): string {
  const d = new Date(iso)
  const now = new Date()
  const diffMin = Math.round((now.getTime() - d.getTime()) / 60_000)
  if (diffMin < 1) return 'just now'
  if (diffMin < 60) return `${diffMin}m ago`
  const diffHr = Math.round(diffMin / 60)
  if (diffHr < 24) return `${diffHr}h ago`
  return d.toLocaleDateString()
}

/**
 * Consolidates preferences that were previously scattered — AISettingsPanel's
 * popover (routing + usage), ChatPage's inline API-key gate and provider
 * switch buttons, and the sidebar's bare sign-out — into one place, plus a
 * genuinely new preference (Appearance) that didn't exist in any form
 * before: dark/light was previously prefers-color-scheme only, no manual
 * override. ChatPage's own inline controls are left as-is, not removed —
 * they read/write the same localStorage-backed functions as this page, so
 * a change made here is picked up there immediately and vice versa.
 */
export function SettingsPage() {
  const { session } = useAuth()

  const [theme, setThemeState] = useState<Theme>(() => getTheme())

  const [apiKey, setApiKeyState] = useState(() => loadStoredApiKey())
  const [keyInput, setKeyInput] = useState('')

  const [provider, setProviderState] = useState<AIProvider>(() => getProvider())
  const [routingOverride, setRoutingOverrideState] = useState<RoutingOverride>(() => getRoutingOverride())

  const [records, setRecords] = useState<AIRequestRecord[]>([])
  const [monthlyTotal, setMonthlyTotal] = useState({ input: 0, output: 0 })

  useEffect(() => {
    setRecords(allRecords())
    setMonthlyTotal(totalTokensThisMonth())
  }, [])

  const [googleConnections, setGoogleConnections] = useState<GoogleConnection[] | 'loading'>('loading')
  const [syncing, setSyncing] = useState(false)

  function reloadGoogleConnections() {
    getConnections()
      .then(setGoogleConnections)
      .catch(() => setGoogleConnections([]))
  }

  useEffect(() => {
    reloadGoogleConnections()
  }, [])

  function handleConnectGoogle(reconnectConnectionId?: string) {
    window.location.href = buildGoogleAuthUrl(reconnectConnectionId)
  }

  async function handleDisconnectGoogle(connection: GoogleConnection) {
    await disconnectGoogleCalendar(connection.id)
    await removeLinksForConnection(connection.id)
    reloadGoogleConnections()
  }

  async function handleSyncNow() {
    setSyncing(true)
    try {
      await syncGoogleCalendarNow()
    } catch {
      // syncGoogleCalendarNow already toasts the failure — nothing more to do here.
    } finally {
      setSyncing(false)
    }
  }

  function handleThemeChange(next: Theme) {
    setTheme(next)
    setThemeState(next)
  }

  function handleSaveKey(e: FormEvent) {
    e.preventDefault()
    const trimmed = keyInput.trim()
    if (!trimmed) return
    storeApiKey(trimmed)
    setApiKeyState(trimmed)
    setKeyInput('')
  }

  function handleRemoveKey() {
    storeApiKey('')
    setApiKeyState('')
  }

  function handleProviderChange(next: AIProvider) {
    setProvider(next)
    setProviderState(next)
  }

  function handleRoutingChange(next: RoutingOverride) {
    setRoutingOverride(next)
    setRoutingOverrideState(next)
  }

  const monthlyCost = recordsThisMonth().reduce((sum, r) => sum + totalCostUSD(r), 0)
  const recent = [...records].reverse().slice(0, 20)

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-text-primary">Settings</h1>
      <p className="mb-4 text-sm text-text-secondary">Appearance, AI, and account preferences.</p>

      <SettingsSection title="Appearance" description="Choose how LEO looks, or follow your system setting.">
        <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
          {THEME_OPTIONS.map(({ value, label, Icon }) => (
            <button
              key={value}
              type="button"
              onClick={() => handleThemeChange(value)}
              aria-pressed={theme === value}
              className={cn(
                'flex flex-1 items-center justify-center gap-1.5 rounded-leo-sm py-1.5 text-xs font-medium transition-colors',
                theme === value ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
              )}
            >
              <Icon className="h-3.5 w-3.5" aria-hidden="true" />
              {label}
            </button>
          ))}
        </div>
      </SettingsSection>

      <SettingsSection title="AI provider" description="Claude needs an API key and costs money to run; the on-device model is free but slower and less reliable.">
        <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
          <button
            type="button"
            onClick={() => handleProviderChange('claude')}
            aria-pressed={provider === 'claude'}
            className={cn(
              'flex flex-1 items-center justify-center gap-1.5 rounded-leo-sm py-1.5 text-xs font-medium transition-colors',
              provider === 'claude' ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
            )}
          >
            <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
            Claude
          </button>
          <button
            type="button"
            onClick={() => handleProviderChange('webllm')}
            disabled={!isWebGPUSupported()}
            aria-pressed={provider === 'webllm'}
            title={isWebGPUSupported() ? undefined : "This browser doesn't support WebGPU"}
            className={cn(
              'flex flex-1 items-center justify-center gap-1.5 rounded-leo-sm py-1.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-40',
              provider === 'webllm' ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
            )}
          >
            <Cpu className="h-3.5 w-3.5" aria-hidden="true" />
            On-device (free)
          </button>
        </div>
      </SettingsSection>

      <SettingsSection title="Claude API key" description="Stored in this browser's local storage, sent to our proxy which forwards it to Anthropic.">
        {apiKey ? (
          <div className="flex items-center justify-between gap-2">
            <span className="flex items-center gap-1.5 text-sm text-text-primary">
              <KeyRound className="h-3.5 w-3.5 text-text-secondary" aria-hidden="true" />
              •••• {apiKey.slice(-4)}
            </span>
            <Button variant="ghost" size="sm" onClick={handleRemoveKey} className="text-text-secondary">
              Remove
            </Button>
          </div>
        ) : (
          <form onSubmit={handleSaveKey} className="flex gap-2">
            <TextField
              label="Anthropic API key"
              type="password"
              className="flex-1"
              value={keyInput}
              onChange={(e) => setKeyInput(e.target.value)}
            />
            <Button type="submit" className="self-end">
              Save
            </Button>
          </form>
        )}
      </SettingsSection>

      <SettingsSection title="Model routing" description="Which Claude model handles a request, when Claude mode is active.">
        <div className="flex gap-1 rounded-leo-md bg-surface-elevated p-1">
          {ROUTING_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              type="button"
              onClick={() => handleRoutingChange(opt.value)}
              aria-pressed={routingOverride === opt.value}
              className={cn(
                'flex-1 rounded-leo-sm py-1.5 text-xs font-medium transition-colors',
                routingOverride === opt.value ? 'bg-surface text-text-primary shadow-sm' : 'text-text-secondary hover:text-text-primary',
              )}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </SettingsSection>

      <SettingsSection title="AI usage">
        <div className="mb-3 flex justify-between text-sm text-text-primary">
          <span>This month: {monthlyTotal.input.toLocaleString()} in / {monthlyTotal.output.toLocaleString()} out</span>
          <span className="text-text-secondary">~${monthlyCost.toFixed(2)}</span>
        </div>
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
      </SettingsSection>

      <SettingsSection
        title="Google Calendar"
        description="Two-way sync — events created/edited/deleted in LEO push to Google, and Google's own changes pull in here. Tasks and other LEO-native items are never pushed to Google."
      >
        {!isGoogleOAuthConfigured() ? (
          <div className="flex flex-col gap-2 text-xs text-text-secondary">
            <p>One-time setup — needs a Google account, ~5 minutes, only you can do this step (it's tied to your own Google account):</p>
            <ol className="ml-4 list-decimal space-y-1.5">
              <li>
                <a
                  href="https://console.cloud.google.com/apis/credentials/consent"
                  target="_blank"
                  rel="noreferrer"
                  className="text-accent hover:underline"
                >
                  OAuth consent screen
                </a>
                : User type <strong>External</strong> → fill in app name + your email → add yourself under{' '}
                <strong>Test users</strong> (keeps it in Testing mode — skips Google's app-review process entirely).
              </li>
              <li>
                <a href="https://console.cloud.google.com/apis/credentials" target="_blank" rel="noreferrer" className="text-accent hover:underline">
                  Create Credentials → OAuth client ID
                </a>
                , type <strong>Web application</strong>, with this exact Authorized redirect URI:
              </li>
            </ol>
            <div className="flex items-center gap-1.5 rounded-leo-sm bg-surface-elevated px-2 py-1.5">
              <code className="flex-1 truncate font-mono">{googleOAuthRedirectUri()}</code>
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label="Copy redirect URI"
                onClick={() => {
                  void navigator.clipboard.writeText(googleOAuthRedirectUri())
                  toast.success('Copied')
                }}
              >
                <Copy className="h-3.5 w-3.5" />
              </Button>
            </div>
            <ol start={3} className="ml-4 list-decimal space-y-1.5">
              <li>
                Copy the resulting <strong>Client ID</strong> and <strong>Client secret</strong> into <code className="font-mono">.env.local</code> (or your Vercel project's env vars) as{' '}
                <code className="font-mono">VITE_GOOGLE_CLIENT_ID</code> and <code className="font-mono">GOOGLE_CLIENT_SECRET</code>, then restart the dev server.
              </li>
            </ol>
          </div>
        ) : googleConnections === 'loading' ? (
          <p className="text-xs text-text-secondary">Loading…</p>
        ) : (
          <div className="flex flex-col gap-3">
            {googleConnections.length > 0 && (
              <ul className="flex flex-col gap-1.5">
                {googleConnections.map((connection) => (
                  <li key={connection.id} className="flex flex-col gap-1 rounded-leo-sm bg-surface-elevated px-2.5 py-1.5">
                    <div className="flex items-center justify-between gap-2">
                      <span className="flex items-center gap-1.5 text-sm text-text-primary">
                        {connection.needsReauth ? (
                          <AlertTriangle className="h-3.5 w-3.5 text-danger" aria-hidden="true" />
                        ) : (
                          <Calendar className="h-3.5 w-3.5 text-success" aria-hidden="true" />
                        )}
                        {connection.googleEmail ?? 'Connected account'}
                      </span>
                      <div className="flex gap-1">
                        {connection.needsReauth && (
                          <Button variant="outline" size="sm" onClick={() => handleConnectGoogle(connection.id)} className="gap-1">
                            Reconnect
                          </Button>
                        )}
                        <Button variant="ghost" size="sm" onClick={() => void handleDisconnectGoogle(connection)} className="text-text-secondary">
                          Disconnect
                        </Button>
                      </div>
                    </div>
                    {connection.needsReauth && (
                      <p className="text-xs text-danger">Access expired — reconnect to resume syncing this account.</p>
                    )}
                  </li>
                ))}
              </ul>
            )}
            <div className="flex gap-1.5">
              <Button variant="outline" onClick={() => handleConnectGoogle()} className="gap-1.5">
                <Calendar className="h-3.5 w-3.5" aria-hidden="true" />
                {googleConnections.length > 0 ? 'Add another account' : 'Connect Google Calendar'}
              </Button>
              {googleConnections.length > 0 && (
                <Button variant="ghost" onClick={() => void handleSyncNow()} disabled={syncing} className="gap-1.5 text-text-secondary">
                  <RefreshCw className={cn('h-3.5 w-3.5', syncing && 'animate-spin')} aria-hidden="true" />
                  {syncing ? 'Syncing…' : 'Sync now'}
                </Button>
              )}
            </div>
          </div>
        )}
      </SettingsSection>

      <SettingsSection title="Account">
        <div className="flex items-center justify-between gap-2">
          <span className="text-sm text-text-primary">{session?.user.email}</span>
          <Button variant="ghost" size="sm" onClick={() => void supabase.auth.signOut()} className="gap-1.5 text-text-secondary">
            <LogOut className="h-3.5 w-3.5" aria-hidden="true" />
            Sign out
          </Button>
        </div>
      </SettingsSection>

      <SettingsSection title="Developer" description="Raw database view — view, create, edit, and bulk-delete every Item, Habit, and Measurement directly.">
        <Link to="/debug">
          <Button variant="outline" size="sm" className="gap-1.5">
            <Bug className="h-3.5 w-3.5" aria-hidden="true" />
            Open Debug
          </Button>
        </Link>
      </SettingsSection>
    </div>
  )
}
