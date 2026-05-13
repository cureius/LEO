# MM6 — Platform Services (Notifications, Alarms, Location, EventKit, Menu-Bar Status)

**Goal:** Replace every iOS-only service stub from MM0 with a working macOS implementation. Notifications fire, alarms ring with escalating audio, location-anchored reminders trigger, EventKit reads/writes the user's calendars and reminders, the menu-bar status reflects "next event" and "active alarm" live.

**Exit criteria:**
- Every iOS notification behavior reproduces on Mac (time-based and location-based).
- Alarms behave per the documented Mac limitation (audio loop while LEO is running; menu-bar status when LEO is in the menu-bar; no system-level lock-screen alarm).
- EventKit syncs Mac calendars and reminders bidirectionally with the same UI surface as iOS.
- MenuBarExtra updates live as items move through time.

## Summary checklist
- [ ] MM6-T01 — Verify `NotificationManager` on macOS (no code changes expected)
- [ ] MM6-T02 — `AlarmEngineMac` real impl (NSSound + escalation + window foregrounding)
- [ ] MM6-T03 — `LocationReminderManagerMac` (CoreLocation on macOS 14+)
- [ ] MM6-T04 — `EventKitBridge` verification + calendar settings pane
- [ ] MM6-T05 — `MenuBarStatusController` live state updates
- [ ] MM6-T06 — `NotificationDelegate` Mac action routing
- [ ] MM6-T07 — Travel-time pre-reminders (MapKit verification on Mac)

---

### MM6-T01 — Verify `NotificationManager` on macOS
- **Status:** TODO
- **Depends on:** MM2-T07
- **Estimated effort:** S

**Goal**
Confirm the existing `LEO/Notifications/NotificationManager.swift` (which uses `UNUserNotificationCenter`) works unchanged on macOS.

**What to build (acceptance criteria)**
- `UNUserNotificationCenter` is the same API on macOS 14+ as iOS 18 — no code change required.
- Permission prompt fires on first launch (already wired in `LEOMacApp.task`).
- A scheduled notification 1 minute in the future fires; clicking it brings the app to focus.
- Notification banner uses the bundle icon — verify `AppIcon` set is correctly registered for macOS sizes.

**How to build it**
1. Audit `NotificationManager.swift` — confirm no `UIKit` import. (It should already be clean.)
2. Add a temporary debug button "Test notification (1 min)" in the Mac sidebar that calls:
   ```swift
   try? await appEnv.notificationManager.schedule(
       identifier: "mac-test", title: "Test", body: "Hello from Mac",
       date: .now.addingTimeInterval(60), userInfo: [:])
   ```
3. Quit Xcode. Wait 60s. Notification banner should appear. Click → LEO comes to foreground.
4. Audit `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — confirm macOS icon sizes exist (16, 32, 128, 256, 512, plus 2x variants). If missing, ask user to generate.

**Verification**
- [ ] Permission prompt appears on first Mac launch.
- [ ] Test notification fires at scheduled time.
- [ ] Click on banner activates LEO.
- [ ] No `UNError` codes in console.

**Notes / decisions**
_(empty)_

---

### MM6-T02 — `AlarmEngineMac` real implementation
- **Status:** TODO
- **Depends on:** MM6-T01
- **Estimated effort:** L

**Goal**
Replace `AlarmEngineMacStub` with a working `AlarmEngineMac` that schedules a `UNNotificationRequest`, plays a sound on fire, and brings LEO to the front when running.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Services/AlarmEngineMac.swift` conforms to `AlarmEngineProtocol`.
- `arm(_:)` schedules a `UNNotificationRequest` with the alarm sound and `interruptionLevel: .timeSensitive` (Mac supports it).
- When the notification fires:
  - If LEO is running: bring the main window to front (`NSApp.activate(ignoringOtherApps: true)`) and play looping sound via `AVAudioPlayer`.
  - If LEO is in the menu-bar only (regular Mac app — Dock icon present): same, plus animate the status item icon.
  - Escalating volume: ramp from 10% → 100% over 30s, same as iOS.
