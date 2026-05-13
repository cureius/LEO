# MM2 — Mac Shell

**Goal:** A real Mac-native shell — `NavigationSplitView`, populated sidebar, menu bar commands, `Settings` scene scaffold, window-state restoration, theme parity. No feature views yet (those come in MM3+).

**Exit criteria:**
- Sidebar navigates between sections (Today, Inbox, Habits, Ask LEO, Calendar, Settings).
- Menu bar shows File / Edit / View / Item / Window / Help commands populated with the right primary actions (even if some are no-ops pointing to MM3 features).
- Settings opens via `⌘,` in its own window with tabs (placeholders).
- Sidebar width and selection persist across launches.
- Theme tokens render correctly on Mac (compare side-by-side with iOS).

## Summary checklist
- [ ] MM2-T01 — Real sidebar with sections and counts
- [ ] MM2-T02 — Content-pane router (switch on `SidebarSection`)
- [ ] MM2-T03 — Menu bar `.commands { }` block populated
- [ ] MM2-T04 — `Settings` scene scaffold with tabbed structure
- [ ] MM2-T05 — Theme verification: colors, typography, spacing on Mac
- [ ] MM2-T06 — Window-state restoration (sidebar width, selection, inspector visibility)
- [ ] MM2-T07 — `MacInspector` scaffold (placeholder for item detail)

---

### MM2-T01 — Real sidebar with sections and counts
- **Status:** TODO
- **Depends on:** MM0-T08
- **Estimated effort:** M

**Goal**
Replace the placeholder `List(SidebarSection.allCases, …)` with a real grouped sidebar showing section labels, icons, and live item counts.

**What to build (acceptance criteria)**
- `MacSidebar.swift` is a standalone view file in `LEO/App/Mac/`.
- Sidebar uses `List` with `selection: $nav.selection`.
- Sections grouped: "Planning" (Today, Inbox, Habits), "Tools" (Ask LEO, Calendar), and the bottom-pinned "Settings".
- Each row shows: icon, label, trailing count badge for sections with counts (Inbox = untimed count, Today = today's open count, Habits = today's habit-instance count).
- Counts update reactively when items change (listen to `.leoDataDidChange` notification or use `@Query`).
- Sidebar minimum width 200, ideal 240.

**How to build it**
1. Create `LEO/App/Mac/MacSidebar.swift`:
   ```swift
   import SwiftUI

   struct MacSidebar: View {
       @Environment(MacNavigationModel.self) private var nav
       @Environment(AppEnvironment.self) private var appEnv
       @State private var counts: SidebarCounts = .empty

       var body: some View {
           @Bindable var navBinding = nav
           List(selection: $navBinding.selection) {
               Section("Planning") {
                   row(.today, icon: "sun.max.fill", badge: counts.todayOpen)
                   row(.inbox, icon: "tray.fill", badge: counts.inbox)
                   row(.habits, icon: "repeat.circle.fill", badge: counts.habitsToday)
               }
               Section("Tools") {
                   row(.ask, icon: "sparkles")
                   row(.calendar, icon: "calendar")
               }
           }
           .listStyle(.sidebar)
           .navigationTitle("LEO")
           .frame(minWidth: 200, idealWidth: 240)
           .task { await refreshCounts() }
           .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
               Task { await refreshCounts() }
           }
       }

       @ViewBuilder
       private func row(_ section: SidebarSection, icon: String, badge: Int? = nil) -> some View {
           Label(section.rawValue.capitalized, systemImage: icon)
               .tag(section)
               .badge(badge ?? 0)
       }

       private func refreshCounts() async {
           guard let items = try? await appEnv.itemRepository.fetch() else { return }
           let today = Calendar.current.startOfDay(for: .now)
           let endOfToday = today.addingTimeInterval(86_400)
           let todayOpen = items.filter { item in
               guard let d = item.anchor.sortDate else { return false }
               return d >= today && d < endOfToday && !item.isCompleted
           }.count
           let inbox = items.filter { $0.anchor.isUntimed && !$0.isCompleted }.count
           let habits = items.filter { $0 is HabitInstanceItem && !$0.isCompleted }.count
           counts = SidebarCounts(todayOpen: todayOpen, inbox: inbox, habitsToday: habits)
       }
   }

   private struct SidebarCounts {
       let todayOpen: Int
       let inbox: Int
       let habitsToday: Int
       static let empty = SidebarCounts(todayOpen: 0, inbox: 0, habitsToday: 0)
   }
   ```
