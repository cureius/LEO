# MM9 — Widgets, Extensions, Polish, Ship

**Goal:** Widget extension supports both iOS and macOS. App Intents and Shortcuts work on Mac. Dev tools (debug menu, DB browser) ported. Crash reporting via MetricKit on Mac. Ready to submit to TestFlight for macOS.

**Exit criteria:**
- macOS desktop widgets render Today, Next Up, and Habit Ring.
- Shortcuts app on Mac shows LEO actions (capture, complete, search).
- Debug menu reachable via `⌘⇧⌥D`.
- TestFlight build uploaded for macOS.
- Mac app passes the same dogfood as iOS: full week with no escape hatches.

## Summary checklist
- [ ] MM9-T01 — `LEOWidgets` target supports macOS
- [ ] MM9-T02 — Mac desktop widgets render (Today, Next Up, Habit Ring)
- [ ] MM9-T03 — App Intents on macOS (Shortcuts.app integration)
- [ ] MM9-T04 — Debug menu + database browser on Mac
- [ ] MM9-T05 — MetricKit + crash reporting on Mac
- [ ] MM9-T06 — TestFlight submission for macOS

---

### MM9-T01 — `LEOWidgets` supports macOS
- **Status:** TODO
- **Depends on:** MM8-T06
- **Estimated effort:** M

**Goal**
The existing widget extension target adds macOS as a supported platform; the existing widget code (which reads `WidgetSnapshot`) compiles for both.

**What to build (acceptance criteria)**
- In `project.yml`, the `LEOWidgets` target's `platform:` becomes a list `[iOS, macOS]`, or two targets share sources via xcodegen template — choose the simplest path.
- Widget supports families: `accessoryCircular` (iOS-only is OK to gate), `systemSmall`, `systemMedium`, `systemLarge`. Mac supports the system families.
- `WidgetSnapshot` (existing) writes to the shared app group (`group.com.theblueman.leo`) — works on both platforms since the entitlement is wired.

**How to build it**
1. Inspect the current `LEOWidgets` target in `project.yml`. Add or duplicate the target for macOS.
2. Most likely path: a single target with `supportedDestinations: [iOS, macOS]` (xcodegen syntax: `supportedDestinations:` is an Xcode 14+ build setting):
   ```yaml
   LEOWidgets:
     type: app-extension
     supportedDestinations: [iOS, macOS]
     deploymentTarget:
       iOS: "18.0"
       macOS: "14.0"
     sources:
       - path: LEOWidgets
     settings:
       base:
         PRODUCT_BUNDLE_IDENTIFIER: com.theblueman.leo.widgets
         INFOPLIST_FILE: LEOWidgets/Info.plist
         CODE_SIGN_ENTITLEMENTS: LEOWidgets/LEOWidgets.entitlements
   ```
3. The entitlements file `LEOWidgets.entitlements` must include the same `com.apple.security.application-groups` value.
4. Gate widget families: `if #available(iOS 17, macOS 14, *) { ... }` for any platform-specific family.

**Verification**
- [ ] iOS widgets still render.
- [ ] Mac widget extension builds without errors.

**Notes / decisions**
_(empty)_

---

### MM9-T02 — Mac desktop widgets render
- **Status:** TODO
- **Depends on:** MM9-T01
- **Estimated effort:** M

**Goal**
Three widgets visible on Mac desktop after install: Today, Next Up, Habit Ring.

**What to build (acceptance criteria)**
- After running Mac app once, opening Mac's widget picker (right-click desktop → Edit Widgets) shows LEO widgets.
- Today widget shows next 3 items.
- Next Up widget shows the single next item (medium size).
- Habit Ring widget shows today's habit completion ratio.
- Widget tap opens LEO (iOS-style behavior — Mac widgets support tap-to-open via Universal Control / Continuity).

**How to build it**
1. Audit existing widget views. Confirm they only use SwiftUI + WidgetKit (no UIKit-only modifiers).
2. Test the widget refresh: edit `WidgetSnapshotStore.write` — already shared between app and widget.
3. Provide both Mac-native preview snapshots (use `Widget` preview macros) so the picker displays nicely.

**Verification**
- [ ] All three widgets appear in Mac widget picker.
- [ ] After adding to desktop, widgets render with real data.
- [ ] Widgets refresh when LEO updates items.

**Notes / decisions**
_(empty)_

---

### MM9-T03 — App Intents on macOS
- **Status:** TODO
- **Depends on:** MM9-T01
- **Estimated effort:** M

