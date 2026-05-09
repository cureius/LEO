# M3 — System Integration & Sync

**Goal of this milestone:** LEO becomes a citizen of iOS — EventKit two-way sync, widgets, Live Activities, Focus filters, App Intents.

**Target ship:** 2026-07-16 (2 weeks).

**Read before starting:** [`PRD.md`](../PRD.md) §7.7, Apple docs for EventKit, WidgetKit, ActivityKit, App Intents, Focus.

**Prerequisites:** M2 complete. CloudKit sync stable.

---

## Task summary

- [x] M3-T01 — EventKit bridge (read)
- [x] M3-T02 — EventKit bridge (write-back) + conflict policy
- [x] M3-T03 — Lock-screen / Home-screen widgets
- [x] M3-T04 — Live Activity for next event
- [x] M3-T05 — App Intents + Siri
- [x] M3-T06 — Focus filter integration
- [ ] M3-T07 — CloudKit deploy & multi-device hardening (BLOCKED: requires user sign-off before production deploy)

---

### M3-T01 — EventKit bridge (read)
- **Status:** TODO
- **Depends on:** M2 complete
- **Estimated effort:** L

**Goal**
Mirror selected iOS calendars and reminder lists into LEO's store as `EventItem`/`ReminderItem`s, marked as externally-sourced.

**What to build (acceptance criteria)**
- `Persistence/EventKit/EventKitBridge.swift`:
  ```swift
  actor EventKitBridge {
    func requestAccess() async -> EKAuthorizationStatus
    func availableSources() async -> [EKSource]
    func availableCalendars() async -> [EKCalendar]
    func subscribe(calendarIDs: Set<String>, listIDs: Set<String>) async
    func sync() async throws -> SyncReport
  }
  ```
- LEO `Item`s sourced from EventKit have `externalRef: ExternalRef?` set:
  ```swift
  struct ExternalRef: Hashable, Sendable {
    let source: ExternalSource   // .eventKit
    let identifier: String       // EKEvent.eventIdentifier or EKReminder.calendarItemIdentifier
    let lastSeen: Date
  }
  ```
- A settings screen `Features/Settings/Views/CalendarsSettings.swift` lists calendars/lists with on/off toggles, persisted in user defaults (settings-only, per conventions).
- First sync runs after permission grant; subsequent syncs are scheduled by `EKEventStoreChangedNotification`.
- Sync report includes counts: imported, updated, removed.

**How to build it**
1. Permission: `EKEventStore.requestFullAccessToEvents` and `requestFullAccessToReminders` (iOS 17+ split). Handle denied gracefully.
2. Mapping `EKEvent` → `EventItem`:
   - `eventIdentifier` → `ExternalRef.identifier`.
   - `startDate` / `endDate` → `.timeBlock`.
   - `recurrenceRules.first` → `RRule` (write a converter `RRule(_ ekRule: EKRecurrenceRule)`).
   - `location` → `EventItem.location`.
   - `attendees` → names only.
3. Mapping `EKReminder` → `ReminderItem`:
   - `dueDateComponents` → `.point` if has time, else `.untimed`.
4. Don't mirror the user's *entire* calendar history — bound to ±30 days from today (configurable). Note this in task body.
5. Detect deletions by diffing the last-seen identifier set against the current EventKit set, scoped to subscribed calendars.

**Verification**
- [ ] Subscribed calendar → events appear in Today/Inbox with externalRef set.
- [ ] Editing an event in iOS Calendar → LEO reflects the change after next sync (≤ 30s with notification observer).
- [ ] Toggling a calendar off removes its events from LEO without affecting native data.

**Notes / decisions**
- We don't import iOS calendars older than 30 days even if visible. Avoid pollution.

---

### M3-T02 — EventKit bridge (write-back) + conflict policy
- **Status:** TODO
- **Depends on:** M3-T01
- **Estimated effort:** L

**Goal**
Items the user creates or edits in LEO are written back to a designated iOS calendar/list. Resolve conflicts deterministically.

