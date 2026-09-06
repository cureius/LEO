import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { NavLink, Outlet } from 'react-router-dom'
import * as Dialog from '@radix-ui/react-dialog'
import { cn } from '@/lib/utils'
import { RESPONSIVE_DIALOG_CONTENT, RESPONSIVE_DIALOG_OVERLAY } from '@/components/ui/responsiveDialog'
import {
  Sun,
  Inbox as InboxIcon,
  Repeat,
  Sparkles,
  Dumbbell,
  LogOut,
  Settings,
  FolderKanban,
  LayoutDashboard,
  Menu,
  Ticket,
  X,
  RefreshCw,
} from 'lucide-react'
import { useAuth } from '@/auth/useAuth'
import { supabase } from '@/lib/supabaseClient'
import { useSyncStore } from '@/sync/store'
import { refreshAll } from '@/sync/engine'
import { startAlarmScheduler, stopAlarmScheduler } from '@/alarms/scheduler'
import { AlarmBanner } from '@/alarms/AlarmBanner'
import { GlobalSearch } from '@/components/search/GlobalSearch'
import { loadGoogleLinks } from '@/google/links'
import { startGoogleCalendarSync, stopGoogleCalendarSync, syncGoogleCalendarNow } from '@/google/sync'
import { loadRules } from '@/sync/rules'

const navSections = [
  {
    label: 'Planning',
    items: [
      { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
      { to: '/today', label: 'Today', icon: Sun },
      { to: '/inbox', label: 'Inbox', icon: InboxIcon },
      { to: '/habits', label: 'Habits', icon: Repeat },
      { to: '/projects', label: 'Projects', icon: FolderKanban },
    ],
  },
  {
    label: 'Tools',
    items: [
      { to: '/fitness', label: 'Fitness', icon: Dumbbell },
      { to: '/jira', label: 'Jira', icon: Ticket },
      { to: '/chat', label: 'Ask LEO', icon: Sparkles },
    ],
  },
]

// A bottom tab bar reads as native on a phone only up to about 5 items
// before labels start truncating/cramping — these are the ones someone
// reaches for every day. Everything else (Dashboard, Fitness, Ask LEO,
// Settings, sign out) lives one tap away behind "More" instead of being
// permanently docked but squeezed.
const PRIMARY_MOBILE_NAV = [
  { to: '/today', label: 'Today', icon: Sun },
  { to: '/inbox', label: 'Inbox', icon: InboxIcon },
  { to: '/habits', label: 'Habits', icon: Repeat },
  { to: '/projects', label: 'Projects', icon: FolderKanban },
]

const MORE_MOBILE_NAV = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/fitness', label: 'Fitness', icon: Dumbbell },
  { to: '/jira', label: 'Jira', icon: Ticket },
  { to: '/chat', label: 'Ask LEO', icon: Sparkles },
]

function navLinkClass({ isActive }: { isActive: boolean }) {
  return cn(
    'flex items-center gap-2 rounded-leo-sm px-2 py-1.5 text-sm',
    isActive ? 'bg-accent-muted font-medium text-accent' : 'text-text-primary hover:bg-surface-elevated',
  )
}

function ConnectionDot({ connectionStatus }: { connectionStatus: string }) {
  return (
    <span
      className={cn(
        'h-2 w-2 shrink-0 rounded-full',
        connectionStatus === 'connected' ? 'bg-success' : connectionStatus === 'connecting' ? 'bg-warning' : 'bg-danger',
      )}
      aria-hidden="true"
    />
  )
}

/** The mobile-only "More" sheet: everything that doesn't fit in the bottom
 *  tab bar, plus account/settings — a bottom sheet (not a full nav
 *  redesign) since it's just an overflow drawer, not a primary surface. */
async function hardRefresh() {
  try {
    await Promise.all([refreshAll(), syncGoogleCalendarNow()])
    toast.success('Refreshed')
  } catch (err) {
    console.error('[sync] hard refresh failed', err)
    toast.error('Refresh failed')
  }
}

