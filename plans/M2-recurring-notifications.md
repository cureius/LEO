# M2 — Recurring & Notifications

**Goal of this milestone:** A recurrence engine that beats Apple Reminders, plus reliable time- and location-based notifications.

**Target ship:** 2026-07-02 (3 weeks).

**Read before starting:** [`AGENTS.md`](../AGENTS.md), [`PRD.md`](../PRD.md) §7.3 and §7.4, RFC 5545 §3.3.10 (RRULE).

**Prerequisites:** M1 dogfooded for at least one week. Domain types and persistence stable.

---

## Task summary

- [x] M2-T01 — RRULE parser + serializer
- [x] M2-T02 — Recurrence expansion engine
- [x] M2-T03 — Per-occurrence overrides (skip / move)
- [x] M2-T04 — LEO recurrence extensions (workdays-only, holidays, etc.)
- [x] M2-T05 — Visual recurrence rule builder
- [x] M2-T06 — Time-based notifications
- [x] M2-T07 — Location reminders + travel-time pre-reminders

---

### M2-T01 — RRULE parser + serializer
- **Status:** TODO
- **Depends on:** M0 complete
- **Estimated effort:** L

**Goal**
A round-trippable Swift representation of RFC 5545 RRULE strings.

**What to build (acceptance criteria)**
- `Domain/Recurrence/RRule.swift` — value type:
  ```swift
  struct RRule: Hashable, Sendable {
    var frequency: Frequency   // .secondly...yearly (we use daily..yearly)
    var interval: Int          // default 1
    var count: Int?
    var until: Date?
    var byDay: [WeekdayOccurrence]   // e.g., 2MO = "second Monday"
    var byMonthDay: [Int]
    var byMonth: [Int]
    var byYearDay: [Int]
    var bySetPos: [Int]
    var weekStart: Weekday     // default .monday
  }
  ```
- Parser: `static func parse(_ string: String) throws -> RRule`. Accepts "FREQ=WEEKLY;BYDAY=MO,WE,FR;INTERVAL=2".
- Serializer: `var rfc5545: String { get }` — round-trips the parsed value; canonical key order; uppercase keys/values.
- Throws on malformed input with specific error cases (`unsupportedFrequency`, `unknownKey`, `invalidByDay`, etc.).
- Test corpus at `LEOTests/Domain/Recurrence/rrule_corpus.json`: 60+ valid + invalid samples with expected results.

**How to build it**
1. Tokenize on `;` then `=`. Validate keys against an allowlist enum.
2. Represent `BYDAY` carefully: it can be `MO,WE,FR` *or* `2MO` (second Monday). Parse "2MO" with regex `^(-?\d+)?(MO|TU|WE|TH|FR|SA|SU)$`.
3. Round-trip: parsing then serializing must produce a canonical normalized form (key order, uppercase). The parser tests assert `parse(serialize(parse(s))) == parse(s)`.
4. Don't support timezones inside RRULE in v1; we always interpret in `Calendar.current` and store anchor times in UTC.
5. **Don't** bridge to EventKit's `EKRecurrenceRule` here. Conversion happens in `Persistence/EventKit/` in M3.

**Verification**
- [ ] All corpus samples parse to expected `RRule` or throw expected error.
- [ ] Round-trip serialization stable (parse twice = same output).
- [ ] Performance: parse 1000 random RRULEs in < 50ms total.

---

### M2-T02 — Recurrence expansion engine
- **Status:** TODO
- **Depends on:** M2-T01
- **Estimated effort:** L

**Goal**
Given an `RRule` + a start `Date` + a query window, produce occurrence dates.

**What to build (acceptance criteria)**
- `Domain/Recurrence/RecurrenceEngine.swift`:
  ```swift
  actor RecurrenceEngine {
    func occurrences(rule: RRule, start: Date, in window: DateInterval, calendar: Calendar = .current) -> [Date]
    func nextOccurrence(rule: RRule, after: Date, anchorStart: Date) -> Date?
  }
  ```