**What to build (acceptance criteria)**
- A "Default write-back calendar" and "Default write-back reminder list" setting, picked at first run.
- On `EventItem` save: if user permits, write/update the corresponding `EKEvent`. Same for `ReminderItem` ↔ `EKReminder`.
- Items created by LEO that haven't been synced get an `ExternalRef` after first successful write.
- Conflict policy:
  - **Last-write-wins for time fields.** Compare `EKEvent.lastModifiedDate` with LEO's `updatedAt`.
  - **LEO wins for LEO-only metadata** (importance, tags, recurrence extensions, AI rationale). These never overwrite native data because they don't exist there.
  - **Native wins for native-only attributes** (full attendee objects, calendar color, alarm types we don't model).
  - **Deletion is hard:** native deletion → LEO removes its item; LEO deletion → native deletion via EventKit.
- Edge cases documented:
  - User edits in both apps in the same sync window → last-write-wins applies, with a notification "Synced X (your calendar's edit was newer)".

**How to build it**
1. Write-back happens *after* the local SwiftData save commits, in a `Task` launched from the repository.
2. Use `EKEventStore.commit()` per write to flush to disk; batch where possible.
3. RRule → EKRecurrenceRule conversion: invert the M3-T01 mapping. Some LEO extensions (workdays-only, holidays) **don't translate** — note this and either store as native daily plus `EXDATE`s, or refuse to write-back and surface an inline note "this rule is LEO-only and won't appear in iOS Calendar".
4. Tests: round-trip sync (LEO save → EK → LEO sync → equality).

**Verification**
- [ ] Create event in LEO → appears in iOS Calendar within 5s.
- [ ] Edit in iOS Calendar → reflected in LEO.
- [ ] Delete in either app → removed in the other.
- [ ] LEO-only metadata preserved across sync cycles.
- [ ] LEO-only recurrence extensions either survive (via EXDATEs) or surface a clear UI warning.

---

### M3-T03 — Lock-screen / Home-screen widgets
- **Status:** TODO
- **Depends on:** M3-T01
- **Estimated effort:** L

**Goal**
Four widget kinds: Today list, Next-up, Quick-add, Habit ring.

**What to build (acceptance criteria)**
- New target: `LEOWidgets` (Widget Extension) sharing the App Group from M0.
- Widgets use a shared `WidgetDataStore` that reads from the App Group container — a small JSON snapshot the main app writes on every meaningful change.
- Widgets:
  - **Today** (medium, large): list of next 5 items with type icon, time, title.
  - **Next-up** (small): single largest-card view of the next item.
  - **Quick-add** (small/medium, lock-screen circular): single button → opens app to capture surface (deep link).
  - **Habit ring** (medium, lock-screen rectangular): summary of today's habit completion.
- Refresh policy: provide a `TimelineProvider` that materializes timelines for the next 24h, with snapshots at item start times + 15-min cadence.
- Lock-screen widgets supported (iOS 18 lock-screen widget API).

**How to build it**
1. Widgets cannot read SwiftData directly across processes (sandbox). Main app exports a `widget_snapshot.json` to App Group on every save.
2. Snapshot schema is its own value type in `Integrations/Widgets/Snapshot.swift`. Versioned with a `schemaVersion` field to allow future evolution.
3. Quick-add widget uses `widgetURL(_:)` deep link `leo://capture` handled by the app's scene to focus the quick-add bar.
4. Don't build a configuration intent in v1 — widgets are static. Configurable widgets are a v1.x ask.

**Verification**
- [ ] Widgets render with seed data; refresh on item completion within 5min.
- [ ] Lock-screen widget readable in dark + light + tinted modes.
- [ ] Quick-add deep link focuses the capture bar.

---

### M3-T04 — Live Activity for next event
- **Status:** TODO
- **Depends on:** M3-T03
- **Estimated effort:** M

**Goal**
A Live Activity shows the next event with countdown; updates dynamically.

**What to build (acceptance criteria)**
- `Integrations/LiveActivities/NextEventActivity.swift`:
  - `ActivityAttributes` includes title, location, start, end.
  - `ActivityContent` includes minutes-until-start, current-state (upcoming, ongoing, late).
- Started automatically by the app when:
  - The next event is < 60 min away **and** Live Activities are enabled in settings.
- Updates every 5 min via `ActivityKit` push or local update; ends 5 min after the event ends.
- Lock screen layout, Dynamic Island compact + expanded layouts.

**How to build it**
1. Use local `Activity.update(...)` for v1 (no server push needed).
2. The "next event" computation lives in a small `NextItemDriver` actor; it observes the repository and starts/stops activities.
3. Don't tie this to alarms — alarms get their own Live Activity in M6.

**Verification**
- [ ] An event 30 min out triggers a Live Activity; countdown updates on lock screen.
- [ ] Editing the event updates the activity within 5 min.
- [ ] Activity disappears 5 min after end.

---

### M3-T05 — App Intents + Siri
- **Status:** TODO
- **Depends on:** M3-T01
- **Estimated effort:** M

**Goal**
Siri/Shortcuts can add tasks, complete items, and read today's summary.

**What to build (acceptance criteria)**
- `Integrations/AppIntents/`:
  - `CreateItemIntent` — parameter: text. Routes through the same parser pipeline as quick-add.
  - `CompleteItemIntent` — parameter: item picker (entity query).
  - `GetTodayIntent` — returns a string summary.
- `LEOItemEntity: AppEntity` — ID + display string for the picker.
- `LEOAppShortcuts: AppShortcutsProvider` registers natural-language phrases ("add to LEO", "complete in LEO", "what's on my LEO today").
- Intents donate after each app usage so Siri suggestions surface them.
- All intents are `OpenAppIntent: false` where reasonable (operate without launching app).

**How to build it**
1. App Intents framework is the canonical path; Siri uses them automatically.
2. The entity query for `LEOItemEntity` runs over the repository; cap results to 50.
3. `GetTodayIntent.perform()` returns `.result(dialog: "...", view: someView)` for richer Siri output.

**Verification**
- [ ] "Hey Siri, add buy milk to LEO" → item created.
- [ ] "Hey Siri, complete buy milk in LEO" → item completes.
- [ ] "Hey Siri, what's on my LEO today" → summary spoken.

---

### M3-T06 — Focus filter integration
- **Status:** TODO
- **Depends on:** M3-T05
- **Estimated effort:** S

**Goal**
A Focus filter that hides personal/work items based on user-configured tags or calendars.

**What to build (acceptance criteria)**
- `Integrations/Focus/LEOFocusFilter.swift` conforms to `SetFocusFilterIntent`.
- User configures (in iOS Settings → Focus → Add Filter): which tags to hide / which calendars to hide.
- When the filter is active, Today and Inbox views hide matching items.
- A small badge in Today header shows "Focus filter active" with tap-to-disable.

**How to build it**
1. Use `SetFocusFilterIntent` from App Intents.
2. State is per-Focus; LEO observes via the App Intents framework and updates a `FocusFilterState` actor.
3. Hiding is a view-layer concern; the underlying data is unchanged.

**Verification**
- [ ] Configure Work focus to hide "personal" tag → enabling Work hides those items.
- [ ] Disabling focus restores the items.

---

### M3-T07 — CloudKit deploy & multi-device hardening
- **Status:** TODO
- **Depends on:** all M3 tasks
- **Estimated effort:** M

**Goal**
Move CloudKit schema from Development to Production, harden sync error handling.

**What to build (acceptance criteria)**
- CloudKit Dashboard: schema deployed to Production (one-way; we don't roll back).
- Error handling: `CKError` cases have explicit handling — `notAuthenticated`, `quotaExceeded`, `networkUnavailable`, `serverRejectedRequest`, `incompatibleVersion`. Each maps to a user-facing recovery hint.
- A "Sync status" panel in Settings showing: account state, last sync time, pending changes count, errors.
- Sync conflict policy is documented in code at `Persistence/CloudKit/CONFLICTS.md` (yes, a markdown doc here is OK; this is policy not memory).
- Multi-device test: 3 devices simultaneously editing converges within 60s.

**How to build it**
1. Before deploying schema, run a migration smoke test: add a new field locally, sync, verify CloudKit accepts.
2. **STOP AND ASK** the user before clicking "Deploy" in CloudKit Dashboard. This is irreversible at the field level.
3. Production deploy ⇒ all field types frozen. Add a checklist to `IMPLEMENTATION_PLAN.md` decision log.

**Verification**
- [ ] Three-device convergence < 60s.
- [ ] Each documented `CKError` case shows the right UI.
- [ ] Production schema visible in CloudKit Dashboard.

---

## Exit criteria for M3

- [ ] All seven tasks `DONE`.
- [ ] EventKit two-way sync bidirectional within 30s.
- [ ] Widgets render and refresh; deep links work.
- [ ] App Intents wired and donatable.
- [ ] Production CloudKit schema deployed.
- [ ] User signs off in chat.
