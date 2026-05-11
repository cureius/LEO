# LEO — Roadmap

**Companion to:** [`PRD.md`](PRD.md)
**Last updated:** 2026-05-07
**Working assumption:** solo developer, ~25–30 focused hours per week. Adjust dates if that changes.

---

## Reading this roadmap

Each milestone has:
- **Goal** — what success looks like.
- **Ships** — the user-visible features that land.
- **Builds** — invisible foundations laid.
- **Exit criteria** — concrete tests the milestone must pass before moving on.
- **Cut line** — what gets dropped if the milestone runs long.

Dates are *targets*, not promises. The discipline is hitting the **exit criteria** in order, not the calendar.

---

## M0 — Foundation (Weeks 1–2 · target 2026-05-21)

**Goal:** A working Xcode project, design system stub, and the data model running with seed data.

**Ships:** Nothing user-facing.

**Builds:**
- Xcode project (iOS 18+), SwiftUI, Swift Concurrency, SwiftData.
- Design tokens (color, type, spacing) via a single `Theme` namespace.
- Domain types: `Item`, `Task`, `Event`, `Reminder`, `Alarm`, `Habit`, `HabitInstance`, `RecurrenceRule`.
- SwiftData persistence + CloudKit container wired (private DB).
- Seeding for dev: 100 fake Items, 5 habits, 3 recurring rules.
- CI: GitHub Actions running `xcodebuild test` on every push; `swiftformat` + `swiftlint` pre-commit.
- Crash reporting via MetricKit hooked up.

**Exit criteria:**
- App launches, persists Items across relaunch, syncs to a second sim via CloudKit.
- Unit tests for the data layer green.
- TestFlight internal pipeline configured (no build pushed yet).

**Cut line:** CloudKit can slip to M3 if it bites; everything else is required.

---

## M1 — Core capture & Today (Weeks 3–5 · target 2026-06-11)

**Goal:** A usable, opinionated single-screen app — capture and see your day.

**Ships:**
- **Today view**: chronological timeline of all Items for today.
- **Quick-add bar**: text input with deterministic date parsing (chrono-style) for the 80% of phrases. NL parser via Foundation Models for the long tail.
- Item detail sheet with edit / complete / delete.
- Drag-to-reschedule on Today.
- Inbox tab for Items lacking dates.
- Light + dark mode, Dynamic Type, basic VoiceOver.

**Builds:**
- View-model layer with `@Observable`.
- Quick-add parser pipeline (regex → Foundation Models fallback).
- Diff/animation primitives for the timeline.

**Exit criteria:**
- Can capture and see 50 Items without lag (60fps scroll).
- Quick-add: 9/10 phrases from a fixed test corpus parse correctly to the right Item type.
- Today view passes accessibility audit (VoiceOver + Dynamic Type AX5).
- Dogfood: Raj uses LEO as the only capture surface for a full week; logs friction.

**Cut line:** Drag-to-reschedule can move to M2.

---

## M2 — Recurring engine & notifications (Weeks 6–8 · target 2026-07-02)

**Goal:** The recurring/reminder engine that beats Apple Reminders.

**Ships:**
- Recurring rule builder (visual + NL).
- All required RRULE patterns (DAILY/WEEKLY/MONTHLY/YEARLY × BYDAY × INTERVAL × COUNT/UNTIL).
- LEO extensions: workdays-only, "every other Tuesday unless holiday", first-weekday-of-month.
- Per-occurrence skip / move without breaking series.
- Time-based local notifications.
- Location-based reminders (CoreLocation + region monitoring).
- Smart pre-reminders with travel time (MapKit ETA).

**Builds:**
- Recurrence expansion service with caching for Today/Week views.
- Notification request manager with rescheduling on edits.
- Holiday data (US to start; expandable).

**Exit criteria:**
- A 100-test suite of recurring scenarios passes (golden files).
- Notifications fire correctly across reboot + force-quit.
- Battery profiling: idle drain < 0.5%/hr with 200 active recurring Items.

**Cut line:** Holiday-aware skip is the most likely cut; ship as v1.1 if it overruns.

---

## M3 — System integration & sync (Weeks 9–10 · target 2026-07-16)

**Goal:** LEO becomes a citizen of the iOS ecosystem.

**Ships:**
- EventKit two-way sync: import calendars + reminder lists, write back changes.
- iCloud sync (private DB) functional across iPhone + iPad sim.
- Lock-screen + Home-screen widgets (Today, Next-up, Quick-add, Habit ring).
- Live Activity for the next event.
- Focus filter integration.
- App Intents for quick-add, complete, get-today.

**Builds:**
- Conflict-resolution policy for two-way sync (LEO wins on metadata, system wins on event timing if last-write-wins ambiguous).
- Widget timeline provider with reasonable refresh budget.

