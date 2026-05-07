# LEO — Implementation Plan (master)

**Companion to:** [`AGENTS.md`](AGENTS.md), [`PRD.md`](PRD.md), [`ROADMAP.md`](ROADMAP.md)
**Last updated:** 2026-05-07

This file is the **source of truth for project state** and the home of global rules. Per-milestone task detail lives in `plans/M*.md`.

---

## How a task is structured

Every task in every milestone file follows this template:

```
### M{N}-T{NN} — {Short, imperative title}
- **Status:** TODO | IN-PROGRESS | DONE | BLOCKED
- **Depends on:** {comma-separated task IDs, or —}
- **Estimated effort:** S (≤2h) | M (½–1 day) | L (1–3 days) | XL (>3 days)

**Goal**
One sentence: what this task accomplishes.

**What to build (acceptance criteria)**
A bullet list of specific, testable outcomes. If you can't tick every bullet,
the task is not done.

**How to build it**
Concrete steps. File paths. Code patterns. Names of types/methods to create.
Gotchas and known Apple-API edge cases. This is the playbook.

**Verification**
- [ ] Specific things to check (run app, run tests, audit, etc.)

**Notes / decisions**
(Empty until the agent records anything worth preserving.)
```

The agent updates `Status`, ticks **Verification** boxes, and appends notes. The agent never deletes the original task body.

---

## Global rules

### Code & process rules
1. **Native SwiftUI. Swift Concurrency (async/await + actors). No UIKit unless an API forces it (UIKit-only surfaces in iOS 18+: a few share extension corners and `UIApplicationDelegate` for some legacy hooks).**
2. **SwiftData is the persistence layer.** No Core Data. No realm. No Codable-to-disk hand-rolling.
3. **CloudKit private DB for sync.** No third-party sync layer. No backend in v1.
4. **iOS 18.0 deployment target.** Use new APIs freely. Do not write iOS 17 fallbacks.
5. **No third-party dependencies without explicit user approval.** When a need arises, propose it in chat with: name, what it replaces, license, weight, alternatives. Add it to `plans/conventions.md` only after approval.
6. **No emoji in code or docs unless the user asked.** Strings in UI may contain emoji where a designer specified.
7. **English (US) for code and docs. Localized strings live in `Localizable.xcstrings` from M1 onward.**
8. **Keep PRs / commits scoped to one task ID.** Multi-task commits are forbidden — they break the rollback story.

### Architecture rules (re-stated from PRD)
1. The app is **single-player** in v1. No code paths that assume multi-user.
2. **AI proposes, never silently mutates.** Every AI-suggested change must surface as a `Diff` the user accepts or rejects.
3. **EventKit is a bridge.** Items live in SwiftData; EventKit is mirrored in/out, not the source of truth.
4. **Local-first.** Every feature works offline. AI degrades gracefully when offline.
5. **The `Item` abstraction is load-bearing.** Tasks, Events, Reminders, Alarms, HabitInstances all share it. Don't fork into parallel hierarchies.

### Anti-divergence rules
See [`AGENTS.md`](AGENTS.md) — re-read every session. They are not rephrased here on purpose; one canonical home.

---

## Status tracker (the live state)

**Current milestone:** M2 — Recurring & Notifications
**Currently-in-progress task:** *(none yet)*
**Last completed task:** `M1-T08`
**Next eligible task:** `M2-T01`

### Milestone progress

| Milestone | File | Status | Tasks done / total | Notes |
|---|---|---|---|---|
| M0 — Foundation | [`plans/M0-foundation.md`](plans/M0-foundation.md) | Done | 8 / 8 | Xcode 15.4 / iOS 17; bump to 18 when Xcode 16 installed |
| M1 — Capture & Today | [`plans/M1-capture-today.md`](plans/M1-capture-today.md) | Done | 8 / 8 | Today view, QuickAdd, parser, ItemRow, Inbox, drag-reschedule |
| M2 — Recurring & Notifications | [`plans/M2-recurring-notifications.md`](plans/M2-recurring-notifications.md) | Not started | 0 / 7 | |
| M3 — Integration & Sync | [`plans/M3-integration-sync.md`](plans/M3-integration-sync.md) | Not started | 0 / 7 | |
| M4 — AI Assistant | [`plans/M4-ai-assistant.md`](plans/M4-ai-assistant.md) | Not started | 0 / 7 | |
| M5 — Habits & Review | [`plans/M5-habits-review.md`](plans/M5-habits-review.md) | Not started | 0 / 6 | |
| M6 — Alarms, Watch, Polish | [`plans/M6-alarms-watch-polish.md`](plans/M6-alarms-watch-polish.md) | Not started | 0 / 7 | |
| M7 — Beta & Monetization | [`plans/M7-beta-monetization.md`](plans/M7-beta-monetization.md) | Not started | 0 / 6 | |
| M8 — Launch | [`plans/M8-launch.md`](plans/M8-launch.md) | Not started | 0 / 5 | |