- `snooze(by:)` reschedules.
- `disarm(id:)` cancels notification and stops audio.
- Audio loop uses `AVAudioPlayer.numberOfLoops = -1` (works on macOS).
- Document the limitation: "Mac alarms work only while LEO is running. To get reliable alarms when LEO is closed, keep LEO in your menu bar or login items." — surface in onboarding (MM8) and Settings.

**How to build it**
1. Read iOS `AlarmEngine.swift` (under `PlatformIOS/Services/`).
2. Create `LEO/PlatformMac/Services/AlarmEngineMac.swift`:
   ```swift
   import Foundation
   import AVFoundation
   import AppKit
   import UserNotifications

   actor AlarmEngineMac: AlarmEngineProtocol {
       private let notificationManager: NotificationManager
       private var audioPlayer: AVAudioPlayer?
       private var escalationTask: Task<Void, Never>?
       private var armed: Set<UUID> = []

       init(notificationManager: NotificationManager) {
           self.notificationManager = notificationManager
       }

       func arm(_ alarm: AlarmItem) async {
           guard case .point(let fireDate) = alarm.anchor, fireDate > .now else { return }
           armed.insert(alarm.id)
           try? await notificationManager.schedule(
               identifier: "alarm.\(alarm.id).fire",
               title: "⏰ \(alarm.title)",
               body: alarm.notes ?? "Alarm",
               date: fireDate,
               categoryIdentifier: NotificationCategory.alarm,
               userInfo: ["itemID": alarm.id.uuidString, "isAlarm": true]
           )
       }

       func disarm(id: UUID) async {
           armed.remove(id)
           await notificationManager.cancel(identifiers: ["alarm.\(id).fire"])
           await stopAudio()
       }

       func snooze(alarm: AlarmItem, minutes: Int) async {
           await disarm(id: alarm.id)
           var s = alarm
           s.anchor = .point(.now.addingTimeInterval(TimeInterval(minutes * 60)))
           await arm(s)
       }

       func startAudioPlayback(sound: AlarmSound, escalates: Bool) async {
           guard sound != .hapticOnly,
                 let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3")
                       ?? Bundle.main.url(forResource: "alarm_default", withExtension: "mp3")
           else { return }
           audioPlayer = try? AVAudioPlayer(contentsOf: url)
           audioPlayer?.numberOfLoops = -1
           audioPlayer?.volume = escalates ? 0.1 : 1.0
           audioPlayer?.play()
           await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
           if escalates {
               escalationTask = Task { [weak self] in
                   for step in 1...30 {
                       try? await Task.sleep(for: .seconds(1))
                       guard let self else { return }
                       await self.setVolume(Float(step) / 30.0)
                   }
               }
           }
       }

       func stopAudio() async {
           escalationTask?.cancel(); escalationTask = nil
           audioPlayer?.stop(); audioPlayer = nil
       }

       private func setVolume(_ v: Float) { audioPlayer?.volume = min(1.0, v) }
   }
   ```
3. In `AppEnvironment`, replace `AlarmEngineMacStub()` with `AlarmEngineMac(notificationManager: nm)`.
4. Wire `NotificationDelegate` (MM6-T06) to call `appEnv.alarmEngine.startAudioPlayback(...)` when an alarm notification fires.
5. Add alarm sound assets to `Resources/Fitness` or a new `Resources/Sounds` folder if missing. Verify with `Bundle.main.url(forResource:)`.

**Verification**
- [ ] Arm an alarm for 1 min in future. Quit Xcode. Wait. Alarm notification fires; if app running, sound plays + window comes forward.
- [ ] Escalating volume audible.
- [ ] Snooze 9m reschedules; rings again 9 min later.
- [ ] Disarm cancels both notification and audio.

**Notes / decisions**
_(empty)_

---

### MM6-T03 — `LocationReminderManagerMac`
- **Status:** TODO
- **Depends on:** MM6-T02
- **Estimated effort:** M