2. In `MacShellView`, replace the placeholder `List` with `MacSidebar()`.
3. `Settings` will be reached via `⌘,` from the menu bar in MM2-T03 — no sidebar entry.

**Verification**
- [ ] Sidebar shows three sections with the right rows.
- [ ] Counts populate within a second of launch.
- [ ] Adding a task on iOS (synced via MM1) updates the count on Mac.
- [ ] Click each row → `nav.selection` updates; verified by adding a `.onChange(of: nav.selection)` print.

**Notes / decisions**
_(empty)_

---

### MM2-T02 — Content-pane router
- **Status:** TODO
- **Depends on:** MM2-T01
- **Estimated effort:** M

**Goal**
Switch the middle column on `nav.selection`. Each case returns a placeholder feature view that future milestones replace with the real thing.

**What to build (acceptance criteria)**
- `MacShellView`'s `content` closure dispatches via a `MacContentPane` view to one of:
  - `.today` → `MacTodayPlaceholder()` (real impl: MM3-T01)
  - `.inbox` → `MacInboxPlaceholder()` (real impl: MM3-T03)
  - `.habits` → `MacHabitsPlaceholder()` (real impl: MM3-T05)
  - `.ask` → `MacAssistantPlaceholder()` (real impl: MM5-T01)
  - `.calendar` → `MacCalendarPlaceholder()` (this is the EventKit-bridged calendar view; real impl: MM6-T04 OR cut)
- Each placeholder uses the shared design system: `LEOCard`, `LEOEmptyState`, etc.
- Placeholder shows section name + "Coming in MM<N>".

**How to build it**
1. Create `LEO/PlatformMac/Features/Common/MacContentPane.swift`:
   ```swift
   import SwiftUI

   struct MacContentPane: View {
       @Environment(MacNavigationModel.self) private var nav
       var body: some View {
           Group {
               switch nav.selection {
               case .today: MacTodayPlaceholder()
               case .inbox: MacInboxPlaceholder()
               case .habits: MacHabitsPlaceholder()
               case .ask:   MacAssistantPlaceholder()
               case .calendar: MacCalendarPlaceholder()
               case .settings: EmptyView() // handled by Settings scene
               }
           }
           .frame(minWidth: 400, idealWidth: 600)
       }
   }
   ```
2. Add a `MacPlaceholderView` shared component in the same file:
   ```swift
   struct MacPlaceholderView: View {
       let title: String
       let milestone: String
       var body: some View {
           LEOEmptyState(systemImage: "hourglass", title: title, subtitle: "Coming in \(milestone)")
       }
   }
   struct MacTodayPlaceholder: View { var body: some View { MacPlaceholderView(title: "Today", milestone: "MM3") } }
   struct MacInboxPlaceholder: View { var body: some View { MacPlaceholderView(title: "Inbox", milestone: "MM3") } }
   struct MacHabitsPlaceholder: View { var body: some View { MacPlaceholderView(title: "Habits", milestone: "MM3") } }
   struct MacAssistantPlaceholder: View { var body: some View { MacPlaceholderView(title: "Ask LEO", milestone: "MM5") } }
   struct MacCalendarPlaceholder: View { var body: some View { MacPlaceholderView(title: "Calendar", milestone: "MM6") } }
   ```
3. Update `MacShellView`:
   ```swift
   NavigationSplitView {
       MacSidebar()
   } content: {
       MacContentPane()
   } detail: {
       MacInspector()  // built in MM2-T07
   }
   ```

**Verification**
- [ ] Selecting each sidebar row swaps the content pane to the right placeholder.
- [ ] `LEOEmptyState` renders identically to iOS visually.

**Notes / decisions**
_(empty)_

---

### MM2-T03 — Menu bar commands populated
- **Status:** TODO
- **Depends on:** MM2-T02
- **Estimated effort:** M

