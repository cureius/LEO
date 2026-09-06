import { useMemo } from 'react'
import { useShallow } from 'zustand/react/shallow'
import { Sparkles } from 'lucide-react'
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Pie,
  PieChart,
  PolarAngleAxis,
  PolarGrid,
  PolarRadiusAxis,
  Radar,
  RadarChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { selectHabitsArray, selectItemsArray, useSyncStore } from '@/sync/store'
import { computeDashboardStats, type DashboardStats } from '@/domain/dashboardStats'
import { kindLabel } from '@/domain/itemDisplay'
import { tagColorHex } from '@/domain/tagColors'
import { cn } from '@/lib/utils'
import type { ItemKind } from '@/domain/types'

/**
 * Read-only stats/insights view — computeDashboardStats (domain/dashboardStats.ts)
 * owns all the actual number-crunching; this file is purely presentation
 * (cards + recharts wiring). No writes happen anywhere on this page.
 */

const TOOLTIP_STYLE: React.CSSProperties = {
  background: 'var(--color-surface)',
  border: '1px solid var(--color-divider)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--color-text-primary)',
}
const AXIS_TICK = { fill: 'var(--color-text-secondary)', fontSize: 11 }
const KIND_COLORS = ['var(--color-accent)', '#14b8a6', '#f97316', '#a855f7', '#eab308', '#ec4899', '#22c55e']
// Radar axis labels sit right at the card edge with little room to grow —
// confirmed live: an unclipped tag name like "Home Renovation Project"
// overflowed the card boundary entirely. Full name is still available via
// the tooltip.
const RADAR_LABEL_MAX = 14
function truncateRadarLabel(name: string): string {
  return name.length > RADAR_LABEL_MAX ? `${name.slice(0, RADAR_LABEL_MAX - 1)}…` : name
}
const IMPORTANCE_COLORS = ['var(--color-text-secondary)', 'var(--color-accent)', 'var(--color-warning)', 'var(--color-danger)']

function StatCard({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <div className="rounded-leo-md border border-divider bg-surface p-4">
      <p className="text-xs font-medium tracking-wide text-text-secondary uppercase">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-text-primary">{value}</p>
      {hint && <p className="mt-0.5 text-xs text-text-secondary">{hint}</p>}
    </div>
  )
}

function ChartCard({ title, children, className }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn('rounded-leo-md border border-divider bg-surface p-4', className)}>
      <h2 className="mb-3 text-xs font-medium tracking-wide text-text-secondary uppercase">{title}</h2>
      {children}
    </div>
  )
}

/** A handful of plain-English observations derived from the same numbers
 *  the charts show — not AI-generated, just simple threshold heuristics
 *  over stats that were already computed. Capped at 4 so this stays a
 *  glance, not another list to read. */
function buildInsights(stats: DashboardStats): string[] {
  const lines: string[] = []

  if (stats.overdueCount > 0) {
    lines.push(`${stats.overdueCount} item${stats.overdueCount === 1 ? ' is' : 's are'} overdue — worth a look.`)
  }
  if (stats.completionRate30d >= 80) {
    lines.push(`Strong follow-through: ${stats.completionRate30d}% of what was due in the last 30 days got done.`)
  } else if (stats.completionRate30d > 0 && stats.completionRate30d < 40) {
    lines.push(`Only ${stats.completionRate30d}% of items due in the last 30 days were completed — might be worth trimming what's committed.`)
  }
  const busiestDay = stats.scheduledHoursByDay.reduce((max, d) => (d.hours > max.hours ? d : max), stats.scheduledHoursByDay[0])
  if (busiestDay && busiestDay.hours >= 6) {
    lines.push(`${busiestDay.label} is your heaviest day ahead — ${busiestDay.hours}h already scheduled.`)
  }
  if (stats.byProject.length > 0) {
    const top = stats.byProject[0]
    lines.push(`"${top.name}" is your biggest active project — ${top.openCount} open item${top.openCount === 1 ? '' : 's'}.`)
  }
  if (stats.bestStreak >= 7) {
    lines.push(`Nice streak — ${stats.bestStreak} days running on your best habit.`)
  }
  return lines.slice(0, 4)
}