- Supports DAILY, WEEKLY, MONTHLY, YEARLY × INTERVAL × COUNT|UNTIL × BYDAY|BYMONTHDAY|BYSETPOS|BYMONTH.
- Honors `weekStart`.
- Window query is bounded: never expands more than `max(window.duration, 1y)` worth of occurrences; throws `RecurrenceError.windowTooLarge` if asked for more than 5y.
- Cache: the engine memoizes recent (rule,start,window) → results with a small LRU (50 entries).
- Golden-file tests at `LEOTests/Domain/Recurrence/golden/` — input rule + window → expected occurrences. 30+ goldens covering edge cases (DST transitions, leap years, end-of-month).

**How to build it**
1. Implement frequency-by-frequency: weekly is easiest (iterate days, filter BYDAY), then daily, monthly (BYMONTHDAY + BYDAY combined), yearly.
2. **DST edge case:** when expanding weekly with a time-of-day, preserve "wall-clock" time, not absolute time. Use `Calendar.date(bySettingHour:minute:second:of:)`.
3. **End-of-month edge case:** a monthly rule starting Jan 31 produces Feb 28/29, Mar 31, etc. — use `Calendar.date(byAdding: .month, value: n, to: start)` and accept that February drops to its last day automatically.
4. BYSETPOS: after computing candidate dates within a "set" (e.g., all Mondays in a month), apply BYSETPOS to pick the Nth.
5. Cache key includes `calendar.identifier` + `calendar.timeZone.identifier` + `weekStart` to be safe across user changes.

**Verification**
- [ ] All goldens pass.
- [ ] Performance: expand a 1y window of weekly recurrence in < 5ms.
- [ ] DST golden: a 9:30am weekly Tuesday across spring-forward stays at 9:30 wall time.
- [ ] Leap-year golden: yearly Feb 29 schedules on Feb 28 of non-leap years (LEO policy: "round down"; document in test).

---

### M2-T03 — Per-occurrence overrides
- **Status:** TODO
- **Depends on:** M2-T02
- **Estimated effort:** M

**Goal**
Skip or move a single occurrence of a recurring item without breaking the series.

**What to build (acceptance criteria)**
- `Domain/Recurrence/Series.swift`:
  ```swift
  struct Series: Hashable, Sendable {
    let id: UUID                // links to all materialized HabitInstance/EventItem occurrences
    let rule: RRule
    let template: any Item
    var overrides: [Date: Override]   // keyed by canonical occurrence date
  }
  enum Override: Hashable, Sendable {
    case skip(reason: String?)
    case move(to: DateInterval)
    case fieldsOnly(ItemPatch)        // override title/notes/etc. without changing time
  }
  ```
- `RecurrenceEngine.occurrences(...)` honors overrides: skipped occurrences are removed; moved occurrences appear at new time.
- Repository APIs:
  - `func skipOccurrence(seriesID: UUID, date: Date, reason: String?) async throws`
  - `func moveOccurrence(seriesID: UUID, originalDate: Date, to: DateInterval) async throws`
  - `func clearOverride(seriesID: UUID, date: Date) async throws`
- Persistence: overrides stored in a new `StoredOverride` model with a relationship to the `StoredSeries`.

**How to build it**
1. `Series` is the persistence-side concept; existing `StoredEvent`/`StoredHabit` etc. either *are* a series (if rule is non-nil) or aren't.
2. Override key uses the canonical occurrence date (i.e., the date the engine *would* produce, before override). Document this — it's the only stable handle.
3. Long-press on a recurring item's row offers "Skip just this one" / "Move just this one" actions.
4. UI work in this task is minimal — long-press menu only. Full edit-this-vs-series flow in M2-T05.

**Verification**
- [ ] Skip a daily 7am habit instance for tomorrow → tomorrow's row gone, day after still appears.
- [ ] Move a weekly meeting from Tue to Wed for one week → series unchanged.
- [ ] Persist + relaunch: override survives.

---

### M2-T04 — LEO recurrence extensions
- **Status:** TODO
- **Depends on:** M2-T02
- **Estimated effort:** M

**Goal**
The features that incumbents fail at: workdays-only, holiday-aware skipping, "first weekday of month".

