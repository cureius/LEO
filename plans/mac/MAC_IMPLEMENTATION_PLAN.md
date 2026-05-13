# LEO macOS — Implementation Plan (master)

**Companion to:** [`MAC_AGENTS.md`](MAC_AGENTS.md), [`PRD.md`](../../PRD.md), [`IMPLEMENTATION_PLAN.md`](../../IMPLEMENTATION_PLAN.md)
**Last updated:** 2026-05-13
**Status:** Not started

This file is the **source of truth for macOS port state** and the home of global rules for the port. Per-milestone task detail lives in `plans/mac/MM*.md`.

---

## Project thesis (for context)

LEO already exists as a finished iOS app (148 Swift files, all 9 milestones coded, in TestFlight prep). The port to macOS is **not a rewrite**. It's:
1. A new SwiftUI scene + Mac-native shell (~20–30 new view files).
2. Platform-conditional services where iOS APIs don't exist on Mac.
3. CloudKit enabled on the existing schema so the two devices sync.

We reuse ~70% of the existing source unchanged: every `Domain/`, `Persistence/`, `AI/Cloud/`, `Monetization/`, `DesignSystem/` file compiles on macOS once the conditional shims are in place.

---

## How a task is structured

Every Mac task follows the same template as iOS:

```
### MM{N}-T{NN} — {Short, imperative title}
- **Status:** TODO | IN-PROGRESS | DONE | BLOCKED
- **Depends on:** {comma-separated task IDs, or —}
- **Estimated effort:** S (≤2h) | M (½–1 day) | L (1–3 days) | XL (>3 days)

**Goal**
One sentence: what this task accomplishes.

**What to build (acceptance criteria)**
A bullet list of specific, testable outcomes.

**How to build it**
Concrete steps. File paths. Code patterns. Type/method names. Known Apple-API edge cases.

**Verification**
- [ ] Specific things to check (run app, run tests, audit, etc.)

**Notes / decisions**
(Empty until the agent records anything worth preserving.)
```

The agent updates `Status`, ticks **Verification** boxes, and appends notes. The agent never deletes the original task body.

---

## Global rules

### Code & process rules
1. **Native SwiftUI on both platforms.** Use `#if os(iOS)` / `#if os(macOS)` only inside view bodies for tiny divergences; for anything bigger, split into separate files (`FooView.swift` vs `FooView+Mac.swift`).
2. **Swift Concurrency.** Async/await + actors everywhere. Same as iOS rules.
3. **SwiftData + CloudKit private DB** is the persistence layer. `cloudKitDatabase: .automatic` once MM1 ships. Same `Stored*` types. Same `SchemaV3`.
4. **iOS deployment target: 18.0. macOS deployment target: 14.0** (Sonoma). Reasons: SwiftData CloudKit sync stabilized in 14.x; `MenuBarExtra` and `NavigationSplitView` are both 14+; `Settings` scene is 14+; SwiftUI `WindowGroup(for:)` is 14+.
5. **No third-party dependencies without approval.** Same rule as iOS.
6. **English (US). No emoji in code.** Same as iOS.
7. **One task = one commit. Prefix commit message with the task ID.** `MM3-T02: port InboxView to Mac three-pane layout`.
8. **Both schemes build green on every commit.** `xcodebuild -scheme LEO build` AND `xcodebuild -scheme LEO-Mac build` must succeed.

### Architecture rules (re-stated)
1. The app is **single-player** in v1. Same.
2. **AI proposes, never silently mutates.** Same.
3. **EventKit is a bridge.** Items live in SwiftData; EventKit is mirrored in/out. Same on Mac (EventKit is fully available).
4. **Local-first.** Every feature works offline. AI degrades gracefully when offline.
5. **The `Item` abstraction is load-bearing.** Same.

### Mac-specific rules
1. **No `UIKit` import in shared code.** Already true in the iOS code. Verify in MM0-T05.
2. **Platform-conditional services use protocols.** `NotificationProviding`, `AlarmEngineProtocol`, `LocationReminderProviding`, `MenuBarStatusProviding` live in `Core` and have iOS + Mac impls.
3. **The Mac app feels Mac-native.** `NavigationSplitView` (not `TabView`), `Settings` scene (not in-window settings), `MenuBarExtra` for always-available capture, keyboard shortcuts on every primary action, `commands { }` for menu bar.
4. **Visual parity, not pixel parity.** Same Theme tokens, same component library (`ItemRow`, `LEOCard`, `LEOChip`, etc.). The shell changes; the cells do not.
5. **Window state restoration.** Sidebar selection, inspector visibility, last viewed date should persist across launches via `SceneStorage` / `AppStorage`.

### Anti-divergence rules
See [`MAC_AGENTS.md`](MAC_AGENTS.md). Re-read every session.

---

## Status tracker (the live state)