export function DashboardPage() {
  const items = useSyncStore(useShallow(selectItemsArray))
  const habits = useSyncStore(useShallow(selectHabitsArray))
  const initialLoadComplete = useSyncStore((s) => s.initialLoadComplete)

  const stats = useMemo(() => computeDashboardStats(items, habits), [items, habits])
  const insights = useMemo(() => buildInsights(stats), [stats])

  return (
    <div className="p-6">
      <h1 className="mb-1 text-xl font-semibold text-text-primary">Dashboard</h1>
      <p className="mb-4 text-sm text-text-secondary">Stats, workload, and trends across everything you're tracking.</p>

      {!initialLoadComplete && <p className="text-sm text-text-secondary">Loading…</p>}

      {initialLoadComplete && (
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            <StatCard label="Open" value={stats.openCount} />
            <StatCard label="Completed this week" value={stats.completedThisWeek} />
            <StatCard label="Overdue" value={stats.overdueCount} hint={stats.overdueCount > 0 ? 'needs attention' : 'all clear'} />
            <StatCard label="30-day completion rate" value={`${stats.completionRate30d}%`} />
            <StatCard label="Best habit streak" value={`${stats.bestStreak}d`} hint={`${stats.activeHabitCount} active habit${stats.activeHabitCount === 1 ? '' : 's'}`} />
          </div>

          {insights.length > 0 && (
            <div className="rounded-leo-md border border-divider bg-surface p-4">
              <h2 className="mb-2 text-xs font-medium tracking-wide text-text-secondary uppercase">Insights</h2>
              <ul className="flex flex-col gap-1.5">
                {insights.map((line) => (
                  <li key={line} className="flex items-start gap-2 text-sm text-text-primary">
                    <Sparkles className="mt-0.5 h-3.5 w-3.5 shrink-0 text-accent" aria-hidden="true" />
                    {line}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
            <ChartCard title="Completions — this month">
              <ResponsiveContainer width="100%" height={220}>
                <AreaChart data={stats.completionsByDay}>
                  <CartesianGrid stroke="var(--color-divider)" vertical={false} />
                  <XAxis dataKey="label" tick={AXIS_TICK} axisLine={{ stroke: 'var(--color-divider)' }} tickLine={false} />
                  <YAxis allowDecimals={false} tick={AXIS_TICK} axisLine={false} tickLine={false} width={28} />
                  <Tooltip contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--color-text-secondary)' }} />
                  <Area type="monotone" dataKey="count" name="Completed" stroke="var(--color-accent)" fill="var(--color-accent-muted)" strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            </ChartCard>

            <ChartCard title="Scheduled hours — next 7 days">
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={stats.scheduledHoursByDay}>
                  <CartesianGrid stroke="var(--color-divider)" vertical={false} />
                  <XAxis dataKey="label" tick={AXIS_TICK} axisLine={{ stroke: 'var(--color-divider)' }} tickLine={false} />
                  <YAxis allowDecimals={false} tick={AXIS_TICK} axisLine={false} tickLine={false} width={28} />
                  <Tooltip contentStyle={TOOLTIP_STYLE} labelStyle={{ color: 'var(--color-text-secondary)' }} formatter={(v) => [`${v}h`, 'Scheduled']} />
                  <Bar dataKey="hours" name="Hours" fill="var(--color-accent)" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </ChartCard>

            <ChartCard title="Open items by project">
              {stats.byProject.length === 0 ? (
                <p className="text-sm text-text-secondary">No projects yet.</p>
              ) : (
                <ResponsiveContainer width="100%" height={Math.max(160, stats.byProject.length * 34)}>
                  <BarChart data={stats.byProject} layout="vertical" margin={{ left: 8, right: 16 }}>
                    <XAxis type="number" allowDecimals={false} tick={AXIS_TICK} axisLine={{ stroke: 'var(--color-divider)' }} tickLine={false} />
                    <YAxis type="category" dataKey="name" width={100} tick={{ fill: 'var(--color-text-primary)', fontSize: 12 }} axisLine={false} tickLine={false} />
                    <Tooltip contentStyle={TOOLTIP_STYLE} />
                    <Bar dataKey="openCount" name="Open items" radius={[0, 4, 4, 0]}>
                      {stats.byProject.map((p) => (
                        <Cell key={p.name} fill={tagColorHex(p.color)} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              )}
            </ChartCard>

            <ChartCard title="Completion rate by project">
              {stats.byProject.length === 0 ? (
                <p className="text-sm text-text-secondary">No projects yet.</p>
              ) : (
                <ResponsiveContainer width="100%" height={260}>
                  <RadarChart data={stats.byProject} outerRadius="62%" margin={{ top: 8, right: 24, bottom: 8, left: 24 }}>
                    <PolarGrid stroke="var(--color-divider)" />
                    <PolarAngleAxis dataKey="name" tickFormatter={truncateRadarLabel} tick={{ fill: 'var(--color-text-primary)', fontSize: 12 }} />
                    <PolarRadiusAxis domain={[0, 100]} tickFormatter={(v) => `${v}%`} tick={AXIS_TICK} axisLine={false} />
                    <Tooltip
                      contentStyle={TOOLTIP_STYLE}
                      formatter={(value, _name, item) => [`${value}% (${item.payload.completedCount}/${item.payload.totalCount})`, 'Completion rate']}
                    />
                    <Radar
                      dataKey="completionRate"
                      name="Completion rate"
                      stroke="var(--color-accent)"
                      fill="var(--color-accent)"
                      fillOpacity={0.25}
                      strokeWidth={2}
                      dot={{ r: 4, fill: 'var(--color-accent)', stroke: 'var(--color-surface)', strokeWidth: 2 }}
                    />
                  </RadarChart>
                </ResponsiveContainer>
              )}
            </ChartCard>

            <ChartCard title="Open items by kind">
              {stats.byKind.length === 0 ? (
                <p className="text-sm text-text-secondary">Nothing open right now.</p>
              ) : (
                <ResponsiveContainer width="100%" height={220}>
                  <PieChart>
                    <Pie data={stats.byKind} dataKey="count" nameKey="kind" innerRadius={50} outerRadius={80} paddingAngle={2}>
                      {stats.byKind.map((k, i) => (
                        <Cell key={k.kind} fill={KIND_COLORS[i % KIND_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value, name) => [value, kindLabel(name as ItemKind)]} />
                    <Legend formatter={(value: string) => kindLabel(value as ItemKind)} wrapperStyle={{ fontSize: 12, color: 'var(--color-text-secondary)' }} />
                  </PieChart>
                </ResponsiveContainer>
              )}
            </ChartCard>

            <ChartCard title="Open items by importance">
              <ResponsiveContainer width="100%" height={180}>
                <BarChart data={stats.byImportance}>
                  <CartesianGrid stroke="var(--color-divider)" vertical={false} />
                  <XAxis dataKey="label" tick={AXIS_TICK} axisLine={{ stroke: 'var(--color-divider)' }} tickLine={false} />
                  <YAxis allowDecimals={false} tick={AXIS_TICK} axisLine={false} tickLine={false} width={28} />
                  <Tooltip contentStyle={TOOLTIP_STYLE} />
                  <Bar dataKey="count" name="Items" radius={[4, 4, 0, 0]}>
                    {stats.byImportance.map((b) => (
                      <Cell key={b.importance} fill={IMPORTANCE_COLORS[b.importance]} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </ChartCard>

            <ChartCard title="Habit streaks">
              {stats.habitStreaks.length === 0 ? (
                <p className="text-sm text-text-secondary">No active habits.</p>
              ) : (
                <ul className="flex flex-col gap-2.5">
                  {stats.habitStreaks.map((h) => (
                    <li key={h.name} className="flex items-center gap-3">
                      <span className="w-28 shrink-0 truncate text-sm text-text-primary">{h.name}</span>
                      <div className="h-2 flex-1 overflow-hidden rounded-full bg-surface-elevated">
                        <div className="h-full rounded-full bg-accent" style={{ width: `${Math.min(100, h.streak * 10)}%` }} />
                      </div>
                      <span className="w-10 shrink-0 text-right text-xs text-text-secondary">{h.streak}d</span>
                    </li>
                  ))}
                </ul>
              )}
            </ChartCard>
          </div>
        </div>
      )}
    </div>
  )
}