**Goal**
Build the menu bar so power users can drive LEO from the keyboard. Even though many actions point to MM3+ functionality, the menus must exist now so the shape is locked in.

**What to build (acceptance criteria)**
- `LEO/App/Mac/MacCommands.swift` is a `Commands` struct.
- File menu:
  - "New Item…" (`⌘N`) — opens the quick-add (real impl: MM4-T01)
  - "New Task" (`⌥⌘N`)
  - "New Event"
  - "New Reminder"
  - "New Alarm"
  - separator
  - "Import from Calendar…" (`⇧⌘I`) — placeholder
- Edit menu: standard items + "Find" (`⌘F`) routed to MM4-T05 command palette.
- View menu:
  - "Today" (`⌘1`), "Inbox" (`⌘2`), "Habits" (`⌘3`), "Ask LEO" (`⌘4`), "Calendar" (`⌘5`)
  - separator
  - "Toggle Sidebar" (`⌃⌘S`) — built-in
  - "Toggle Inspector" (`⌃⌥⌘I`)
  - "List view" / "Timeline view" for Today (`⌘L` / `⌘T`)
- Item menu (only enabled when an item is selected):
  - "Complete" (`⌘.`)
  - "Reschedule…" (`⇧⌘R`)
  - "Snooze 15 min" (`⌃1`)
  - "Snooze 1 hour" (`⌃2`)
  - "Snooze until tomorrow" (`⌃3`)
  - separator
  - "Delete" (`⌘⌫`)
- Window menu: standard.
- Help menu: "LEO Help" → opens a web link in MM9; for now, no-op.
- `LEOMacApp.body.commands { MacCommands() }`.

**How to build it**
1. Create `LEO/App/Mac/MacCommands.swift`:
   ```swift
   import SwiftUI

   struct MacCommands: Commands {
       @FocusedBinding(\.macNavigation) private var nav: MacNavigationModel?
       @FocusedBinding(\.selectedItemID) private var selectedItemID: UUID?

       var body: some Commands {
           CommandGroup(replacing: .newItem) {
               Button("New Item…") { /* posts a notification consumed by MM4 quick-add */ NotificationCenter.default.post(name: .leoOpenQuickAdd, object: nil) }
                   .keyboardShortcut("n")
               Menu("New") {
                   Button("Task")     { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "task") }
                   Button("Event")    { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "event") }
                   Button("Reminder") { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "reminder") }
                   Button("Alarm")    { NotificationCenter.default.post(name: .leoOpenQuickAdd, object: "alarm") }
               }
           }
           CommandGroup(after: .pasteboard) {
               Button("Find") { NotificationCenter.default.post(name: .leoOpenCommandPalette, object: nil) }
                   .keyboardShortcut("f")
           }
           CommandMenu("Item") {
               Button("Complete") { NotificationCenter.default.post(name: .leoCompleteSelectedItem, object: selectedItemID) }
                   .keyboardShortcut(".", modifiers: .command)
                   .disabled(selectedItemID == nil)
               Button("Reschedule…") { NotificationCenter.default.post(name: .leoRescheduleSelectedItem, object: selectedItemID) }
                   .keyboardShortcut("r", modifiers: [.command, .shift])
                   .disabled(selectedItemID == nil)
               Divider()
               Button("Snooze 15 min") { NotificationCenter.default.post(name: .leoSnoozeSelected, object: ["id": selectedItemID, "seconds": 900]) }
                   .keyboardShortcut("1", modifiers: .control)
                   .disabled(selectedItemID == nil)
               Button("Snooze 1 hour") { NotificationCenter.default.post(name: .leoSnoozeSelected, object: ["id": selectedItemID, "seconds": 3600]) }
                   .keyboardShortcut("2", modifiers: .control)
                   .disabled(selectedItemID == nil)
               Button("Snooze until tomorrow") { NotificationCenter.default.post(name: .leoSnoozeSelected, object: ["id": selectedItemID, "seconds": 86_400]) }
                   .keyboardShortcut("3", modifiers: .control)
                   .disabled(selectedItemID == nil)
               Divider()
               Button("Delete") { NotificationCenter.default.post(name: .leoDeleteSelectedItem, object: selectedItemID) }
                   .keyboardShortcut(.delete, modifiers: .command)
                   .disabled(selectedItemID == nil)
           }
           CommandGroup(after: .sidebar) {
               Button("Toggle Inspector") { NotificationCenter.default.post(name: .leoToggleInspector, object: nil) }
                   .keyboardShortcut("i", modifiers: [.control, .option, .command])
               Divider()
               Button("Today")   { sectionShortcut(.today) }.keyboardShortcut("1", modifiers: .command)
               Button("Inbox")   { sectionShortcut(.inbox) }.keyboardShortcut("2", modifiers: .command)
               Button("Habits")  { sectionShortcut(.habits) }.keyboardShortcut("3", modifiers: .command)
               Button("Ask LEO") { sectionShortcut(.ask) }.keyboardShortcut("4", modifiers: .command)
               Button("Calendar"){ sectionShortcut(.calendar) }.keyboardShortcut("5", modifiers: .command)
           }
           CommandGroup(replacing: .help) {
               Button("LEO Help") { /* MM9 */ }
           }
       }

       private func sectionShortcut(_ section: SidebarSection) {
           // selection is read by MacRootView via FocusedValue or env override; simpler:
           NotificationCenter.default.post(name: .leoSelectSidebarSection, object: section)
       }
   }
   ```