**Goal**
The existing App Intents (`LEOIntents.swift`, `LEOItemEntity.swift`) appear in Mac Shortcuts.app and are runnable.

**What to build (acceptance criteria)**
- Mac Shortcuts.app shows LEO under "Apps" with the existing intents (Quick Add, Complete Item, Search).
- An intent can be run from Shortcuts and creates/modifies items.
- An intent can be run via Spotlight (`⌘Space → "Add task to LEO" + return`).

**How to build it**
1. App Intents framework is cross-platform; the existing code should compile and register on Mac unchanged.
2. Verify in Xcode → Run on Mac → wait 10s → open Shortcuts.app → search for "LEO".
3. Test one intent end-to-end.

**Verification**
- [ ] LEO appears in Shortcuts.app on Mac.
- [ ] Quick Add intent works from Spotlight.

**Notes / decisions**
_(empty)_

---

### MM9-T04 — Debug menu + database browser
- **Status:** TODO
- **Depends on:** MM8-T06
- **Estimated effort:** S

**Goal**
Port `DebugMenu.swift` and `DatabaseBrowserView.swift` to Mac, reachable via `⌘⇧⌥D` (replacing iOS shake-to-reveal).

**What to build (acceptance criteria)**
- `⌘⇧⌥D` keyboard shortcut opens debug menu (only in Debug builds).
- Debug menu: Seed data, Reset store, Open DB browser, Toggle telemetry, Clear notifications, Force sync.
- DB browser shows tables and rows (read-only).

**How to build it**
1. Read existing `Utilities/Dev/DebugMenu.swift` and `DatabaseBrowserView.swift`.
2. Port — they're already SwiftUI-only.
3. Wire `⌘⇧⌥D` via `.keyboardShortcut` in a hidden menu under `Window` (Debug builds only via `#if DEBUG`).
4. Replace iOS's `onShake` mounting (already gated to iOS in `RootView.swift`).

**Verification**
- [ ] `⌘⇧⌥D` opens debug menu.
- [ ] Seed adds items; visible immediately.
- [ ] DB browser shows tables.

**Notes / decisions**
_(empty)_

---

### MM9-T05 — MetricKit + crash reporting
- **Status:** TODO
- **Depends on:** MM9-T04
- **Estimated effort:** S

**Goal**
MetricKit reports work on Mac (`MXMetricManager` is cross-platform on macOS 12+).

**What to build (acceptance criteria)**
- `LEO/Utilities/Telemetry/MetricsSubscriber.swift` works on Mac without code change.
- Crash reports collected via MetricKit are processed by the existing subscriber.

**How to build it**
1. Audit the file — confirm no UIKit imports.
2. Register on `LEOMacApp.task`:
   ```swift
   await MainActor.run {
       MXMetricManager.shared.add(env.metricsSubscriber)
   }
   ```
3. Trigger a controlled crash in a Debug build (e.g. `fatalError("test")`) and verify the metric is captured on next launch.

**Verification**
- [ ] Metric subscriber registered on launch.
- [ ] Controlled crash test produces a payload.

**Notes / decisions**
_(empty)_

---

### MM9-T06 — TestFlight submission for macOS
- **Status:** TODO (BLOCKED on user action)
- **Depends on:** MM9-T05
- **Estimated effort:** M

**Goal**
Archive the Mac app and submit to TestFlight via Xcode Organizer.

**What to build (acceptance criteria)**
- Archive succeeds: `xcodebuild -scheme LEO-Mac -configuration Release archive`.
- Xcode Organizer can upload to App Store Connect.
- TestFlight build appears on the user's macOS TestFlight after processing (~30 min).
- User installs and dogfoods for 1 week before App Store submission.

**How to build it**
1. **STOP — user action required.** Run `xcodebuild archive`, then Xcode Organizer → Distribute App → App Store Connect.
2. Provide a release notes template:
   ```
   First macOS beta of LEO.

   What works:
   • Sync with iOS via iCloud
   • Today, Inbox, Habits, Ask LEO
   • Quick capture: ⌘N inside the app, ⌃⌥Space from anywhere
   • Menu bar capture
   • All EventKit features
   • Gym Companion

   Known limits:
   • Alarms ring only while LEO is running or in the menu bar
   • Global hotkey requires Accessibility permission
   ```
3. After upload, ensure metadata for the Mac listing exists in App Store Connect (icon, screenshots — separate from iOS).

**Verification**
- [ ] Archive succeeds without warnings.
- [ ] Upload accepted by App Store Connect.
- [ ] TestFlight install on a clean Mac runs.

**Notes / decisions**
_(empty)_
