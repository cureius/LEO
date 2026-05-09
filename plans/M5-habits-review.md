# M5 — Habits & Weekly Review

**Goal of this milestone:** The accountability loop. Habits with forgiving streaks, the weekly retrospective, and the habits tab.

**Target ship:** 2026-08-20 (2 weeks).

**Read before starting:** [`PRD.md`](../PRD.md) §7.5.

**Prerequisites:** M4 complete. Recurrence engine and AI assistant available.

---

## Task summary

- [x] M5-T01 — Habit definition + materializer
- [x] M5-T02 — Habit row inline on Today
- [x] M5-T03 — Forgiving streaks
- [x] M5-T04 — Habits tab (rings, history)
- [x] M5-T05 — Weekly review generator
- [x] M5-T06 — Weekly review UI

---

### M5-T01 — Habit definition + materializer
- **Status:** TODO
- **Depends on:** M4 complete
- **Estimated effort:** M

**Goal**
Create habits and materialize their `HabitInstanceItem`s into the timeline so they appear like any other Item.

**What to build (acceptance criteria)**
- Habit creation flow: from a "+" in Habits tab, pick name, frequency (daily / N times per week / specific weekdays / custom RRule), time hint (morning / afternoon / evening / specific time), target duration, forgiveness setting.
- Persistence: `StoredHabit` from M0; `StoredHabitInstance` materialized for a 14-day rolling window.
- A `HabitMaterializer` actor:
  - On habit create or rule edit, generates instances forward 14 days.
  - On midnight, advances the window: drops 1 day past, adds 1 day future.
  - Uses the recurrence engine for generation.
- Instances on Today show via the unified timeline (no separate query path).

**How to build it**
1. Materialization is idempotent: re-running the same window produces the same instances (keyed by canonical occurrence date).
2. Don't materialize too far ahead — 14 days is enough for streak math + UI; further dates are computed on demand.
3. Edit-habit semantics: changing frequency clears future unstarted instances and regenerates; completed/skipped instances stay.

**Verification**
- [ ] Creating "Gym MWF 7am 60m" produces 6 instances over 14 days at correct times.
- [ ] Past completed instances survive editing the rule.
- [ ] Materializer runs silently in background at midnight.

---

### M5-T02 — Habit row inline on Today
- **Status:** TODO
- **Depends on:** M5-T01
- **Estimated effort:** S

**Goal**
Habits look like first-class items on Today.