**Goal**
Location-anchored reminders work on macOS 14+ using `CLLocationManager` region monitoring (which IS available on Mac — fewer regions, less precision than iOS but functional).

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Services/LocationReminderManagerMac.swift` conforms to `LocationReminderProviding`.
- API matches iOS: `requestWhenInUsePermission`, `requestAlwaysPermission`, `sync(items:)`, `stopAll()`.
- Uses `CLLocationManager.startMonitoring(for:)` — works on macOS 14+.
- Honors Mac limits: up to 20 monitored regions (same as iOS), minimum 100m radius.
- Permission prompt on first request: `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` (already in `Info-mac.plist`).

**How to build it**
1. Copy the iOS `LocationReminderManager.swift` (now in `PlatformIOS/Services/`) into `PlatformMac/Services/LocationReminderManagerMac.swift`. The code is mostly portable.
2. Verify macOS-specific API differences: `CLLocationManager.requestAlwaysAuthorization()` is available; the delegate methods are the same; `CLCircularRegion` is the same.
3. One known difference: `CLLocationManager.authorizationStatus()` was deprecated in favor of the instance property in iOS 14+/macOS 11+ — already using the instance property. Good.
4. Replace in `AppEnvironment` initialization (currently `LocationReminderManager` is allocated in `LEOApp.swift` because it must be main-thread). Move that allocation into `AppEnvironment` behind `#if`:
   ```swift
   // in AppEnvironment.init (still @MainActor-callable)
   #if os(iOS)
   self.locationReminders = LocationReminderManager(notificationManager: nm)
   #else
   self.locationReminders = LocationReminderManagerMac(notificationManager: nm)
   #endif
   ```
   Need to mark the protocol type the same way. Audit: the iOS code's `LocationReminderManager` is `final class` not actor and is `@MainActor`-friendly. Mac version mirrors.
5. Update `LEOApp.swift` (iOS) and `LEOMacApp.swift` (Mac) so neither directly constructs the manager — both go through `appEnv.locationReminders`.

**Verification**
- [ ] Set a location reminder (e.g. lat/lng for current location, 200m radius, on entry).
- [ ] Walk into/out of the region (or simulate via Xcode → Simulator → Location → Custom Location). Notification fires.
- [ ] Up to 20 active regions sync correctly.

**Notes / decisions**
_(empty)_

---

### MM6-T04 — `EventKitBridge` verification + calendar settings pane
- **Status:** TODO
- **Depends on:** MM6-T03
- **Estimated effort:** L

**Goal**
EventKit is fully supported on macOS. Verify the existing `EventKitBridge` and `CalendarSyncCoordinator` work; build the Mac `CalendarSettingsView` pane.

**What to build (acceptance criteria)**
- Mac app prompts for calendar + reminders access on first sync attempt (descriptions already in `Info-mac.plist`).
- Calendar subscription works (user picks which calendars to mirror into LEO).
- Reminder list subscription works.
- Bi-directional write-back works (creating an Event in LEO writes to EventKit; editing in EventKit reflects in LEO on next sync).
- Recurring reminders expand to `ReminderItem` occurrences as on iOS.
- A Mac `MacCalendarSettingsView` is built and mounted in `MacSettingsScene` (replaces placeholder).
- `CalendarSyncCoordinator.start()` is called from `LEOMacApp.task` (same as iOS).

**How to build it**
1. Read `LEO/Persistence/EventKit/EventKitBridge.swift`, `EventKitWriteBack.swift`, `CalendarSyncCoordinator.swift`. None import UIKit; should compile on Mac.
2. Audit any `EKEventStore.requestAccess(to: ...)` calls — on macOS 14, `requestFullAccessToEvents()` and `requestFullAccessToReminders()` (iOS 17+ APIs) are also available on Mac. No change expected; if the iOS code uses the new API, it works.
3. Add EventKit lifecycle to `LEOMacApp.task` (mirror `LEOApp.swift`):
   ```swift
   let savedCalIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_calendar_ids") ?? [])
   let savedRemIDs = Set(UserDefaults.standard.stringArray(forKey: "ek_subscribed_reminder_list_ids") ?? [])
   await env.eventKitBridge.subscribe(calendarIDs: savedCalIDs, reminderListIDs: savedRemIDs)
   await env.calendarSyncCoordinator.start()
   await env.calendarSyncCoordinator.syncOnForeground()
   ```