**Exit criteria:**
- Editing an Item in Apple Calendar reflects in LEO within 30s; vice versa.
- Widgets render without "Unable to load" 99% of the time over 24h.
- Siri can add a task via App Intent.

**Cut line:** Live Activities can ship in M6 with the alarms work.

---

## M4 — AI assistant (Weeks 11–13 · target 2026-08-06)

**Goal:** "Ask LEO" exists and is good enough to be the marketing centerpiece.

**Ships:**
- Chat UI with streaming responses.
- Tool-use harness: AI calls typed tools (`findFreeSlots`, `proposeReschedule`, `summarizeWeek`, etc.) returning Item diffs.
- Diff review sheet — accept / reject / edit each proposed change.
- Model routing (on-device for L0/L1, Claude API for L2/L3).
- Prompt caching of the user's standing context.
- Token budget meter visible in settings.

**Builds:**
- Claude API client (cached system prompt with user profile + standing context).
- Eval harness: 30 hand-curated planning prompts with expected behaviors (no exact-match scoring; rubric-based).

**Exit criteria:**
- Five canonical prompts work end-to-end (see PRD §7.6).
- Eval harness ≥ 80% pass on the rubric.
- Median L2 response time < 4s on a typical prompt.
- Privacy: outbound payload inspector shows only the relevant slice of user data is sent.

**Cut line:** L3 ("reason") tier moves to v1.x. Ship with L0/L1/L2.

---

## M5 — Habits & weekly review (Weeks 14–15 · target 2026-08-20)

**Goal:** The accountability loop closes.

**Ships:**
- Habit definition (frequency, time hint, duration target).
- Habit instances rendered inline on Today.
- Forgiving streaks (one allowed miss per period).
- Sunday weekly review: AI-generated summary + slip analysis + next-week prompt.
- Habits tab with rings, history, longest streak.

**Builds:**
- Habit instance materializer (driven by recurrence engine).
- Weekly review prompt with cached week-context.

