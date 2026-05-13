# MM3 — Today, Inbox, Habits, Item Detail

**Goal:** The three primary content panes (Today, Inbox, Habits) work on Mac with full feature parity to iOS. Item detail edits live in the inspector, not a sheet. History view is reachable from Today. Drag-to-reschedule works between dates.

**Exit criteria:**
- Selecting Today shows the same content the iOS Today view shows for the same Apple ID (verified against iPhone).
- Both Today modes (list and 24h timeline) work, with `⌘L` / `⌘T` toggles.
- Inbox shows untimed items, supports the same actions (schedule, complete, delete).
- Habits shows today's habit instances with streak rings.
- Item detail inspector lets the user edit every field that iOS's `ItemDetailSheet` does.
- Drag-and-drop between sidebar dates (drag an item onto Today vs. a future date) reschedules.
- Multi-select with `⌘`-click and `⇧`-click; bulk complete and bulk delete.
- History view reachable via a button in Today's toolbar.

## Summary checklist
- [ ] MM3-T01 — `MacTodayView` (list + timeline modes)
- [ ] MM3-T02 — `MacHistoryView`
- [ ] MM3-T03 — `MacInboxView`
- [ ] MM3-T04 — `MacItemDetailInspector` (full editing)
- [ ] MM3-T05 — `MacHabitsView`
- [ ] MM3-T06 — Drag-and-drop reschedule
- [ ] MM3-T07 — Multi-select + bulk actions

---

### MM3-T01 — `MacTodayView` (list + timeline modes)
- **Status:** TODO
- **Depends on:** MM2-T07
- **Estimated effort:** L

**Goal**
Port the iOS Today view to Mac, preserving both list and timeline modes, and using bigger-screen affordances (multi-column where helpful, persistent toolbar, no bottom-of-screen quick-add).

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Today/MacTodayView.swift` shows today's items grouped chronologically (timed before untimed) in list mode.
- Timeline mode is the 24-hour grid from iOS's `DayTimelineView`, fitted to the Mac middle column. Default for new users on Mac.
- A toolbar at the top has: date picker (← Today →), list/timeline toggle, "History" button, and a "Capture" field (real impl: MM4-T01; placeholder for now).
- Selecting an item from the list/timeline updates `nav.selectedItemID`, which drives the inspector.
- Completed items still appear in a `CompletedSection` at the bottom (same component as iOS).
- The view re-renders on `.leoDataDidChange`.
- `⌘L` toggles to list, `⌘T` toggles to timeline (wired via the View menu in MM2-T03).

**How to build it**
1. Create `LEO/PlatformMac/Features/Today/MacTodayView.swift`. Use the iOS `TodayViewModel` as-is — it's platform-neutral.
   ```swift
   import SwiftUI

   struct MacTodayView: View {
       @Environment(AppEnvironment.self) private var appEnv
       @Environment(MacNavigationModel.self) private var nav
       @State private var vm: TodayViewModel?
       @SceneStorage("leo.today.mode") private var modeRaw: String = "timeline"

       enum Mode: String, Hashable { case list, timeline }
       var mode: Mode { Mode(rawValue: modeRaw) ?? .timeline }

       var body: some View {
           VStack(spacing: 0) {
               toolbar
               Divider()
               if let vm {
                   ScrollView {
                       if mode == .list {
                           MacTodayListBody(vm: vm, selection: navBinding.selectedItemID)
                       } else {
                           MacDayTimelineBody(vm: vm, selection: navBinding.selectedItemID)
                       }
                   }
               } else {
                   ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
               }
           }
           .task {
               if vm == nil {
                   vm = TodayViewModel(itemRepository: appEnv.itemRepository)
                   await vm?.load()
               }
           }
           .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
               Task { await vm?.load() }
           }
       }

       private var toolbar: some View { /* date stepper + mode toggle + history button */ }
       private var navBinding: MacNavigationModel { nav } // helper
   }
   ```
2. Build `MacTodayListBody` as a port of `TodayScrollView` — same row component (`ItemRow`), same grouping helpers. Use `List` with `selection: $nav.selectedItemID` so multi-select and keyboard navigation work for free.
3. Build `MacDayTimelineBody` based on iOS `DayTimelineView`. Critical: keep the `VStack of hour rows + overlay(GeometryReader)` pattern documented in memory `feedback_swiftui_layout.md`. Do not switch to ZStack.
4. Wire up the toolbar buttons:
   - Date stepper: `vm.previousDay()` / `vm.nextDay()` (add these methods to the VM if absent).
   - Mode toggle: `Picker` with two segments.
   - History button: pushes `MacHistoryView()` into the same content pane via a `NavigationStack` wrapper.
5. Update `MacContentPane` so `.today → MacTodayView()` (replace the placeholder).
6. Confirm that the existing `TodayViewModel`'s public API supports day-navigation. If not, **add `previousDay()`/`nextDay()` methods** — these are additive and shared with iOS (so iOS may also adopt them; document but don't change iOS callers).

**Verification**
- [ ] Today list shows same items as iOS for the same Apple ID.
- [ ] Timeline mode auto-scrolls to current hour on entry.
- [ ] `⌘L` / `⌘T` toggle modes.
- [ ] Tapping/clicking a row sets `nav.selectedItemID`.
- [ ] Date stepper navigates ± 1 day.
- [ ] No "Cannot find type" runtime errors (the indexer false-positives noted in memory may show; rely on `xcodebuild`).

**Notes / decisions**
_(empty)_

---

### MM3-T02 — `MacHistoryView`
- **Status:** TODO
- **Depends on:** MM3-T01
- **Estimated effort:** M

**Goal**
Port `HistoryView.swift` to the Mac middle column. Lists completed items grouped by day, scrollable, with the same swipe-to-uncomplete action (right-click context menu on Mac).

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Today/MacHistoryView.swift` shows completed items reverse-chronologically.
- Right-click on a row: "Mark as not done", "Show in Today", "Delete".
- Reachable from Today's toolbar.
- Back button (or breadcrumb) returns to Today — use a `NavigationStack` in the Today section.