**What to build (acceptance criteria)**
- `Domain/Recurrence/Extensions/` with one file per extension:
  - `WorkdaysOnlyExtension` — filters out Sat/Sun.
  - `SkipUSHolidaysExtension` — uses an embedded holiday calendar (US federal holidays through 2030).
  - `FirstWeekdayOfMonthExtension` — replaces the occurrence with the first weekday-of-month if it falls on a weekend or holiday.
- `RecurrenceEngine.occurrences(rule:start:in:)` accepts an `extensions: [LEORuleExtension]` parameter and applies them in declared order *after* the RRULE expansion.
- Holiday data at `Resources/Holidays/us_federal.json`. Schema: `[{ name, date, observedDate? }]`. Parsed at app launch; held in memory.
- Settings toggle for "Skip US holidays for work-related items" (off by default in v1; user-facing behavior is per-item).
- Tests with 12+ goldens covering: holiday in middle of weekly recurrence, holiday on a Friday → following Monday, weekend-only skip with no holiday flag.

**How to build it**
1. Don't build international holiday support yet. Document this in the task notes; new ext files (`SkipUKHolidaysExtension`) are v1.x.
2. Holiday JSON is hand-curated for now; in v1.1 we can pull from a third-party API (with caching).
3. Order matters: WorkdaysOnly before Holidays before FirstWeekdayOfMonth — document the order in `RecurrenceEngine`.

**Verification**
- [ ] A weekly Monday rule with `[.skipUSHolidays]` skips Memorial Day.
- [ ] A daily rule with `[.workdaysOnly]` excludes weekends.
- [ ] All extension goldens pass.

---

### M2-T05 — Visual recurrence rule builder
- **Status:** TODO
- **Depends on:** M2-T01, M2-T02, M2-T04
- **Estimated effort:** L

**Goal**
A SwiftUI form that lets the user define any supported recurrence visually, and a natural-language input that round-trips with the form.

**What to build (acceptance criteria)**
- `Features/Recurrence/Views/RecurrenceBuilder.swift` — pickers for frequency, interval, days-of-week, end condition (never / on date / after N occurrences), and a "More" disclosure for BYMONTHDAY, BYSETPOS, LEO extensions.
- A natural-language input field at the top: "every other Tuesday and Thursday". As the user types, the form below updates (parsed via M1-T04 deterministic parser augmented for recurrence). The form values are also serialized back into a NL summary above the form ("Repeats: every 2 weeks on Tue, Thu").
- Edit-recurring-item flow: when the user changes a recurring item via Detail Sheet, prompt "Apply to this only / This and future / Whole series" before committing.
- Builder integrates into `ItemDetailSheet` from M1-T02 as a section.
- Builder previews show the next 5 occurrences as a sanity check.

**How to build it**
1. Form ↔ `RRule` is a two-way binding. Keep the model (`RRule` + `[LEORuleExtension]`) as the single source; the form binds to it.
2. NL → RRule uses the deterministic parser's recurrence recognizer. NL → form happens by mutating the bound model.
3. RRule → NL summary uses a small dedicated formatter (`RecurrenceFormatter`); this is presentation, not part of the engine.
4. Edit-series prompt: standard SwiftUI confirmation dialog with three actions. Each action calls a different repository method (`updateOccurrence`, `splitSeries(at:)`, `updateSeries`).

**Verification**
- [ ] Building "every other Tuesday and Thursday for 10 occurrences" via the form produces an RRULE that the engine expands correctly.
- [ ] NL field round-trips for at least 15 sample phrases.
- [ ] Edit-series prompt works for all three options without corrupting the data model.

---

### M2-T06 — Time-based notifications
- **Status:** TODO
- **Depends on:** M2-T02, M0 complete
- **Estimated effort:** M

**Goal**
LEO schedules and delivers local notifications for Reminders, Alarms, and Events with `leadTime`.

**What to build (acceptance criteria)**
- `Notifications/NotificationManager.swift`:
  ```swift
  actor NotificationManager {
    func requestAuthorization() async -> AuthorizationStatus
    func sync(for items: [any Item]) async  // upserts/cancels notifications
    func cancelAll() async
  }
  ```
