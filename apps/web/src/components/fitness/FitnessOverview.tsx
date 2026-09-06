import { Flame, Minus, Target, TrendingDown, TrendingUp } from 'lucide-react'
import { bmi, tdee } from '@/ai/bodyMath'
import { cn } from '@/lib/utils'
import type { BodyProfile, Measurement, MealItem, WorkoutItem } from '@/domain/types'

function kg(value: number, unit: BodyProfile['unitPreference']): string {
  return unit === 'imperial' ? `${(value * 2.20462).toFixed(1)} lb` : `${value.toFixed(1)} kg`
}

function ProgressBar({ pct, warn }: { pct: number; warn: boolean }) {
  return (
    <div className="h-2 w-full overflow-hidden rounded-full bg-surface-elevated">
      <div
        className={cn('h-full rounded-full transition-all', warn ? 'bg-warning' : 'bg-accent')}
        style={{ width: `${Math.min(100, Math.max(0, pct))}%` }}
      />
    </div>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-[11px] font-medium tracking-wide text-text-secondary uppercase">{label}</span>
      <span className="text-lg font-semibold text-text-primary">{value}</span>
      {sub && <span className="text-xs text-text-secondary">{sub}</span>}
    </div>
  )
}

/**
 * Body profile / measurements sync down from Supabase already (`bodyProfile`,
 * `measurements` in sync/store.ts) but had no UI anywhere on web — the AI's
 * `get_body_profile` tool could read them, but a human looking at /fitness
 * had no way to see their own weight trend, BMI, or daily kcal target. This
 * surfaces that existing data instead of adding new sync surface.
 */
export function FitnessOverview({
  bodyProfile,
  measurements,
  todayWorkouts,
  todayMeals,
}: {
  bodyProfile: BodyProfile | undefined
  measurements: Measurement[]
  todayWorkouts: WorkoutItem[]
  todayMeals: MealItem[]
}) {
  const sorted = [...measurements].sort((a, b) => b.date.getTime() - a.date.getTime())
  const latest = sorted[0]
  const previous = sorted[1]
  const currentWeight = latest?.weightKg ?? bodyProfile?.weightKg
  const unit = bodyProfile?.unitPreference ?? 'metric'

  const weightDelta =
    latest?.weightKg !== undefined && previous?.weightKg !== undefined ? latest.weightKg - previous.weightKg : undefined

  const bmiValue = bodyProfile?.heightCm && currentWeight ? bmi(currentWeight, bodyProfile.heightCm) : undefined
  const tdeeValue = bodyProfile ? tdee(bodyProfile) : undefined

  const kcalIn = todayMeals.reduce((sum, m) => sum + (m.actualKcal ?? 0), 0)
  const kcalTargetToday = todayMeals.reduce((sum, m) => sum + m.targetKcal, 0)
  const kcalBurned = todayWorkouts.reduce((sum, w) => sum + (w.actualKcal ?? w.estimatedKcal), 0)
  const hasTodayData = todayWorkouts.length > 0 || todayMeals.length > 0
  const kcalGoal = Math.round(tdeeValue ?? kcalTargetToday)
  const kcalPct = kcalGoal > 0 ? (kcalIn / kcalGoal) * 100 : 0

  const hasBodyData = currentWeight !== undefined || bmiValue !== undefined || tdeeValue !== undefined

  return (
    <div className="mb-6 grid grid-cols-1 gap-3 md:grid-cols-2">
      <section className="rounded-leo-md border border-divider bg-surface p-4">
        <h2 className="mb-3 text-xs font-medium tracking-wide text-text-secondary uppercase">Body</h2>
        {!hasBodyData ? (
          <p className="text-sm text-text-secondary">
            Set up your body profile via Ask LEO to see BMI, daily calorie targets, and weight trends here.
          </p>
        ) : (
          <div className="grid grid-cols-2 gap-4">
            {currentWeight !== undefined && (
              <Stat
                label="Weight"
                value={kg(currentWeight, unit)}
                sub={
                  weightDelta !== undefined
                    ? `${weightDelta > 0 ? '+' : weightDelta < 0 ? '-' : ''}${kg(Math.abs(weightDelta), unit)} vs last`
                    : bodyProfile?.goalWeightKg !== undefined
                      ? `Goal ${kg(bodyProfile.goalWeightKg, unit)}`
                      : undefined
                }
              />
            )}
            {bmiValue !== undefined && <Stat label="BMI" value={bmiValue.toFixed(1)} />}
            {tdeeValue !== undefined && <Stat label="Daily target" value={`${Math.round(tdeeValue)} kcal`} sub="Maintenance (TDEE)" />}
            {weightDelta !== undefined && currentWeight !== undefined && bodyProfile?.goalWeightKg === undefined && (
              <div className="flex items-center gap-1.5 text-xs text-text-secondary">
                {weightDelta > 0 ? (
                  <TrendingUp className="h-3.5 w-3.5 text-warning" />
                ) : weightDelta < 0 ? (
                  <TrendingDown className="h-3.5 w-3.5 text-success" />
                ) : (
                  <Minus className="h-3.5 w-3.5" />
                )}
                since last measurement
              </div>
            )}
          </div>
        )}
      </section>

      <section className="rounded-leo-md border border-divider bg-surface p-4">
        <h2 className="mb-3 text-xs font-medium tracking-wide text-text-secondary uppercase">Today</h2>
        {!hasTodayData ? (
          <p className="text-sm text-text-secondary">Nothing logged for today yet.</p>
        ) : (
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between text-sm">
              <span className="flex items-center gap-1.5 font-medium text-text-primary">
                <Target className="h-3.5 w-3.5 text-accent" /> {kcalIn} / {kcalGoal || '—'} kcal
              </span>
              {kcalBurned > 0 && (
                <span className="flex items-center gap-1.5 text-text-secondary">
                  <Flame className="h-3.5 w-3.5 text-warning" /> {kcalBurned} burned
                </span>
              )}
            </div>
            {kcalGoal > 0 && <ProgressBar pct={kcalPct} warn={kcalPct > 100} />}
            <span className="text-xs text-text-secondary">
              {todayMeals.length} meal{todayMeals.length === 1 ? '' : 's'} · {todayWorkouts.length} workout
              {todayWorkouts.length === 1 ? '' : 's'} today
            </span>
          </div>
        )}
      </section>
    </div>
  )
}