**How to build it**
1. Read existing `LEO/Features/Today/Views/HistoryView.swift` for behavior reference.
2. Build the Mac version using `List` with sections by date. Reuse `ItemRow` directly.
3. Wrap Today's content in `NavigationStack` so the toolbar's History button can push:
   ```swift
   NavigationStack {
       MacTodayView()
           .toolbar { ToolbarItem { NavigationLink("History") { MacHistoryView() } } }
   }
   ```
4. Right-click context menu via `.contextMenu`.

**Verification**
- [ ] History shows same items as iOS.
- [ ] Mark as not done re-opens an item; it reappears in Today.
- [ ] Navigation back to Today preserves Today's scroll position.

**Notes / decisions**
_(empty)_

---

### MM3-T03 — `MacInboxView`
- **Status:** TODO
- **Depends on:** MM3-T01
- **Estimated effort:** M

**Goal**
Port `InboxView.swift` to the Mac middle column with multi-select and bulk schedule.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Inbox/MacInboxView.swift` lists untimed open items.
- Sort modes: by date added (default), by importance, alphabetical.
- Selection mirrors `nav.selectedItemID` (single) or a `Set<UUID>` (multi via `⌘`-click).
- Top toolbar: sort menu, "Capture" field (placeholder → MM4), bulk-action menu (visible when multi-select active).
- Right-click on a row: "Schedule for…" (date picker popover), "Move to Today", "Complete", "Delete".
- Empty state: `LEOEmptyState("Inbox is empty", subtitle: "Capture a thought to get started")`.

**How to build it**
1. Replace `MacInboxPlaceholder` with `MacInboxView`.
2. Reuse `InboxView.swift`'s ViewModel logic — port to a new `MacInboxViewModel` (most code is shareable; consider extracting an `InboxViewModelCore` to share, but only if the diff is small).
3. Implement multi-select via `List(selection: $selectedIDs)` where `selectedIDs: Set<UUID>`.
4. Bulk action menu: `Menu("Actions") { Button("Schedule for Today"); Button("Schedule for Tomorrow"); Button("Complete"); Button("Delete") }`.
5. Wire "Schedule for…" → presents a `Popover` containing a `DatePicker` and a "Schedule" button.

**Verification**
- [ ] Inbox shows same items as iOS.
- [ ] Multi-select with `⌘`+click works.
- [ ] Bulk Schedule for Today: all selected items move to Today, visible in Today section.
- [ ] Sort menu changes order.

**Notes / decisions**
_(empty)_

---

### MM3-T04 — `MacItemDetailInspector`
- **Status:** TODO
- **Depends on:** MM3-T01 (so we can select items)
- **Estimated effort:** L

**Goal**
Replace `MacInspector` placeholder with the real editing surface. Every field iOS's `ItemDetailSheet` edits, the inspector must edit, but laid out as a tall vertical inspector rather than a sheet.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/ItemDetail/MacItemDetailInspector.swift` is the new content of the inspector column.
- Driven by an `ItemDetailViewModel` (existing) — port unchanged; if any view-coupling exists, factor to view layer.
- Fields editable: title, notes, importance, anchor (untimed / due-at / time-block / point / location), tags, recurrence (link to `MacRecurrenceBuilderSheet` from MM5), reminder offsets, alarm settings (for AlarmItem).
- Save: auto-saves on field commit (`onSubmit`, `onChange` with debounce 500ms), no explicit Save button.
- Delete button at the bottom with confirmation popover.
- The inspector header shows the item type badge (Task/Event/Reminder/Alarm/Habit) using `LEOChip`.
- When no item is selected, show the empty state from MM2-T07.