- For each item with a `.point` or `.dueAt` anchor (and `.timeBlock` with `leadTime`), schedule a `UNNotificationRequest` with a stable identifier (`"item.\(id).primary"`).
- Pre-reminders: a separate request with id `"item.\(id).pre.\(leadSeconds)"` at `anchor - leadTime`.
- For recurring items, expand the next 30 days and schedule individual one-off notifications (iOS limit ≈ 64 pending; we manage the sliding window).
- A background task (`BGAppRefreshTask`) wakes daily to top up the notification window.
- Notification actions: "Complete", "Snooze 10m / 1h", "Open".
- Permission flow: prompt at first capture if not yet granted; show Settings deep-link if denied.

**How to build it**
1. Use `UNUserNotificationCenter.current()`. All scheduling goes through `NotificationManager`.
2. Sync algorithm:
   - Compute desired set of `(identifier, request)` for the next 30 days.
   - Diff against `getPendingNotificationRequests()`.
   - Add missing, remove extraneous.
3. Background task registration in `LEOApp.init` via `BGTaskScheduler.shared.register`. Schedule for ~24h cadence.
4. Action handler: a `UNUserNotificationCenterDelegate` (registered in `LEOApp`) routes to the relevant repository method (`completeItem(id:)`, `snoozeItem(id:by:)`).
5. **Test on device.** Simulator notification handling has subtle differences (background task firing, sound).

**Verification**
- [ ] Schedule a reminder 60s out → notification fires; tap "Complete" → item completes in app.
- [ ] Schedule 50 recurring instances → all visible in `getPendingNotificationRequests()` for next 30 days.
- [ ] Cancel an item → its pending requests removed.
- [ ] Background task fires (use `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.leo.refresh"]` debugger trick).

---

### M2-T07 — Location reminders + travel-time pre-reminders
- **Status:** TODO
- **Depends on:** M2-T06
- **Estimated effort:** M

**Goal**
Items with location triggers fire on arrival/departure. Events with locations get smart "leave by" pre-reminders based on MapKit ETA.

**What to build (acceptance criteria)**
- `Notifications/LocationReminderManager.swift`:
  - Wraps `CLLocationManager` region monitoring.
  - On items with `.location(LocationTrigger)` anchor, registers up to 20 regions (iOS hard limit; manage with priority list).
  - On entering/leaving the region, posts a local notification.
- `Notifications/TravelTimePreReminder.swift`:
  - For `EventItem` with `location` and a known coordinate (geocoded once at save), computes `MKDirections` ETA periodically (every 30min within 6h of the event).
  - Schedules a one-off notification N minutes before "leave time" (configurable; default 5 min before).
  - Cancels if event time changes or user is already at the location.
- Permission: requests `When In Use` first; only requests `Always` if the user explicitly enables location reminders in settings.
- Privacy: nothing leaves the device; geocoding uses Apple's MapKit.

**How to build it**
1. Geocoding: on item save with a location string, call `CLGeocoder().geocodeAddressString` and cache the coordinate on the item.
2. Region monitoring caveats:
   - 100m minimum radius (iOS docs).
   - 20 region limit per app.
   - Manage a priority queue: nearest 20 unfired regions.
3. Travel-time job: a periodic background task (`BGProcessingTask`) every 30min, only enabled when there's an upcoming located event.
4. Battery: do not subscribe to continuous location updates. Region monitoring + on-demand `CLLocationManager.requestLocation` only.

**Verification**
- [ ] Set a "Buy milk" reminder at home → simulator location → arrive at home → notification fires.
- [ ] Set an event at a far address → app schedules a "leave in X" notification using ETA.
- [ ] Battery profile: < 0.2%/hr idle with active region monitoring on a typical workload.
- [ ] Permissions: "When In Use" requested at first location-touching feature; "Always" only if user opts in.

---

## Exit criteria for M2

- [ ] All seven tasks `DONE`.
- [ ] 100-test recurrence suite green.
- [ ] Notifications fire reliably across app force-quit and device reboot.
- [ ] Battery profile < 0.5%/hr idle with 200 recurring items.
- [ ] User signs off in chat.