**Current milestone:** MM1 — Data Sync
**Currently-in-progress task:** none
**Last completed task:** `MM0-T08`
**Next eligible task:** `MM1-T01`

### Milestone progress

| Milestone | File | Status | Tasks done / total | Notes |
|---|---|---|---|---|
| MM0 — Foundation | [`MM0-foundation.md`](MM0-foundation.md) | Done | 8 / 8 | macOS target, entitlements, protocol extraction, empty Mac app |
| MM1 — Data Sync | [`MM1-data-sync.md`](MM1-data-sync.md) | TODO | 0 / 5 | Enable CloudKit, verify iPhone↔Mac, migrate existing users |
| MM2 — Mac Shell | [`MM2-shell.md`](MM2-shell.md) | TODO | 0 / 7 | NavigationSplitView, sidebar, menu bar, Settings scene |
| MM3 — Today, Inbox, Detail | [`MM3-today-inbox.md`](MM3-today-inbox.md) | TODO | 0 / 7 | TodayView, InboxView, HabitsView, item-detail inspector, history, drag-reschedule, multi-select |
| MM4 — Capture & Power Tools | [`MM4-capture.md`](MM4-capture.md) | TODO | 0 / 6 | Toolbar quick-add, MenuBarExtra, global hotkey, floating capture, command palette, keyboard shortcuts |
| MM5 — AI Assistant & Recurrence | [`MM5-ai-recurrence.md`](MM5-ai-recurrence.md) | TODO | 0 / 5 | AssistantChat Mac, DiffReview pane, RecurrenceBuilder, voice capture |
| MM6 — Platform Services | [`MM6-platform-services.md`](MM6-platform-services.md) | TODO | 0 / 7 | Notifications, alarms, location reminders, EventKit, menu-bar status, travel-time |
| MM7 — Fitness, Habits, Review | [`MM7-fitness-habits-review.md`](MM7-fitness-habits-review.md) | TODO | 0 / 6 | FitnessHome, plan generator, meal/workout detail, measurements, weekly review |
| MM8 — Onboarding, Paywall, Settings | [`MM8-onboarding-paywall-settings.md`](MM8-onboarding-paywall-settings.md) | TODO | 0 / 6 | Onboarding window, PaywallView, StoreKit on Mac, Settings scene, Calendar/Fitness/Feedback panes |
| MM9 — Widgets, Extensions, Ship | [`MM9-widgets-ship.md`](MM9-widgets-ship.md) | TODO | 0 / 6 | Mac widgets, App Intents, Shortcuts, MetricKit, debug tools, TestFlight Mac |

**Total tasks:** 63

### How to update this tracker

When you change a task's status:
1. Update the **Status** line inside the task in its milestone file.
2. Update the milestone summary checklist at the top of that milestone file.
3. Update the row in the table above (recompute "tasks done / total").
4. When a task starts, set **Currently-in-progress task** above the table. When it finishes, set **Last completed task** and clear the in-progress field.
5. When all tasks in a milestone are DONE, mark its row `Done` and bump **Current milestone**.

Single-source-of-truth principle: if these three places (task body, milestone summary, master table) disagree, the agent stops and reconciles before doing anything else.

---

## Feature parity checklist (from the iPhone app)

Every feature below must work on Mac at MM9 exit. Each row maps to the milestone that ships it.