4. Listen to `NSApplication.didBecomeActiveNotification` on Mac (replaces iOS's `scenePhase`):
   ```swift
   .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
       Task { await env.calendarSyncCoordinator.syncOnForeground() }
   }
   ```
5. Build `MacCalendarSettingsView`:
   - List of available calendars (checkbox each).
   - List of available reminder lists (checkbox each).
   - "Refresh now" button.
   - Save persists to `UserDefaults` keys `ek_subscribed_calendar_ids` / `ek_subscribed_reminder_list_ids`.
6. Mount in `MacSettingsScene` Tab.calendar (replaces placeholder).
7. Background sync: iOS uses `BGAppRefreshTask`. Mac equivalent: `NSBackgroundActivityScheduler`. Add a registration in `LEOMacApp.task` that fires every 30 min when reasonable:
   ```swift
   let activity = NSBackgroundActivityScheduler(identifier: "com.theblueman.leo.refresh")
   activity.interval = 30 * 60
   activity.repeats = true
   activity.qualityOfService = .utility
   activity.schedule { completion in
       Task { @MainActor in
           await env.calendarSyncCoordinator.syncForBackgroundTask()
           if let items = try? await env.itemRepository.fetch() {
               await env.notificationManager.sync(for: items)
           }
           completion(.finished)
       }
   }
   ```

**Verification**
- [ ] First sync prompts for calendar + reminders access.
- [ ] Selecting 2 calendars in `MacCalendarSettingsView` and "Refresh now" pulls events into LEO.
- [ ] Adding an event in macOS Calendar.app appears in LEO within 30 min (or immediately on app foreground).
- [ ] Editing an event in LEO writes back to Calendar.app.
- [ ] Recurring reminders show one row per occurrence in LEO (per `expandRecurringReminder` logic).

**Notes / decisions**
_(empty)_

---

### MM6-T05 — `MenuBarStatusController` live state
- **Status:** TODO
- **Depends on:** MM6-T04, MM4-T02
- **Estimated effort:** M

**Goal**
Replace any iOS-Live-Activity behavior on Mac with the menu-bar item updating in real time: "Next: standup in 12 min", and a red dot when an alarm is active.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Services/MenuBarStatusController.swift` is an `@Observable` class.
- Computes "next event/alarm" from `appEnv.itemRepository.fetch(.all)` filtered to future items, picks the soonest with anchor.
- Refreshes every 60 seconds (`Timer.publish`).
- Refreshes immediately on `.leoDataDidChange`.
- Provides `nextItem: (any Item)?` and `activeAlarm: AlarmItem?` to the menu-bar popover.
- Used by `MenuBarCaptureView` to render the "Next: …" row.

**How to build it**
1. Create the controller:
   ```swift
   import SwiftUI

   @Observable
   final class MenuBarStatusController: MenuBarStatusProviding {
       var nextItem: (any Item)?
       var activeAlarm: AlarmItem?
       private weak var appEnv: AppEnvironment?

       func bind(_ env: AppEnvironment) {
           appEnv = env
           Task { await refresh() }
           NotificationCenter.default.addObserver(forName: .leoDataDidChange, object: nil, queue: .main) { [weak self] _ in
               Task { await self?.refresh() }
           }
           Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
               Task { await self?.refresh() }
           }
       }

       func updateNextItem(_ item: (any Item)?) async { nextItem = item }
       func showActiveAlarm(_ alarm: AlarmItem?) async { activeAlarm = alarm }

       private func refresh() async {
           guard let env = appEnv,
                 let items = try? await env.itemRepository.fetch() else { return }
           let now = Date.now
           let upcoming = items
               .compactMap { item -> (any Item, Date)? in
                   guard let d = item.anchor.sortDate, d > now, !item.isCompleted else { return nil }
                   return (item, d)
               }
               .sorted { $0.1 < $1.1 }
               .first?.0
           await MainActor.run { nextItem = upcoming }
       }
   }
   ```
2. In `AppEnvironment`, on Mac, replace the stub with this controller and call `controller.bind(self)` after init.
3. `MenuBarCaptureView` reads `menuBarController.nextItem` and renders:
   ```swift
   if let next = ctl.nextItem {
       VStack(alignment: .leading) {
           Text("Next: \(next.title)").font(.headline)
           if let d = next.anchor.sortDate {
               Text(d, style: .relative).font(.caption).foregroundStyle(.secondary)
           }
       }
   }
   ```
4. The menu-bar icon swap (active alarm dot): driven by `menuBarController.activeAlarm`.

**Verification**
- [ ] Status bar shows "Next: <upcoming item>" within 60s of creation.
- [ ] Editing the item changes the status within 60s.
- [ ] Alarm active → red dot on icon.

**Notes / decisions**
_(empty)_

---

### MM6-T06 — `NotificationDelegate` Mac action routing
- **Status:** TODO
- **Depends on:** MM6-T02
- **Estimated effort:** M

**Goal**
Tapping a notification on Mac (banner click) routes through the same `NotificationDelegate` as iOS so it surfaces the same `ReminderActionSheet` (Done / Snooze) when appropriate.

**What to build (acceptance criteria)**
- `LEO/Notifications/NotificationDelegate.swift` works on Mac unchanged (it uses `UNUserNotificationCenter` only).
- Mac `LEOMacApp.task` sets `UNUserNotificationCenter.current().delegate = delegate` (mirroring iOS `AppEnvironment` initializer; we already do this in iOS code and it should run on Mac too).
- Tapping a reminder banner shows a Mac equivalent of `ReminderActionSheet` (the iOS view uses no UIKit; should port directly).
- Action buttons in the banner ("Done", "Snooze 15m") work via `UNNotificationAction` (iOS code already registers these).

**How to build it**
1. Audit `NotificationDelegate.swift` — confirm it compiles on Mac. If any `UIApplication` reference exists, gate with `#if os(iOS)`.
2. Audit `ReminderActionSheet.swift` — confirm no UIKit imports. If it has any iOS-only modifiers (`.sheet` with `.presentationDetents`), gate with `#if os(iOS)` and provide a simpler Mac variant (full sheet).
3. Verify the delegate is being set on Mac. In `AppEnvironment.init`, the existing line `UNUserNotificationCenter.current().delegate = delegate` runs on both. Good.
4. Test: schedule a reminder for 1 min, wait, click banner → action sheet should appear in LEO.