**How to build it**
1. Read existing `LEO/Features/ItemDetail/Views/ItemDetailSheet.swift` and `LEO/Features/ItemDetail/ViewModels/ItemDetailViewModel.swift`.
2. Create `MacItemDetailInspector.swift`. Bind to `nav.selectedItemID`; on change, ask `appEnv.itemRepository.fetch(.byID(id))` and seed the VM.
3. Re-use as many sub-views from iOS as possible. The fields are the same; only the chrome (sheet vs inspector) differs. Where iOS uses `Form { Section { ... } }`, Mac can use the same — `Form` works well in macOS in an inspector.
4. Anchor editing UI:
   - `Picker("Type", selection: $vm.anchorType)` with cases: Untimed, Due, Time block, Point, Location.
   - Conditional sub-controls based on type: `DatePicker` for due/point; two `DatePicker`s for time block; lat/lng + radius for location.
5. Recurrence row: shows `RecurrenceFormatter.string(for: rule)` and a "Edit recurrence" button that opens `MacRecurrenceBuilderSheet` (MM5-T03) as a sheet.
6. Reminder offsets: same UI as iOS (`Set<TimeInterval>` chips).
7. Auto-save: debounce changes with a 500ms `Task` cancellation; call `vm.save()`.
8. Delete: trailing-bottom `Button("Delete", role: .destructive)` with `.confirmationDialog`.

**Verification**
- [ ] Selecting an item in the middle column populates the inspector with the right fields.
- [ ] Edit title, hit `Tab` → change persists.
- [ ] Change anchor from untimed to due-at → item shows up in Today's date.
- [ ] Delete button → confirmation → item removed; selection cleared.
- [ ] Every field iOS edits is editable here (manual checklist below).

iOS field parity manual checklist:
- [ ] title
- [ ] notes
- [ ] importance (low/normal/high/urgent)
- [ ] anchor type + values (5 cases)
- [ ] tags
- [ ] recurrence rule
- [ ] reminder offsets (None, 5m, 15m, 30m, 1h, 1d, 1w)
- [ ] alarm sound + escalation (for `AlarmItem` only)
- [ ] location coordinate + radius + direction (for `.location` anchor)

**Notes / decisions**
_(empty)_

---

### MM3-T05 — `MacHabitsView`
- **Status:** TODO
- **Depends on:** MM3-T04
- **Estimated effort:** M