**Exit criteria:**
- A user can create a habit, complete it daily for 14 days, miss once, and see the streak preserved per the forgiving rule.
- Weekly review feels useful in dogfood (subjective; Raj's call after 2 cycles).

**Cut line:** History/longest-streak views can ship in v1.1.

---

## M6 — Alarms, Watch glance, polish (Weeks 16–17 · target 2026-09-03)

**Goal:** Real alarms and presence on the Watch wrist.

**Ships:**
- Real-alarm mode (AVAudioSession `.playback`, escalating volume, Live Activity with snooze/dismiss).
- Apple Watch app (read-only Today + complications + quick-add via dictation).
- Onboarding flow (4 screens + permissions).
- Settings: notification scheduling, energy blocks, AI privacy controls, theme.
- Empty states, error states, retry UX across the app.

**Builds:**
- WatchConnectivity stub (full sync deferred).

**Exit criteria:**
- Real alarm wakes the device from silent mode 95%+ of the time in test (best-effort acknowledged in §11 of PRD).
- Onboarding completes in < 90s p50.
- App Store screenshots & app preview video drafts done.

**Cut line:** Watch app ships at v1.1 if alarm work overruns. (Onboarding cannot be cut.)

---

## M7 — Beta & monetization (Weeks 18–19 · target 2026-09-17)

**Goal:** TestFlight beta with paying users.

**Ships:**
- StoreKit 2 paywall (Pro $9.99/mo, $79.99/yr, 7-day trial, family sharing).
- Free vs Pro gating per PRD §7.8.
- TestFlight public link (limited to 500 testers).
- In-app feedback channel (mailto + radar template).
- Crash + non-fatal reporting via MetricKit dashboards.

**Exit criteria:**
- 100+ beta users, ≥ 30 actively using daily after week 2.
- ≥ 5 paying trialists convert.
- Top 10 reported bugs triaged; P0/P1s fixed.
- App Privacy nutrition label drafted, App Store metadata complete.

**Cut line:** Family sharing can ship post-launch.

---

## M8 — Gym Companion (Weeks 20–22 · target 2026-10-08)

**Goal:** A personalized fitness layer — body profile, AI-generated workout routines and meal plans, HealthKit two-way sync — included in v1.0.

**Ships:**
- Body profile capture (height, weight, body fat %, goal weight, goal physique, diet type, allergies, medical flags).
- AI-generated workout routines and meal plans, surfaced as a Diff the user accepts.
- Bundled exercise (~150) and recipe (~80) library; AI selects from these to prevent hallucinated exercises.
- `WorkoutItem` and `MealItem` flow through the Today timeline like every other Item.
- HealthKit two-way sync: read body metrics + active energy; write completed workouts (`HKWorkout`) and logged meals (dietary energy + macros).
- Tap-to-complete workouts/meals with optional "Log actuals" detail sheet.
- Measurements chart (weight + body-fat trend).
- Onboarding step for body profile (skippable).

**Builds:**
- `Domain/Fitness/`: `UserBodyProfile`, `BodyMath` (BMI/BMR/TDEE), `Exercise`, `Recipe`.
- `Persistence/HealthKit/HealthKitBridge.swift` actor.
- New AI tools: `GetBodyProfile`, `ProposeWorkoutPlan`, `ProposeMealPlan`, `AdjustPlan`.

**Exit criteria:**
- Five canonical fitness prompts work end-to-end.
- HealthKit two-way sync verified on a real device with Apple Watch.
- Medical disclaimer present in onboarding and settings.
- All M8 tasks done or accepted via the cut line.

**Cut line:** in order — HealthKit write-back → custom workout/meal notification actions → "Log actuals" + swap-meal + measurements chart. T01/T02/T03/T05/T07 are non-cuttable.

See [`plans/M8-gym-companion.md`](plans/M8-gym-companion.md).

---

## M9 — App Store launch (Weeks 23–24 · target 2026-10-22)

**Goal:** v1.0 in the store.

**Ships:**
- App Store submission, review, release.
- Marketing site (one page, screenshots, video, trial CTA).
- Launch on Product Hunt, Hacker News (Show HN), r/productivity, r/iOSProgramming, dev Twitter.
- Press list: MacStories, 9to5Mac, The Verge contacts emailed in advance with embargoed preview.

**Exit criteria:**
- Approved on first or second review submission.
- 1,000 installs in first 7 days.
- ≥ 4.5 average rating after 100 ratings.

**Cut line:** None — this is the launch. If it slips, M7 extends.

---

## Post-launch — v1.1 → v2.0 (Q4 2026 onward)

**v1.1 (≈ 4–6 weeks post-launch):**
- Whatever the most-requested cut item is.
- Anything cut from M8 via the Gym Companion cut line (likely HealthKit write-back, custom workout/meal notification actions, "Log actuals" / swap-meal / measurements chart).
- Apple Watch full sync (if not in v1).
- iPad-optimized layout.
- Voice-first "Talk to LEO" mode.
- Holiday-aware recurring (international).

**v1.2:**
- Projects (grouping with deadlines).
- Energy-aware AI scheduling using user-defined energy blocks.
- More languages (start with ES, FR, DE, JA).

**v2.0 candidates (Q1–Q2 2027):**
- macOS Catalyst / native Mac app.
- Shared lists & light collaboration (requires backend — re-evaluate CloudKit-only stance).
- Plug-ins for email triage (Apple Intelligence + Mail integration).
- Time-tracking / focus-session features.
- Coach mode: proactive AI that nudges, not just reacts.

---

## Operating principles for the build

1. **Dogfood from M1.** Raj uses LEO as primary capture surface starting Week 5. Switch to LEO-only as primary by M5.
2. **One opinionated UI in v1.** No theme switcher, no layout choices. Every preference is a maintenance cost.
3. **No feature without a kill switch.** Every M4+ feature ships behind a remote-disable flag (CloudKit config record) so a bad release can be partially rolled back.
4. **Write the tests before the recurring engine becomes load-bearing.** M2 is where bugs become permanent.
5. **The AI's failure mode must be "I don't know," not a wrong plan.** Bake that into the system prompt and eval rubric.
6. **Ship the cut line.** Any milestone running > 25% over its budget triggers an explicit cut conversation, not a silent slip.

---

## Estimated timeline summary

| Milestone | Target ship | Calendar weeks |
|---|---|---|
| M0 — Foundation | 2026-05-21 | 2 |
| M1 — Core capture & Today | 2026-06-11 | 3 |
| M2 — Recurring & notifications | 2026-07-02 | 3 |
| M3 — System integration & sync | 2026-07-16 | 2 |
| M4 — AI assistant | 2026-08-06 | 3 |
| M5 — Habits & weekly review | 2026-08-20 | 2 |
| M6 — Alarms, Watch, polish | 2026-09-03 | 2 |
| M7 — Beta & monetization | 2026-09-17 | 2 |
| M8 — Gym Companion | 2026-10-08 | 3 |
| M9 — App Store launch | 2026-10-22 | 2 |
| **v1.0 in the store** | **2026-10-22** | **24 weeks (~5.5 months)** |

That's the optimistic path. Build a realistic 1.4× buffer in your head — **most likely launch window: mid-November to early December 2026.**

---

*Roadmap is a living document. Update after each milestone retrospective.*