2. Define `Notification.Name` extensions in `LEO/App/Mac/MacNotifications.swift`:
   ```swift
   import Foundation
   extension Notification.Name {
       static let leoOpenQuickAdd        = Notification.Name("leoOpenQuickAdd")
       static let leoOpenCommandPalette  = Notification.Name("leoOpenCommandPalette")
       static let leoSelectSidebarSection = Notification.Name("leoSelectSidebarSection")
       static let leoToggleInspector     = Notification.Name("leoToggleInspector")
       static let leoCompleteSelectedItem = Notification.Name("leoCompleteSelectedItem")
       static let leoRescheduleSelectedItem = Notification.Name("leoRescheduleSelectedItem")
       static let leoSnoozeSelected      = Notification.Name("leoSnoozeSelected")
       static let leoDeleteSelectedItem  = Notification.Name("leoDeleteSelectedItem")
   }
   ```
3. Define focused-value keys for cleaner state plumbing (alternative to NotificationCenter):
   ```swift
   private struct MacNavigationKey: FocusedValueKey { typealias Value = MacNavigationModel }
   private struct SelectedItemIDKey: FocusedValueKey { typealias Value = UUID }
   extension FocusedValues {
       var macNavigation: MacNavigationModel? { get { self[MacNavigationKey.self] } set { self[MacNavigationKey.self] = newValue } }
       var selectedItemID: UUID? { get { self[SelectedItemIDKey.self] } set { self[SelectedItemIDKey.self] = newValue } }
   }
   ```
4. In `MacShellView`, attach focused values:
   ```swift
   .focusedSceneValue(\.macNavigation, nav)
   .focusedSceneValue(\.selectedItemID, nav.selectedItemID)
   ```
5. Wire up sidebar listener in `MacRootView` (or `MacShellView`):
   ```swift
   .onReceive(NotificationCenter.default.publisher(for: .leoSelectSidebarSection)) { note in
       if let section = note.object as? SidebarSection { nav.selection = section }
   }
   .onReceive(NotificationCenter.default.publisher(for: .leoToggleInspector)) { _ in
       nav.inspectorVisible.toggle()
   }
   ```
6. Add `commands { MacCommands() }` to `LEOMacApp.body`.

**Verification**
- [ ] Menu bar shows File / Edit / View / Item / Window / Help with the items above.
- [ ] `⌘1`–`⌘5` switch sidebar selection.
- [ ] `⌘N` posts the quick-add notification (verified via `print` in a temporary listener).
- [ ] Item-menu items are disabled when nothing is selected.

**Notes / decisions**
_(empty)_

---

### MM2-T04 — `Settings` scene scaffold
- **Status:** TODO
- **Depends on:** MM2-T03
- **Estimated effort:** M

