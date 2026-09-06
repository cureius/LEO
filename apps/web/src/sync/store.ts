import { create } from 'zustand'
import type { BodyProfile, DomainItem, Habit, Measurement } from '@/domain/types'
import type { AutomationRule } from '@/domain/automationRules'

export type ConnectionStatus = 'connecting' | 'connected' | 'disconnected'

/** item_id -> its google_calendar_links row. Cached here (not queried fresh
 *  from Supabase per call) so mutations.ts's updateItem/deleteItem can check
 *  "is this item Google-linked?" synchronously on EVERY item save/delete —
 *  not just Google-originated ones — without a network round trip on the
 *  common case of an unrelated item. */
export type GoogleLink = { connectionId: string; googleEventId: string; googleUpdatedAt?: string; googleRecurringEventId?: string }

type SyncStore = {
  items: Map<string, DomainItem>
  habits: Map<string, Habit>
  measurements: Map<string, Measurement>
  bodyProfile: BodyProfile | undefined
  googleLinks: Map<string, GoogleLink>
  rules: Map<string, AutomationRule>
  connectionStatus: ConnectionStatus
  /** True once the initial fetch for the signed-in user has completed. */
  initialLoadComplete: boolean

  upsertItem: (item: DomainItem) => void
  removeItem: (id: string) => void
  getItem: (id: string) => DomainItem | undefined

  upsertHabit: (habit: Habit) => void
  removeHabit: (id: string) => void

  upsertMeasurement: (measurement: Measurement) => void
  removeMeasurement: (id: string) => void

  setBodyProfile: (profile: BodyProfile) => void

  upsertGoogleLink: (itemId: string, link: GoogleLink) => void
  removeGoogleLink: (itemId: string) => void

  upsertRule: (rule: AutomationRule) => void
  removeRule: (id: string) => void

  setConnectionStatus: (status: ConnectionStatus) => void
  setInitialLoadComplete: () => void

  /** Full reset on sign-out — this store must never leak one account's data into the next session. */
  reset: () => void
}

const initialState = {
  items: new Map<string, DomainItem>(),
  habits: new Map<string, Habit>(),
  measurements: new Map<string, Measurement>(),
  bodyProfile: undefined as BodyProfile | undefined,
  googleLinks: new Map<string, GoogleLink>(),
  rules: new Map<string, AutomationRule>(),
  connectionStatus: 'connecting' as ConnectionStatus,
  initialLoadComplete: false,
}

export const useSyncStore = create<SyncStore>((set, get) => ({
  ...initialState,

  upsertItem: (item) =>
    set((state) => {
      const items = new Map(state.items)
      items.set(item.id, item)
      return { items }
    }),

  removeItem: (id) =>
    set((state) => {
      const items = new Map(state.items)
      items.delete(id)
      return { items }
    }),

  getItem: (id) => get().items.get(id),

  upsertHabit: (habit) =>
    set((state) => {
      const habits = new Map(state.habits)
      habits.set(habit.id, habit)
      return { habits }
    }),

  removeHabit: (id) =>
    set((state) => {
      const habits = new Map(state.habits)
      habits.delete(id)
      return { habits }
    }),

  upsertMeasurement: (measurement) =>
    set((state) => {
      const measurements = new Map(state.measurements)
      measurements.set(measurement.id, measurement)
      return { measurements }
    }),

  removeMeasurement: (id) =>
    set((state) => {
      const measurements = new Map(state.measurements)
      measurements.delete(id)
      return { measurements }
    }),

  setBodyProfile: (profile) => set({ bodyProfile: profile }),

  upsertGoogleLink: (itemId, link) =>
    set((state) => {
      const googleLinks = new Map(state.googleLinks)
      googleLinks.set(itemId, link)
      return { googleLinks }
    }),

  removeGoogleLink: (itemId) =>
    set((state) => {
      const googleLinks = new Map(state.googleLinks)
      googleLinks.delete(itemId)
      return { googleLinks }
    }),

  upsertRule: (rule) =>
    set((state) => {
      const rules = new Map(state.rules)
      rules.set(rule.id, rule)
      return { rules }
    }),

  removeRule: (id) =>
    set((state) => {
      const rules = new Map(state.rules)
      rules.delete(id)
      return { rules }
    }),

  setConnectionStatus: (status) => set({ connectionStatus: status }),
  setInitialLoadComplete: () => set({ initialLoadComplete: true }),

  reset: () =>
    set({ ...initialState, items: new Map(), habits: new Map(), measurements: new Map(), googleLinks: new Map(), rules: new Map() }),
}))

/**
 * Array selector helpers. IMPORTANT: these allocate a new array every call,
 * so a component MUST wrap them in `useShallow` from `zustand/react/shallow`
 * — e.g. `useSyncStore(useShallow(selectItemsArray))` — never call them bare.
 * Zustand v5 sits on `useSyncExternalStore`, which re-renders whenever a
 * selector's *reference* changes; a bare selector here creates a new
 * reference on literally every read regardless of whether the data changed,
 * which React interprets as "constantly changing" and enters an infinite
 * render loop ("Maximum update depth exceeded"). Hit this for real in
 * TodayPage during Phase 1 — `useShallow` fixed it by comparing array
 * contents instead of the array's own identity.
 */
export function selectItemsArray(state: SyncStore): DomainItem[] {
  return Array.from(state.items.values())
}
export function selectHabitsArray(state: SyncStore): Habit[] {
  return Array.from(state.habits.values())
}
export function selectMeasurementsArray(state: SyncStore): Measurement[] {
  return Array.from(state.measurements.values())
}
export function selectRulesArray(state: SyncStore): AutomationRule[] {
  return Array.from(state.rules.values())
}