**Goal**
Port `HabitsView` to Mac with streak rings.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Habits/MacHabitsView.swift` lists today's `HabitInstanceItem`s with a streak indicator on each.
- Top of view: "Today" / "All habits" segmented control.
- Each row: habit name, streak count, ring (small `Circle().stroke`), action button (`Circle()` toggle for complete).
- Below the list: weekly heatmap (port from iOS).
- Selecting a row opens the inspector with the underlying `HabitInstanceItem` editable.

**How to build it**
1. Read existing `LEO/Features/Habits/Views/HabitsView.swift`.
2. Reuse `Domain/Habits/HabitMaterializer.swift` and `StreakEngine.swift` — both shared.
3. Build the view. Streak ring component: a small SwiftUI `Circle().trim(from:to:).stroke(...)`.
4. Weekly heatmap: a `LazyHGrid` of dot views.

**Verification**
- [ ] Habits shown match iOS for the same Apple ID.
- [ ] Toggling a habit updates the streak.
- [ ] Selecting a row opens the inspector.

**Notes / decisions**
_(empty)_

---

### MM3-T06 — Drag-and-drop reschedule
- **Status:** TODO
- **Depends on:** MM3-T04, MM3-T05
- **Estimated effort:** M

**Goal**
Drag an item from the middle column onto a date in the sidebar (or a time on the timeline) to reschedule it.

**What to build (acceptance criteria)**
- `ItemRow` in Mac context is wrapped in `.draggable(item.id.uuidString)`.
- Sidebar `Today` row accepts drop: drag a future-day item onto "Today" → re-anchors to today.
- Future: sidebar could show next 7 days as drop targets (out of scope for v1; defer to v1.1).
- Timeline mode: dropping an item on an hour row sets `.point(hour)` for that day.
- Visual feedback during drag: row outline highlighted.
- Drop completes by calling `appEnv.itemRepository.update(modifiedItem)`.

**How to build it**
1. Use `Transferable` protocol with `UUID` as the payload (`.draggable(item.id, preview: { … })`).
2. Sidebar drop:
   ```swift
   .dropDestination(for: String.self) { items, _ in
       Task { await handleDrop(ids: items.compactMap(UUID.init), to: .today) }
       return true
   }
   ```
3. Implement `handleDrop`: fetch each item, change anchor, save.
4. Timeline drop: `.dropDestination(for: String.self)` per hour row. The hour row needs a `Transferable` accept zone with the target hour.

**Verification**
- [ ] Drag a future item onto Today sidebar → it appears in Today list.
- [ ] Drag a list-mode Today item onto a timeline hour → its anchor becomes that hour.
- [ ] Drag rejects unsupported drops (e.g. dropping on Ask LEO sidebar row).

**Notes / decisions**
_(empty)_

---

### MM3-T07 — Multi-select + bulk actions
- **Status:** TODO
- **Depends on:** MM3-T06
- **Estimated effort:** M

**Goal**
Allow `⌘`+click and `⇧`+click to select multiple items in any list view; expose bulk actions in the toolbar and via right-click.

**What to build (acceptance criteria)**
- All `List` views (Today, Inbox, History, Habits) use `selection: $selectedIDs` of type `Set<UUID>`.
- A `MacBulkActionBar` appears at the top of the content pane when `selectedIDs.count > 1`.
- Actions: Complete (`⌘.`), Schedule for Today, Schedule for Tomorrow, Reschedule…, Delete (`⌘⌫`).
- The single-select case continues to drive `nav.selectedItemID` for the inspector (rule: when exactly 1 selected, mirror to `selectedItemID`).

**How to build it**
1. Hoist `@State private var selectedIDs: Set<UUID> = []` into the list-bearing views.
2. Mirror to `nav.selectedItemID`:
   ```swift
   .onChange(of: selectedIDs) { _, new in
       nav.selectedItemID = (new.count == 1) ? new.first : nil
   }
   ```
3. Build `MacBulkActionBar` showing a count "N selected" and the buttons.
4. Implement each bulk action by iterating `selectedIDs` and calling repository methods.
5. Hook keyboard shortcuts via `.keyboardShortcut(...)` on the buttons.

**Verification**
- [ ] `⌘`+click in Today selects 3 items; bulk bar appears.
- [ ] Bulk Complete completes all 3.
- [ ] Bulk Delete prompts confirmation, then removes all 3.
- [ ] Single-click clears multi-select and shows inspector for that item.

**Notes / decisions**
_(empty)_
