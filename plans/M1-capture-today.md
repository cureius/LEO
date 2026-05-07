# M1 — Capture & Today

**Goal of this milestone:** A usable single-screen app: capture by typing, see your day, edit/complete items. This is the first time LEO is dogfoodable.

**Target ship:** 2026-06-11 (3 weeks).

**Read before starting:** [`AGENTS.md`](../AGENTS.md), [`IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md), [`conventions.md`](conventions.md), [`PRD.md`](../PRD.md) §7.1 and §7.2.

**Prerequisites:** M0 fully done (Domain types, persistence, repositories, design system).

---

## Task summary

- [ ] M1-T01 — Today view scaffold
- [ ] M1-T02 — Item row component + detail sheet
- [ ] M1-T03 — Quick-add bar UI + view model
- [ ] M1-T04 — Deterministic date parser
- [ ] M1-T05 — Foundation Models parser fallback
- [ ] M1-T06 — Inbox view
- [ ] M1-T07 — Drag-to-reschedule on Today
- [ ] M1-T08 — Accessibility + Dynamic Type pass

---

### M1-T01 — Today view scaffold
- **Status:** TODO
- **Depends on:** M0 complete
- **Estimated effort:** M

**Goal**
Lay out the Today timeline with date header, hour rail, time-blocked items rendered at correct positions, and untimed items pinned to a separate "no time set" lane.

**What to build (acceptance criteria)**
- `Features/Today/Views/TodayView.swift` — top-level view.
- `Features/Today/Views/TodayTimeline.swift` — the scrollable timeline.
- `Features/Today/ViewModels/TodayViewModel.swift` — `@Observable` view model exposing `items: [any Item]` for the current date plus selectors (untimed vs. timed).
- Layout:
  - Sticky date header showing weekday + date + a "today" indicator.
  - Hour rail on the left from 6am to 11pm by default; auto-extends if items fall outside.
  - Items in `.timeBlock` and `.point` anchors render at their times with height proportional to duration (point items get a fixed minimum height).
  - Items with `.untimed` or `.dueAt` (without a time-of-day) appear in a top "no time set" stack above the rail.
  - Past time of day is greyed out; current time draws a "now" line.
- View model fetches via `ItemRepository.fetch(predicate: .inDateInterval(today))`; refreshes when the repository signals a change.
- An empty state (`LEOEmptyState`) appears when no items today.

**How to build it**
1. Build `TodayTimeline` as a `ScrollView` containing a `ZStack { hourRail; itemsLayer }`. Items position with `.offset(y:)` from `Calendar.current` math.
2. The "now" line is its own subview using a `TimelineView(.periodic(from: .now, by: 60))` so it ticks once per minute without recomposing the whole tree.
3. View model: subscribe to repository updates via an `AsyncStream<Void>` exposed by `ItemRepository.changes()`; on emit, refetch.
4. Use `@Environment(\.itemRepository)` injection.
5. Performance: don't render items off-screen. Wrap items layer in `LazyVStack`-equivalent custom layout, or compute on-screen subset before rendering.
6. **Don't** build week view here. That's a follow-up task in M3 (or a new task created in M1 if needed).

**Verification**
- [ ] With seed data, Today shows ~5–10 items distributed through the day plus 2 untimed.
- [ ] Scroll is smooth (60fps) with up to 50 items in the day.
- [ ] "Now" line moves visibly within 60s.
- [ ] Empty state shown when no items.

---

### M1-T02 — Item row + detail sheet
- **Status:** TODO
- **Depends on:** M1-T01
- **Estimated effort:** M

**Goal**
Reusable item row used by Today, Inbox, and later by Week. Detail sheet for editing a single item.

**What to build (acceptance criteria)**
- `DesignSystem/Components/ItemRow.swift` — renders any `any Item`:
  - Leading: completion checkbox (or alarm icon, event dot, etc., based on type).
  - Title + secondary line (time, location, recurrence indicator).
  - Trailing: importance pill (only if `.high` or `.urgent`), tag chips (max 2 inline; "+N" overflow).
  - Long-press → context menu (Complete, Snooze, Edit, Delete).
- `Features/ItemDetail/Views/ItemDetailSheet.swift` — bottom sheet with:
  - Editable title, notes (single line per PRD).
  - Anchor editor (date + time picker, or "no time set").
  - Type-specific fields (location for Event, sound profile for Alarm, etc.).
  - Tags picker.
  - Importance picker.
  - Save / Cancel / Delete actions.
- `Features/ItemDetail/ViewModels/ItemDetailViewModel.swift` — `@Observable`, owns a draft Item, validates on save, calls repository.
- Completing an item via checkbox or long-press triggers a haptic and animates out of Today.

**How to build it**
1. Row uses `switch` on the concrete type to choose the leading icon and secondary line. Keep this `switch` in one extension — every new Item type adds a case here, by design.
2. Detail sheet uses SwiftUI `.sheet` with `.presentationDetents([.medium, .large])`.
3. Editing: copy the item into a draft on appear; only commit on Save. Cancel discards.
4. Validation: title non-empty; if `.timeBlock`, end > start.
5. **Concurrency:** repository writes happen in a `Task { ... }` triggered from a `@MainActor` button handler. Show a brief toast on success/failure.

**Verification**
- [ ] Tap an item on Today → sheet opens with current values.
- [ ] Edit title/time, save → row updates within ~200ms.
- [ ] Long-press → context menu, Complete works, item animates away.
- [ ] Delete from sheet → confirmation, then removed; survives relaunch.

---

### M1-T03 — Quick-add bar UI + view model
- **Status:** TODO
- **Depends on:** M1-T02
- **Estimated effort:** M

**Goal**
A persistent capture surface on Today that turns free text into a draft Item via the parser pipeline (M1-T04, M1-T05) and saves it.

**What to build (acceptance criteria)**
- `Features/Capture/Views/QuickAddBar.swift` — pinned to the bottom of Today; a single-line `LEOTextField`, submit button, mic icon (voice in M1-T04 only if trivial; full speech in M6).
- `Features/Capture/ViewModels/QuickAddViewModel.swift` — `@Observable`:
  - `text: String` bound to the field.
  - `parsing: ParseState` (idle/parsing/parsed/failed).
  - `parsedDraft: any Item?` — what we'd save if the user submits now.
  - `parsedSummary: String?` — human echo of what we understood (e.g., "Task — call mom Sunday 6pm — recurring weekly").
  - On submit: save the draft via `ItemRepository.add`, clear text.
- A small "interpretation chip" appears above the bar as the user types, showing `parsedSummary` and offering "Send to Inbox" if confidence is low.
- Submit on Return; Shift+Return inserts newline (multi-line growth up to 4 lines).
- Successful save fires a haptic + a toast "Captured" with an Undo (10s window using a delayed delete).

**How to build it**
1. Parser pipeline (interface only in this task; implementations in T04/T05):
   ```swift
   protocol QuickAddParser: Sendable {
     func parse(_ text: String) async -> ParseResult
   }
   struct ParseResult { let draft: (any Item)?; let confidence: Double; let rationale: String }
   ```
   `QuickAddViewModel` debounces `text` changes by 250ms, calls the injected parser, updates state.
2. Inject parser via environment with a stub that always parses to a `TaskItem` titled with the raw text. T04 replaces the stub.
3. Avoid showing the interpretation chip while the user is mid-word; only show after a 250ms quiet period.
4. Undo: implement using a single-slot "trash" — last saved item id; if user taps Undo within 10s, repository deletes it. Don't build a full undo stack in v1.
5. **A11y:** the interpretation chip must be readable by VoiceOver before the user submits.

**Verification**
- [ ] Typing arbitrary text → submit → row appears on Today (or Inbox if no time parsed).
- [ ] Interpretation chip updates after pause.
- [ ] Undo within 10s removes the item; after 10s, undo button is gone.
- [ ] Bar doesn't block keyboard input or get covered by the keyboard.

---

### M1-T04 — Deterministic date parser
- **Status:** TODO
- **Depends on:** M1-T03
- **Estimated effort:** L

**Goal**
A fast, dependency-free parser that handles 80%+ of common phrases without hitting any LLM. This is the floor of the quick-add experience.

**What to build (acceptance criteria)**
- `Domain/Capture/Parsers/DeterministicParser.swift` conforming to `QuickAddParser`.
- Recognizes:
  - Times: "6pm", "6:30am", "noon", "midnight", "in 20 min", "in 2 hours".
  - Dates: "tomorrow", "today", "tonight", "Friday", "this Saturday", "next Tuesday", "June 12", "12/06" (locale-aware), "in 3 days", "next week".
  - Combined: "Friday at 3pm", "tomorrow morning" (=8am default), "tonight" (=8pm default), "next Mon 9am".
  - Recurrence: "every day", "every Sunday", "every other Tuesday", "MWF", "weekdays", "every 3 days".
  - Type hints: starting with verbs "remind me to / wake me at / call / meet" → respective Item type. "by" before a date → Task with deadline. "for N hours" → EventItem with duration.
  - Locations: "@ Pine St", "at Equinox" → stored as `EventItem.location`.
  - Importance: "!" or "high priority", "urgent", "asap" → bumps importance.
- Returns `ParseResult` with confidence in [0,1]:
  - 1.0: type + time/date both detected unambiguously.
  - 0.5–0.9: type unclear or date relative without anchor.
  - <0.5: barely parsed; sender should send to Inbox by default.
- A test corpus of ~80 phrases lives at `LEOTests/Domain/Capture/parser_corpus.json` with expected `(type, anchor, recurrence, confidence)`.

**How to build it**
1. Use Apple's `Date` formatters (`DateFormatter`, `ISO8601DateFormatter`) and `NSDataDetector(.date)` as a starting point. Augment with custom regex for things detectors miss (recurrence, "MWF", "every other").
2. Don't reach for a third-party chrono library in v1 — Apple's `NSDataDetector` covers most cases. Document gaps if you find them.
3. Architecture: split into stages — `Tokenizer → Recognizers (date, time, recurrence, type, location, importance) → Composer`. Each recognizer returns possibly-empty extracted fields plus residual text.
4. Composer assembles into the right `Item` concrete type:
   - Has time + duration → `EventItem`.
   - Has time + recurrence → `EventItem` if duration, else `ReminderItem`.
   - "remind me" prefix or `.point` time only → `ReminderItem`.
   - "wake me" prefix → `AlarmItem`.
   - Has only "by <date>" → `TaskItem` with deadline.
   - Default → `TaskItem`.
5. Confidence: deterministic rules — every recognized field adds a weighted score; missing critical fields penalize.
6. Tests use the JSON corpus. Add `XCTAssertEqual` per-row. Add a top-level summary asserting ≥90% pass.

**Verification**
- [ ] Corpus pass rate ≥ 90%.
- [ ] Quick-add bar shows correct interpretation for the canonical PRD phrases:
  - "call mom every Sunday at 6pm" → ReminderItem, weekly Sunday 6pm.
  - "draft Q3 report by Friday" → TaskItem with deadline.
  - "wake me up at 6:30 tomorrow" → AlarmItem, 6:30 tomorrow.
  - "gym MWF 7am for 1 hour" → EventItem, M/W/F 7am 60min.
  - "dentist June 12 at 2pm at 401 Pine St" → EventItem with location.
- [ ] Parser runs in < 50ms on a typical phrase (XCTest `measure`).

---

### M1-T05 — Foundation Models parser fallback
- **Status:** TODO
- **Depends on:** M1-T04
- **Estimated effort:** M

**Goal**
When the deterministic parser's confidence is below threshold, ask Apple's on-device LLM (FoundationModels) to fill the gaps. Stay on-device.

**What to build (acceptance criteria)**
- `Domain/Capture/Parsers/FoundationModelsParser.swift` conforming to `QuickAddParser`.
- A *composite* parser `Domain/Capture/Parsers/CompositeQuickAddParser.swift`:
  1. Run deterministic parser.
  2. If confidence ≥ 0.8, return.
  3. Otherwise, call Foundation Models with a structured prompt and merge results (FM fills only fields the deterministic parser didn't produce).
- Uses `FoundationModels` framework (`SystemLanguageModel`, `LanguageModelSession`) with tool-call-style structured output schema mapping to `ParseResult`.
- Hard failure cases: device lacks Apple Intelligence support → composite returns deterministic result regardless of confidence and surfaces "AI assist unavailable" once per session, never blocks capture.
- A small offline mode: if FM is unavailable for any reason (cold start, network, region), composite falls back gracefully.

**How to build it**
1. Check availability: `SystemLanguageModel.default.availability`. If unavailable, surface in settings and skip the FM step entirely.
2. Define a `Generable` schema for the structured output:
   ```swift
   @Generable struct ParsedDraft {
     let kind: ItemKind        // enum
     let title: String
     let isoStart: String?     // ISO8601 if known
     let isoEnd: String?
     let recurrenceRRULE: String?
     let location: String?
     let importance: Importance
   }
   ```
3. Prompt: short, deterministic, includes today's date+timezone. Cache the system prompt across calls.
4. Latency budget: 500ms p50. Time out at 1.5s and fall back to deterministic.
5. Privacy: assert in code that FM calls never include any non-user-typed strings (no calendar context).

**Verification**
- [ ] On a device with Apple Intelligence, ambiguous phrases that deterministic scored < 0.8 ("plan trip to Paris next month for two weeks") become higher-confidence drafts.
- [ ] On a device without Apple Intelligence, capture still works; FM step is skipped silently.
- [ ] No FM call exceeds 1.5s wall-clock without timeout firing.

**Notes / decisions**
- The prompt and schema are versioned. When the user changes phrasing of a hint (e.g., "asap" → urgent), increment a `prompt_v` constant in code and update tests.

---

### M1-T06 — Inbox view
- **Status:** TODO
- **Depends on:** M1-T03
- **Estimated effort:** S

**Goal**
A list view for items that lack scheduling info, so they can be triaged later.

**What to build (acceptance criteria)**
- `Features/Inbox/Views/InboxView.swift` with header, list of `ItemRow`s sorted by `createdAt` desc.
- Shown via a tab or a swipe target on Today (final placement TBD; for M1, add a tab).
- Tapping an item opens the detail sheet with focus on the date picker.
- Pull-to-refresh; empty state.
- Long-press → "Schedule for today/tomorrow/this week" quick actions that add an anchor.

**How to build it**
1. Predicate: `.untimed` anchor or `.dueAt` without time-of-day where the date is in the past.
2. The "schedule for…" quick actions update `anchor` only; don't auto-promote `.untimed` to a full event.
3. Use the same `ItemRow` from T02; don't fork a list cell.

**Verification**
- [ ] Captures with no parsed date appear in Inbox.
- [ ] Quick-actions move an item out of Inbox onto Today.
- [ ] Empty state shown when nothing in Inbox.

---

### M1-T07 — Drag-to-reschedule on Today
- **Status:** TODO
- **Depends on:** M1-T01, M1-T02
- **Estimated effort:** M

**Goal**
Drag an item on the Today timeline to a new time. Snap to 5-minute increments. Conflict warnings on drop, but no AI yet (M4 adds AI ripple).

**What to build (acceptance criteria)**
- Long-press an item on Today to start a drag; visual lift.
- Drag updates a temporary "ghost" position in real time.
- Drop snaps to nearest 5 minutes.
- Drop triggers a toast with Undo + a "Conflicts with X" banner if there's overlap.
- Edits only `anchor`; preserves duration; preserves recurrence (single-occurrence override; series untouched in v1).

**How to build it**
1. Use SwiftUI's `.gesture(DragGesture)` with `minimumDistance` after a long-press transition.
2. Drag math: convert `value.translation.height` to minutes via the timeline's pixels-per-minute scale.
3. Conflict detection: query repository for items overlapping the candidate time window; flag visually before drop.
4. For recurring instances, don't touch the series — write a per-occurrence override (the override mechanism comes in M2; for M1, no-op-warn if user tries to drag a recurring instance).
5. Haptic on snap; different haptic on drop.

**Verification**
- [ ] Drag a 1h Event from 10am to 2pm; the row moves smoothly and saves.
- [ ] Snap to 5-min steps visible in the ghost preview.
- [ ] Conflict banner shows when overlap exists; tapping it scrolls to conflicting item.
- [ ] Undo restores the prior time within 10s.

---

### M1-T08 — Accessibility + Dynamic Type pass
- **Status:** TODO
- **Depends on:** M1-T01, M1-T02, M1-T03, M1-T06
- **Estimated effort:** M

**Goal**
The app is usable end-to-end with VoiceOver and at AX5 type size. This is non-negotiable for App Store quality and for our positioning.

**What to build (acceptance criteria)**
- Every interactive element has an `.accessibilityLabel` (and `.accessibilityHint` where the action is non-obvious).
- The Today timeline uses `accessibilityElement(children: .combine)` per item with a label like "Task, draft Q3 report, due Friday, high importance".
- Quick-add bar: parser interpretation is announced once per stable parse via `.accessibilityNotification`.
- Reduced motion: the "now" line tick and item-completion animations respect `accessibilityReduceMotion`.
- AX5 type size: every screen scrolls instead of truncating; no text clipping.
- Color contrast: WCAG AA across all backgrounds.

**How to build it**
1. Run the app under VoiceOver and walk every screen; record gaps in this task's notes; fix.
2. Use Xcode's Accessibility Inspector for contrast and label audits.
3. For DynamicType, add a debug menu toggle that forces `dynamicTypeSize = .accessibility5` so this is always one tap away.
4. Tests: add a couple of UI tests asserting key labels exist (`XCUIApplication().buttons["quickAddSubmit"].exists`).

**Verification**
- [ ] VoiceOver flow: open app → hear today summary → capture an item → hear confirmation → review item.
- [ ] At AX5: no clipped labels, no horizontal scroll on Today.
- [ ] Reduce Motion: animations replaced with cross-fades.
- [ ] Contrast inspector: zero AA violations.

---

## Exit criteria for M1

- [ ] All eight tasks `DONE`.
- [ ] Raj uses LEO as the only capture surface for a full week (dogfood).
- [ ] Parser corpus pass rate ≥ 90%.
- [ ] Today renders 50 items at 60fps.
- [ ] All a11y gates from M1-T08 pass.
- [ ] User signs off in chat.