**Verification**
- [ ] Notification banner clickable.
- [ ] Action sheet shows.
- [ ] Done → item completed.
- [ ] Snooze 15m → item rescheduled.

**Notes / decisions**
_(empty)_

---

### MM6-T07 — Travel-time pre-reminders
- **Status:** TODO
- **Depends on:** MM6-T04
- **Estimated effort:** M

**Goal**
Verify or port `TravelTimePreReminder.swift` to Mac. On iOS, this uses `MKDirections` to estimate travel time and schedules a pre-reminder. macOS has MapKit too.

**What to build (acceptance criteria)**
- `LEO/Notifications/TravelTimePreReminder.swift` either works unchanged on macOS (preferred) or has a Mac variant.
- For an event with a `location` field, it schedules a notification N minutes before, where N is the MKDirections estimate + buffer.
- Mac variant lives in `PlatformIOS/Services/` only if the iOS version is truly iOS-only; otherwise it should be in `Notifications/` and shared.
- Audit: if `TravelTimePreReminder.swift` imports `MapKit` only (no UIKit), keep it shared.

**How to build it**
1. Read `LEO/PlatformIOS/Services/TravelTimePreReminder.swift` (moved here in MM0-T03 — re-check).
2. If purely MapKit + UserNotifications, move back to `LEO/Notifications/TravelTimePreReminder.swift` and update `project.yml` excludes accordingly.
3. If it uses `CLLocationManager` heavily, create a Mac variant alongside.
4. Wire it into `AppEnvironment` for Mac (it's already wired for iOS).

**Verification**
- [ ] Event at a coordinate 30 min away triggers a "Leave in 5 min" notification ~35 min before start.
- [ ] Works on Mac in a clean session.

**Notes / decisions**
_(empty)_