**What to build (acceptance criteria)**
- `HabitInstanceItem` rows show with a small ring indicator (today's habit completion) and the habit name.
- Tap to complete; long-press for "Skip today / Move to evening / Edit habit".
- Skipping consumes the forgiveness budget (M5-T03).

**How to build it**
1. `ItemRow` already switches on type (M1-T02). Add the case.
2. Don't add a separate "habits" timeline lane — merging is the point.

**Verification**
- [ ] Habit instance shows in the right time slot on Today.
- [ ] Complete and skip actions work.

---

### M5-T03 — Forgiving streaks
- **Status:** TODO
- **Depends on:** M5-T01
- **Estimated effort:** M

**Goal**
Streak math that allows N misses per period without breaking. Users feel encouraged, not punished.

**What to build (acceptance criteria)**
- `Domain/Habits/StreakEngine.swift`:
  - Configurable `forgiveness: HabitForgiveness` per habit:
    - `.none`
    - `.misses(perWeek: Int)` — default 1.
    - `.percent(min: Double)` — e.g., 70% in trailing 14 days.
  - `func currentStreak(for habit: Habit, instances: [HabitInstance]) -> StreakState` returning `(activeStreakDays, longestStreak, forgivenessRemainingThisPeriod, atRisk: Bool)`.
- `atRisk` flag when one more miss would break the streak — surfaced as a warning chip.
- All math pure-functional and unit-tested.

**How to build it**
1. Walk back from today day-by-day; count consecutive completions; allow up to N misses per ISO week (or trailing window) before resetting.
2. Don't guess what users want. Default forgiveness = `.misses(perWeek: 1)` per PRD; expose in habit edit.
3. Tests: synthetic 90-day completion histories with known expected streaks.

**Verification**
- [ ] 14 days of completion + 1 skip → streak preserved (15 days).
- [ ] 14 days + 2 skips in same week → streak breaks; longest still 14.
- [ ] `atRisk` triggers when one more miss would break.

---

### M5-T04 — Habits tab (rings, history)
- **Status:** TODO
- **Depends on:** M5-T03
- **Estimated effort:** M

**Goal**
A dedicated surface for habit tracking — at-a-glance rings + history calendar.

**What to build (acceptance criteria)**
- `Features/Habits/Views/HabitsView.swift`:
  - Top: today's rings (one per habit, completion %) — Apple-style activity rings.
  - Middle: list of habits with current streak, target, time hint.
  - Tap a habit → detail with 90-day calendar heatmap, longest streak, miss reasons, edit / archive.
- Archive (not delete): hides from main list but preserves history.

**How to build it**
1. Rings: a SwiftUI `Canvas` with `strokeBorder` arcs; one per habit. Don't import a charting library.
2. Calendar heatmap: a `LazyVGrid` of 90 cells, color-coded by completion state.
3. Editing flow reuses M5-T01 forms.

**Verification**
- [ ] Rings reflect today's completion accurately.
- [ ] Heatmap colors match instance states.
- [ ] Archived habits removed from Today/Inbox but preserved in detail view via "Show archived" toggle.

---

### M5-T05 — Weekly review generator
- **Status:** TODO
- **Depends on:** M4 complete, M5-T04
- **Estimated effort:** M

**Goal**
Generate a Sunday evening review summarizing the week — completed, slipped, insights, next-week prompts.

**What to build (acceptance criteria)**
- `AI/Review/WeeklyReviewGenerator.swift`:
  - `func generate(for week: DateInterval) async throws -> WeeklyReview`.
  - Bundles: completion stats, habit streaks, deadlines hit/missed, AI-generated narrative ("you completed 3/5 deep work blocks; gym dropped to 2x").
  - Calls Claude (Sonnet) with cached context including the week's items.
  - Returns a `WeeklyReview` value type with sections: highlights, slips, themes, suggestions.
- Triggered Sunday 6pm local time via `BGAppRefreshTask`; surfaces a notification "Your week with LEO is ready".
- Persisted as `StoredWeeklyReview` for history.

**How to build it**
1. The bundling step computes deterministic stats first; the LLM only narrates them. This guards against hallucinated numbers.
2. Cap context to ~80 items (the week's). Items beyond go in a summary line.
3. Cache the system prompt (LM cache + LEO-side cache by week ID).

**Verification**
- [ ] Generating a review for last week produces plausible narrative + correct numbers.
- [ ] Stats match a hand-computed control test.
- [ ] Sunday notification fires in a simulated time test.

---

### M5-T06 — Weekly review UI
- **Status:** TODO
- **Depends on:** M5-T05
- **Estimated effort:** M

**Goal**
A presentation of the review with action prompts the user can act on inline.

**What to build (acceptance criteria)**
- `Features/Review/Views/WeeklyReviewView.swift`:
  - Hero: "Week of [dates]" + headline metric.
  - Sections from generator: highlights / slips / themes / suggestions.
  - Suggestions are actionable: "Add a gym block Friday morning?" → tap → goes to AI assistant pre-loaded with that prompt.
  - Sharing as image (PNG) via `ShareLink` for socials/Slack — anonymized by default.
- History list of past reviews accessible from Habits tab.

**How to build it**
1. Use `ImageRenderer` for share image generation.
2. The "anonymized" share template hides item names; replaces them with categories ("3 deep work blocks").
3. Suggestion → assistant: pre-fill the chat input field with the suggestion text.

**Verification**
- [ ] Last week's review displays correctly.
- [ ] Sharing produces a clean image.
- [ ] Suggestion taps route into the assistant with the right prompt.

---

## Exit criteria for M5

- [ ] All six tasks `DONE`.
- [ ] Streak math passes the test suite including the forgiving-rule case.
- [ ] Weekly review feels useful in dogfood (Raj's call after 2 cycles).
- [ ] User signs off in chat.