function MoreSheet({
  session,
  connectionStatus,
  onClose,
}: {
  session: ReturnType<typeof useAuth>['session']
  connectionStatus: string
  onClose: () => void
}) {
  return (
    <Dialog.Root open onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className={RESPONSIVE_DIALOG_OVERLAY} />
        <Dialog.Content className={cn(RESPONSIVE_DIALOG_CONTENT, 'flex max-h-[80vh] flex-col bg-surface p-4 shadow-xl')}>
          <div className="mb-3 flex items-center justify-between">
            <Dialog.Title className="text-sm font-medium text-text-primary">More</Dialog.Title>
            <Dialog.Close asChild>
              <button aria-label="Close" className="rounded-leo-sm p-2 text-text-secondary hover:bg-surface-elevated">
                <X className="h-4 w-4" />
              </button>
            </Dialog.Close>
          </div>

          <ul className="flex flex-col gap-0.5">
            {MORE_MOBILE_NAV.map(({ to, label, icon: Icon }) => (
              <li key={to}>
                <NavLink to={to} onClick={onClose} className={({ isActive }) => cn(navLinkClass({ isActive }), 'py-2.5')}>
                  <Icon className="h-4 w-4" aria-hidden="true" />
                  {label}
                </NavLink>
              </li>
            ))}
          </ul>

          <div className="mt-3 flex flex-col gap-0.5 border-t border-divider pt-3">
            <NavLink to="/settings" onClick={onClose} className={({ isActive }) => cn(navLinkClass({ isActive }), 'py-2.5')}>
              <Settings className="h-4 w-4" aria-hidden="true" />
              Settings
            </NavLink>
            <div className="flex items-center gap-2 px-2 py-1.5 text-xs text-text-secondary">
              <ConnectionDot connectionStatus={connectionStatus} />
              {connectionStatus === 'connected' ? 'Live' : connectionStatus === 'connecting' ? 'Connecting…' : 'Offline'}
            </div>
            <p className="truncate px-2 py-1 text-xs text-text-secondary">{session?.user.email}</p>
            <button
              type="button"
              onClick={() => void hardRefresh()}
              className="flex items-center gap-2 rounded-leo-sm px-2 py-2.5 text-left text-sm text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
            >
              <RefreshCw className="h-4 w-4" aria-hidden="true" />
              Refresh
            </button>
            <button
              type="button"
              onClick={() => void supabase.auth.signOut()}
              className="flex items-center gap-2 rounded-leo-sm px-2 py-2.5 text-left text-sm text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
            >
              <LogOut className="h-4 w-4" aria-hidden="true" />
              Sign out
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

export function AppShell() {
  const { session } = useAuth()
  const connectionStatus = useSyncStore((s) => s.connectionStatus)
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)
  const [moreOpen, setMoreOpen] = useState(false)

  useEffect(() => {
    startAlarmScheduler()
    return () => stopAlarmScheduler()
  }, [])

  useEffect(() => {
    // Gated on initialLoadComplete — confirmed live: without this, Google
    // Calendar sync could start (via AuthProvider's own, separately-triggered
    // core items fetch) BEFORE that fetch had populated the items map. An
    // already-linked event's item lookup came back empty, sync.ts concluded
    // it wasn't linked yet, created a duplicate, and then failed to save
    // THAT duplicate's link (the real one already existed) — leaving one
    // more orphaned duplicate item behind on every single page load.
    // loadGoogleLinks itself must also still resolve before the first sync
    // pass for the same reason, just against the googleLinks map instead of
    // the items map.
    if (!initialLoadComplete) return
    let cancelled = false
    loadGoogleLinks()
      .then(() => {
        if (!cancelled) startGoogleCalendarSync()
      })
      .catch((err) => console.warn('[google-calendar] could not load links:', err))
    return () => {
      cancelled = true
      stopGoogleCalendarSync()
    }
  }, [initialLoadComplete])

  useEffect(() => {
    // Same gate as Google links above, though for a simpler reason here:
    // there's no item-lookup race to worry about (rules don't touch items
    // until the user hits "Run rules now"), just no point fetching rules
    // before there's a signed-in session driving the rest of the load.
    if (!initialLoadComplete) return
    loadRules().catch((err) => console.warn('[automation-rules] could not load rules:', err))
  }, [initialLoadComplete])

  return (
    <div className="flex h-dvh flex-col bg-background">
      <AlarmBanner />
      <GlobalSearch />

      {/* Mobile-only top bar — just identity + a way into the overflow
          menu; the bottom tab bar below is the real navigation surface, this
          mirrors how native apps keep the top bar minimal on phones. */}
      <div
        className="flex shrink-0 items-center justify-between border-b border-divider bg-surface px-4 py-3 md:hidden"
        style={{ paddingTop: 'calc(0.75rem + env(safe-area-inset-top))' }}
      >
        <span className="text-lg font-semibold text-text-primary">LEO</span>
        <button
          type="button"
          onClick={() => setMoreOpen(true)}
          aria-label="More"
          className="rounded-leo-sm p-2 text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
        >
          <Menu className="h-5 w-5" aria-hidden="true" />
        </button>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* Desktop/tablet sidebar — unchanged, just hidden below md: now. */}
        <nav aria-label="Main" className="hidden w-56 flex-col border-r border-divider bg-surface p-3 md:flex">
          <div className="mb-4 px-2">
            <span className="text-lg font-semibold text-text-primary">LEO</span>
          </div>

          {navSections.map((section) => (
            <div key={section.label} className="mb-4">
              <p className="mb-1 px-2 text-xs font-medium uppercase tracking-wide text-text-secondary">{section.label}</p>
              <ul className="flex flex-col gap-0.5">
                {section.items.map(({ to, label, icon: Icon }) => (
                  <li key={to}>
                    <NavLink to={to} className={navLinkClass}>
                      <Icon className="h-4 w-4" aria-hidden="true" />
                      {label}
                    </NavLink>
                  </li>
                ))}
              </ul>
            </div>
          ))}

          <div className="mt-auto flex flex-col gap-2 border-t border-divider pt-3">
            <div className="flex items-center gap-2 px-2 text-xs text-text-secondary">
              <ConnectionDot connectionStatus={connectionStatus} />
              {connectionStatus === 'connected' ? 'Live' : connectionStatus === 'connecting' ? 'Connecting…' : 'Offline'}
            </div>
            <NavLink to="/settings" className={navLinkClass}>
              <Settings className="h-4 w-4" aria-hidden="true" />
              Settings
            </NavLink>
            <button
              type="button"
              onClick={() => void hardRefresh()}
              className="flex items-center gap-2 rounded-leo-sm px-2 py-1.5 text-left text-sm text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
            >
              <RefreshCw className="h-4 w-4" aria-hidden="true" />
              Refresh
            </button>
            <p className="truncate px-2 text-xs text-text-secondary">{session?.user.email}</p>
            <button
              type="button"
              onClick={() => void supabase.auth.signOut()}
              className="flex items-center gap-2 rounded-leo-sm px-2 py-1.5 text-left text-sm text-text-secondary hover:bg-surface-elevated hover:text-text-primary"
            >
              <LogOut className="h-4 w-4" aria-hidden="true" />
              Sign out
            </button>
          </div>
        </nav>

        {/* Bottom padding on mobile reserves space for the fixed tab bar
            below so the last row of content is never hidden behind it. */}
        <main className="flex-1 overflow-y-auto pb-[calc(4rem+env(safe-area-inset-bottom))] md:pb-0">
          <Outlet />
        </main>
      </div>

      {/* Mobile-only bottom tab bar — fixed, safe-area-aware, the primary
          navigation surface on a phone (the sidebar above is display:none
          here, not just visually hidden, so it costs nothing on mobile). */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-30 flex border-t border-divider bg-surface md:hidden"
        style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
      >
        {PRIMARY_MOBILE_NAV.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              cn(
                'flex flex-1 flex-col items-center gap-0.5 py-2 text-[11px] font-medium',
                isActive ? 'text-accent' : 'text-text-secondary',
              )
            }
          >
            <Icon className="h-5 w-5" aria-hidden="true" />
            {label}
          </NavLink>
        ))}
        <button
          type="button"
          onClick={() => setMoreOpen(true)}
          className="flex flex-1 flex-col items-center gap-0.5 py-2 text-[11px] font-medium text-text-secondary"
        >
          <Menu className="h-5 w-5" aria-hidden="true" />
          More
        </button>
      </nav>

      {moreOpen && <MoreSheet session={session} connectionStatus={connectionStatus} onClose={() => setMoreOpen(false)} />}
    </div>
  )
}