### How to update this tracker

When you change a task's status:
1. Update the **Status** line inside the task in its milestone file.
2. Update the milestone summary checklist at the top of that milestone file.
3. Update the row in the table above (recompute "tasks done / total").
4. When a task starts, set **Currently-in-progress task** above the table. When it finishes, set **Last completed task** and clear the in-progress field (or set it to the next one being started).
5. When all tasks in a milestone are DONE, mark its row "Done", and bump **Current milestone** to the next.

Single-source-of-truth principle: if these three places (task body, milestone summary, master table) disagree, the agent stops and reconciles before doing anything else.

---

## Decision log

When the user (or the agent, with user approval) makes a decision that overrides or extends the PRD/conventions, log it here as a one-liner. This is *not* for routine implementation choices — only ones future agents need to know to avoid re-litigating.

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-07 | iOS 18.0 deployment target | Foundation Models API + SwiftData maturity |
| 2026-05-07 | SwiftData over Core Data | Modern, less boilerplate; accept v1 migration risk |
| 2026-05-07 | Native SwiftUI, no cross-platform | Widgets/Live Activities/AppIntents/Watch require it |
| 2026-05-07 | EventKit as bridge, not source of truth | Need to attach LEO-specific metadata to Items |
| 2026-05-07 | AI proposes diffs; never auto-mutates v1 | Trust + safety |
| 2026-05-07 | Deployment target iOS 17.0 (not 18.0) for now | Xcode 15.4 installed; bump target + strict concurrency when Xcode 16 is installed |
| 2026-05-07 | xcodegen 2.45.4 used to generate project.yml; pbxproj objectVersion patched to 60 | No xcode-16 available; project opens in Xcode 15.4 |
| 2026-05-07 | `@Previewable` macro removed from previews | Not available in Swift 5.10 / Xcode 15; use wrapper structs instead |
| 2026-05-08 | `ModelConfiguration` uses `.cloudKitDatabase(.none)` until M3 | SwiftData validates CloudKit rules (all attrs optional, all rels have inverses) at container init even for in-memory stores when app is signed with CloudKit entitlements. M3 must make all @Model attrs optional and add inverse to StoredHabit.recurrenceRule before switching to `.private("iCloud.com.leo.app")` |

---

## Open questions log

Questions that need a user decision before relevant tasks can complete. The agent surfaces these in chat; the user answers; the answer is logged in the **Decision log** above and the question is removed.

- [ ] Watch app at v1 launch or v1.1? (Affects M6 scope.)
- [ ] Google Calendar direct integration in v1, or rely on iOS account? (Affects M3.)
- [ ] AI assistant as separate tab, or sheet over Today? (Affects M4 UI shape.)
- [ ] Default AI posture: quiet or proactive? (Affects M4 + M5.)
- [ ] Voice-first "Talk to LEO" in v1 or v1.x? (Affects M4 + M6 scope.)

---

## Glossary (implementation-specific)

Domain glossary lives in [`PRD.md` §14](PRD.md). This section is for *code-level* names that recur across tasks.

- **`Item`** — protocol or abstract base; the unifying type. Concrete types: `TaskItem`, `EventItem`, `ReminderItem`, `AlarmItem`, `HabitInstanceItem`. (Suffix `Item` avoids collision with Swift's `Task`.)
- **`RecurrenceRule`** — RFC 5545 RRULE wrapper plus LEO extensions.
- **`Diff`** — a structured list of `ItemChange` records the AI proposes.
- **`Capture`** — the act of creating an Item via quick-add. The pipeline is parser → draft Item → confirm/save.
- **`Plan`** — output of an AI L2 request. Always a `Diff`, never raw text.
- **`Anchor`** — the time point/window an Item is bound to.
- **`Series`** — the abstract recurring item; `HabitInstance`/expanded recurrence Items are concrete occurrences.

---

## Reference materials (curated, for the agent)

When implementing, prefer these primary sources over Stack Overflow:

- Apple Developer Docs (official). Especially: SwiftData, EventKit, UserNotifications, App Intents, WidgetKit, ActivityKit (Live Activities), FoundationModels (Apple Intelligence), StoreKit 2, MapKit (ETA), CoreLocation (region monitoring), AVAudioSession.
- WWDC 2024–2026 sessions on the above (search by API name).
- RFC 5545 (iCalendar) for recurrence — not a blog explainer, the actual RFC.
- Anthropic API docs at `docs.claude.com` for the Claude API integration in M4.

If a task references an API the agent isn't sure exists in iOS 18+, it stops and asks rather than inventing a method name.