**Goal**
A native macOS Settings window opened by `⌘,` with tabbed panes that mirror iOS Settings sections. Panes are placeholders to be filled in MM8.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Settings/MacSettingsScene.swift` contains a `TabView` with tabs: General, Calendar, Fitness, Sync, AI, Feedback.
- Each tab has a `Label("…", systemImage: …)` and a placeholder body.
- Window minimum size: 600 × 480.
- `LEOMacApp.body` includes:
  ```swift
  Settings { MacSettingsScene() }
  ```
- Pressing `⌘,` opens the settings window.

**How to build it**
1. Create `LEO/PlatformMac/Features/Settings/MacSettingsScene.swift`:
   ```swift
   import SwiftUI

   struct MacSettingsScene: View {
       enum Tab: String, Hashable { case general, calendar, fitness, sync, ai, feedback }
       @State private var selection: Tab = .general

       var body: some View {
           TabView(selection: $selection) {
               Text("General — MM8")
                   .tabItem { Label("General", systemImage: "gearshape") }
                   .tag(Tab.general)
               Text("Calendar — MM8")
                   .tabItem { Label("Calendar", systemImage: "calendar") }
                   .tag(Tab.calendar)
               Text("Fitness — MM8")
                   .tabItem { Label("Fitness", systemImage: "figure.run") }
                   .tag(Tab.fitness)
               Text("Sync — MM8")
                   .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                   .tag(Tab.sync)
               Text("AI — MM8")
                   .tabItem { Label("AI", systemImage: "sparkles") }
                   .tag(Tab.ai)
               Text("Feedback — MM8")
                   .tabItem { Label("Feedback", systemImage: "envelope") }
                   .tag(Tab.feedback)
           }
           .frame(minWidth: 600, minHeight: 480)
           .padding()
       }
   }
   ```
2. Update `LEOMacApp.body` to include `Settings { MacSettingsScene() }`.

**Verification**
- [ ] `⌘,` opens the Settings window with 6 tabs.
- [ ] Window remembers its size across launches (system-provided behavior).

**Notes / decisions**
_(empty)_

---

### MM2-T05 — Theme verification
- **Status:** TODO
- **Depends on:** MM2-T04
- **Estimated effort:** M

**Goal**
Confirm `Theme.Color.*` tokens, typography (`Theme.Font`), spacing (`Theme.Spacing`), and component visuals (`LEOCard`, `LEOChip`, `LEOButton`) render correctly on macOS in both light and dark mode.

**What to build (acceptance criteria)**
- A `MacDesignSystemPreviewScene` window (under `View` menu → "Design System") shows the same grid as iOS's `DesignSystemPreview.swift`.
- Visual side-by-side: launch iPhone simulator + Mac, screenshot the design system view from each, confirm color and type token parity.
- Fix any colorset that renders wrong on Mac (likely `Resources/Theme.xcassets/Theme/*.colorset` already supports both `Universal` appearances; verify).
- Dark mode and light mode both verified.

**How to build it**
1. Read `LEO/DesignSystem/DesignSystemPreview.swift`. Confirm it compiles on Mac (it should — no UIKit).
2. Wrap it in a Mac-friendly scene: add a `Window` group in `LEOMacApp.body`:
   ```swift
   Window("Design System", id: "leo-design-system") {
       DesignSystemPreview()
       .frame(minWidth: 900, minHeight: 700)
   }
   ```
3. Add a menu bar entry under `View` (or `Help`) to open it: `OpenWindowAction`. In `MacCommands`:
   ```swift
   CommandGroup(after: .windowList) {
       Button("Design System") { /* uses @Environment(\.openWindow) — see SwiftUI docs */ }
   }
   ```
4. Open on both platforms. Compare side-by-side.
5. Audit each colorset under `Resources/Theme.xcassets/Theme/` — confirm each has `Any Appearance` + `Dark Appearance` color definitions. If any are missing dark variants on macOS specifically, edit the asset catalog.
6. Audit typography: `Theme.Font.title`, `.headline`, `.body`, `.caption` — should render with system fonts that exist on both. (They do — `SF Pro` is universal.)
7. Spot-check `LEOButton.primary` and `.secondary` on Mac — they may need `controlSize(.large)` for Mac visual weight.

**Verification**
- [ ] Design System window opens via menu.
- [ ] Side-by-side screenshot test in light + dark passes (subjective — record screenshots under `docs/mac-design-parity/`).
- [ ] No asset-catalog warnings about missing variants.

**Notes / decisions**
_(empty)_

---

### MM2-T06 — Window-state restoration
- **Status:** TODO
- **Depends on:** MM2-T05
- **Estimated effort:** S

**Goal**
The sidebar's collapsed/expanded state, sidebar width, selected section, and inspector visibility persist across app launches.

**What to build (acceptance criteria)**
- `nav.selection` persists via `SceneStorage("leo.sidebar.section")`.
- `nav.inspectorVisible` persists via `AppStorage("leo.inspector.visible")` (default `true`).
- Window frame (size + position) persists via SwiftUI's default `WindowGroup` behavior with `defaultSize(width:height:)`.
- Default first-launch window size: 1200 × 800.

**How to build it**
1. In `MacShellView`, replace the navigation model state with `@SceneStorage`-backed mirrors:
   ```swift
   @SceneStorage("leo.sidebar.section") private var sectionRaw: String = SidebarSection.today.rawValue
   @AppStorage("leo.inspector.visible") private var inspectorVisible: Bool = true
   ```
2. Mirror `nav.selection` to/from `sectionRaw` on change.
3. Add `.frame(minWidth: 900, minHeight: 600)` and `.defaultSize(width: 1200, height: 800)` to the WindowGroup.
4. Verify by launching, picking a section, closing the app, relaunching — last section is selected.

**Verification**
- [ ] Selection survives quit+relaunch.
- [ ] Inspector show/hide survives.
- [ ] Window size and position survive.

**Notes / decisions**
_(empty)_

---

### MM2-T07 — `MacInspector` scaffold
- **Status:** TODO
- **Depends on:** MM2-T06
- **Estimated effort:** S

**Goal**
The right column shows an item's editable detail when one is selected, or a placeholder when nothing is selected. The full editing surface lands in MM3-T04.

**What to build (acceptance criteria)**
- `LEO/App/Mac/MacInspector.swift` exists.
- Reads `nav.selectedItemID`. If nil, shows `LEOEmptyState("Select an item")`. Otherwise shows a placeholder for now ("Item \(id) — MM3").
- Width: minimum 280, ideal 320.
- Respects `nav.inspectorVisible` — `MacShellView` conditionally renders it.

**How to build it**
1. Create `LEO/App/Mac/MacInspector.swift`:
   ```swift
   import SwiftUI

   struct MacInspector: View {
       @Environment(MacNavigationModel.self) private var nav

       var body: some View {
           Group {
               if let id = nav.selectedItemID {
                   VStack(alignment: .leading) {
                       Text("Item \(id.uuidString.prefix(8))")
                           .font(.headline)
                       Text("Detail editor — MM3-T04")
                           .foregroundStyle(.secondary)
                       Spacer()
                   }
                   .padding()
               } else {
                   LEOEmptyState(systemImage: "sidebar.right", title: "No item selected", subtitle: "Select an item to view its details")
               }
           }
           .frame(minWidth: 280, idealWidth: 320)
       }
   }
   ```
2. Update `MacShellView`'s `detail:` closure to conditionally show `MacInspector()` based on `nav.inspectorVisible`. SwiftUI's `NavigationSplitView` handles three columns natively; for hiding the third column, set `columnVisibility`:
   ```swift
   @State private var columnVisibility: NavigationSplitViewVisibility = .all
   NavigationSplitView(columnVisibility: $columnVisibility) { … }
   .onChange(of: nav.inspectorVisible) { _, visible in
       columnVisibility = visible ? .all : .doubleColumn
   }
   ```

**Verification**
- [ ] Empty inspector shows placeholder.
- [ ] `⌃⌥⌘I` toggles inspector visibility.
- [ ] Inspector reappears with last visibility state on relaunch.

**Notes / decisions**
_(empty)_