| Feature | iOS file/location | macOS milestone |
|---|---|---|
| Today list view | `Features/Today/Views/TodayView.swift` | MM3 |
| Today timeline (24h grid) | `Features/Today/Views/TodayView.swift` (DayTimelineView) | MM3 |
| History view | `Features/Today/Views/HistoryView.swift` | MM3 |
| Inbox view | `Features/Inbox/Views/InboxView.swift` | MM3 |
| Item detail (edit/complete/delete/reschedule) | `Features/ItemDetail/Views/ItemDetailSheet.swift` | MM3 (as inspector, not sheet) |
| Quick-add bar (text + parser) | `Features/Capture/Views/QuickAddBar.swift` | MM4 (toolbar + MenuBarExtra + global hotkey) |
| Voice capture | iOS Speech | MM5 |
| Recurrence builder (UI) | `Features/Recurrence/Views/RecurrenceBuilderView.swift` | MM5 |
| RRULE engine | `Domain/Recurrence/` | Reused as-is |
| Notifications (UN scheduling) | `Notifications/NotificationManager.swift` | MM6 |
| Alarms (escalating audio) | `Alarms/AlarmEngine.swift` | MM6 (NSSound impl) |
| Location reminders | `Notifications/LocationReminderManager.swift` | MM6 |
| Travel-time pre-reminders | `Notifications/TravelTimePreReminder.swift` | MM6 |
| EventKit bridge (calendar + reminders) | `Persistence/EventKit/EventKitBridge.swift` | MM6 |
| Calendar sync coordinator | `Persistence/EventKit/CalendarSyncCoordinator.swift` | MM6 |
| Habits view + streaks | `Features/Habits/Views/HabitsView.swift` | MM3 |
| Habit materializer + streak engine | `Domain/Habits/` | Reused as-is |
| Weekly review | `Features/Review/Views/WeeklyReviewView.swift` | MM7 |
| AI Assistant chat | `Features/AssistantChat/` | MM5 |
| Claude SSE client | `AI/Cloud/ClaudeClient.swift` | Reused as-is |
| Tool runtime (read + propose tools) | `AI/Cloud/Tools/` | Reused as-is |
| Diff review (accept/reject AI proposals) | `Features/AssistantChat/Views/DiffReviewSheet.swift` | MM5 (as side pane) |
| Fitness home (Gym Companion) | `Features/Fitness/Views/FitnessHomeView.swift` | MM7 |
| Generate plan flow | `Features/Fitness/Views/GeneratePlanFlowView.swift` | MM7 |
| Workout detail | `Features/Fitness/Views/WorkoutDetailSheet.swift` | MM7 |
| Meal detail | `Features/Fitness/Views/MealDetailSheet.swift` | MM7 |
| Measurements chart | `Features/Fitness/Views/MeasurementsChartView.swift` | MM7 |
| HealthKit two-way sync | iOS HKHealthStore | MM7 (limited on Mac — see milestone) |
| Onboarding flow | `Features/Onboarding/Views/OnboardingFlow.swift` | MM8 |
| Gym onboarding page | `Features/Onboarding/Views/OnboardingPageGym.swift` | MM8 |
| Paywall (StoreKit 2) | `Features/Paywall/Views/PaywallView.swift` | MM8 |
| ProGate | `Monetization/ProGate.swift` | Reused as-is |
| Settings root + Calendar/Fitness/Feedback panes | `Features/Settings/Views/` | MM8 (in `Settings` scene) |
| App Intents (Shortcuts) | `Integrations/AppIntents/` | MM9 |
| Focus filter | `Integrations/Focus/LEOFocusFilter.swift` | **Skip** — iOS-only API |
| Live Activities | `Integrations/LiveActivities/` | **Replace** with MenuBarExtra (MM6) |
| Widgets | `LEOWidgets/` (separate target) | MM9 (add macOS as supported family) |
| Debug menu + DB browser | `Utilities/Dev/` | MM9 |
| MetricKit crash reporting | `Utilities/Telemetry/` | MM9 |

**Features that do not port (documented anti-features):**
- iOS Focus filter — Focus filters are iOS/iPadOS only.
- iOS Live Activities — replaced by MenuBarExtra status item on Mac.
- Background tasks (`BGAppRefreshTask`) — replaced by `NSBackgroundActivityScheduler` and a launch-agent for the menu-bar process on Mac.
- iOS Shake-to-debug — replaced by `⌘⇧⌥D` keyboard shortcut on Mac.
- Lock-screen widgets — N/A on Mac.

---

## Build commands

After MM0 ships, both schemes exist:

```bash
# iOS (unchanged from existing)
xcodebuild -scheme LEO -destination 'platform=iOS Simulator,id=FB3865AE-D134-4831-8A18-5CC7394D16C5' build

# macOS (new)
xcodebuild -scheme LEO-Mac -destination 'platform=macOS,arch=arm64' build

# Both must pass before any merge
```

After adding new Swift files, regenerate the project:

```bash
xcodegen generate
```

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Enabling CloudKit on existing schema causes data loss for early TestFlight users | Medium | High | MM1-T03 includes a one-shot CloudKit schema-deploy step; user must confirm before deploy. Manual smoke test with a clean install before any production push. |
| AlarmKit replacement on Mac feels weaker than iOS | High | Medium | Document the limitation in the Mac onboarding flow ("Mac alarms ring only when LEO is running or in the menu bar"); explore `NSBackgroundActivityScheduler` to keep menu-bar process alive. |
| Global hotkey conflicts with other apps | Medium | Low | Default to `⌃⌥Space`; let user customize in Settings → Keyboard. Detect collision on registration and warn. |
| macOS region monitoring is less reliable than iOS | Medium | Medium | Document in Settings → Location; fall back to time-based reminders for the same item if the user opts in. |
| SwiftData CloudKit on macOS 14 has different bugs than iOS 18 | Medium | High | MM1 includes a 48-hour soak test across both devices before MM2 starts. |
| Two-app TestFlight submission complexity | Low | Medium | MM9-T06 covers it; user must already have App Store Connect setup for iOS, which they do. |

---

## What still needs user action (will accumulate as milestones run)

Track here in same style as iOS plan:
1. _(MM1 will populate)_ — CloudKit production schema deploy via CloudKit Dashboard after MM1-T03.
2. _(MM8 will populate)_ — Mac IAP product setup in App Store Connect (separate from iOS products? — research in MM8-T03).
3. _(MM9 will populate)_ — Mac TestFlight submission via Xcode Organizer.
