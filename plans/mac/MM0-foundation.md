# MM0 — Foundation

**Goal:** A macOS scheme that builds, launches an empty window, signs in to iCloud, and uses the same `AppEnvironment` as iOS. No data shown yet — just the wiring.

**Exit criteria:**
- `xcodebuild -scheme LEO-Mac build` succeeds.
- `xcodebuild -scheme LEO build` still succeeds (no iOS regression).
- Mac app launches, shows an empty `NavigationSplitView`, no crash.
- `AppEnvironment` initializes on Mac. `PersistenceController` opens the SwiftData store. `ClaudeClient` is reachable.
- All previously-iOS-only services are now behind protocols, with iOS impls intact.

## Summary checklist
- [x] MM0-T01 — Add `LEO-Mac` target to `project.yml`
- [x] MM0-T02 — Create macOS entitlements + Info.plist
- [x] MM0-T03 — Scaffold `PlatformIOS/` and `PlatformMac/` folders; move iOS-only files
- [x] MM0-T04 — Extract service protocols (`AlarmEngineProtocol`, `LocationReminderProviding`, `MenuBarStatusProviding`)
- [x] MM0-T05 — Make `AppEnvironment` compile on both platforms
- [x] MM0-T06 — Add `LEOMacApp.swift` with empty `MacShellView`
- [x] MM0-T07 — Verify dual-platform builds and iCloud sign-in
- [ ] MM0-T08 — Update `MAC_IMPLEMENTATION_PLAN.md` tracker and commit

---

### MM0-T01 — Add `LEO-Mac` target to `project.yml`
- **Status:** DONE
- **Depends on:** —
- **Estimated effort:** M

**Goal**
Define the macOS target in xcodegen and regenerate the Xcode project so both schemes exist side-by-side.

**What to build (acceptance criteria)**
- `project.yml` declares a second target `LEO-Mac` (type `application`, platform `macOS`, deploymentTarget `14.0`).
- Both targets share `path: LEO` for sources but exclude each other's platform-specific subtrees.
- `xcodegen generate` produces a project with two schemes: `LEO` (existing) and `LEO-Mac` (new).
- `xcodebuild -list` shows both schemes.
- Building either scheme does not pick up the other's `@main` entry.

**How to build it**
1. Open `project.yml`. After the existing `LEO` target block, add:
   ```yaml
     LEO-Mac:
       type: application
       platform: macOS
       deploymentTarget: "14.0"
       sources:
         - path: LEO
           excludes:
             - "**/.gitkeep"
             - "PlatformIOS/**"
             - "App/LEOApp.swift"
             - "App/AppTabView.swift"
             - "App/RootView.swift"
             - "Alarms/**"                  # legacy location — moved to PlatformIOS in MM0-T03
             - "Notifications/LocationReminderManager.swift"   # legacy iOS-only
             - "Notifications/TravelTimePreReminder.swift"     # legacy iOS-only
             - "Integrations/LiveActivities/**"
             - "Integrations/Focus/**"
             - "Resources/LEO.entitlements"
             - "Resources/LEO-debug.entitlements"
             - "Resources/Info.plist"
       resources:
         - LEO/Resources
       settings:
         base:
           PRODUCT_BUNDLE_IDENTIFIER: com.theblueman.leo
           PRODUCT_NAME: LEO
           INFOPLIST_FILE: LEO/Resources/Info-mac.plist
           ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
           MARKETING_VERSION: "1.0.0"
           CURRENT_PROJECT_VERSION: "1"
           DEVELOPMENT_TEAM: ZT397U24CA
           CODE_SIGN_STYLE: Automatic
           SWIFT_STRICT_CONCURRENCY: targeted
           ENABLE_HARDENED_RUNTIME: YES
         configs:
           Debug:
             DEBUG_INFORMATION_FORMAT: dwarf
             SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG
             CODE_SIGN_ENTITLEMENTS: LEO/Resources/LEO-mac-debug.entitlements
           Release:
             DEBUG_INFORMATION_FORMAT: dwarf-with-dsym
             SWIFT_ACTIVE_COMPILATION_CONDITIONS: ""
             CODE_SIGN_ENTITLEMENTS: LEO/Resources/LEO-mac.entitlements
       info:
         path: LEO/Resources/Info-mac.plist
         properties:
           CFBundleName: LEO
           CFBundleDisplayName: LEO
           LSApplicationCategoryType: public.app-category.productivity
           NSHumanReadableCopyright: "© 2026 The Blueman"
   ```
2. Add the iOS target's existing `excludes:` block — append:
   ```yaml
             - "PlatformMac/**"
             - "App/Mac/**"
             - "Resources/LEO-mac.entitlements"
             - "Resources/LEO-mac-debug.entitlements"
             - "Resources/Info-mac.plist"
   ```
3. Add a `schemes:` entry for `LEO-Mac`:
   ```yaml
   schemes:
     LEO-Mac:
       build:
         targets:
           LEO-Mac: all
       run:
         config: Debug
       test:
         config: Debug
         targets: [LEOMacTests]
       profile:
         config: Release
       analyze:
         config: Debug
       archive:
         config: Release
   ```
4. Create empty placeholder directories so xcodegen doesn't error: `PlatformIOS/`, `PlatformMac/`, `App/Mac/`. Each gets a `.gitkeep`.
5. Create placeholder files so the Mac target has at least one source: `App/Mac/LEOMacApp.swift` with:
   ```swift
   import SwiftUI
   @main struct LEOMacApp: App {
       var body: some Scene { WindowGroup { Text("LEO Mac — wired") } }
   }
   ```
6. Create placeholder `Resources/Info-mac.plist`, `Resources/LEO-mac.entitlements`, `Resources/LEO-mac-debug.entitlements` (empty plists for now; populated in MM0-T02).
7. Run `xcodegen generate`. Open the project. Both schemes should appear.
8. Build each scheme.

**Verification**
- [ ] `xcodegen generate` exits 0.
- [ ] `xcodebuild -list` lists both `LEO` and `LEO-Mac` schemes.
- [ ] `xcodebuild -scheme LEO -destination 'platform=iOS Simulator,id=FB3865AE-D134-4831-8A18-5CC7394D16C5' build` succeeds.
- [ ] `xcodebuild -scheme LEO-Mac -destination 'platform=macOS,arch=arm64' build` succeeds.
- [ ] No duplicate-`@main` error from either scheme (the excludes block the other entry point).

**Notes / decisions**
_(empty)_

---

### MM0-T02 — Create macOS entitlements + Info.plist
- **Status:** TODO
- **Depends on:** MM0-T01
- **Estimated effort:** S

**Goal**
Author the Mac-specific entitlements file and Info.plist so the app can use iCloud + EventKit + CoreLocation + Network on macOS.

**What to build (acceptance criteria)**
- `LEO/Resources/Info-mac.plist` has correct keys for: app name, bundle identifier, sandbox usage descriptions for EventKit/Reminders/Location/Speech/AppleEvents, LSUIElement off (we want a Dock icon).
- `LEO/Resources/LEO-mac.entitlements` and `LEO-mac-debug.entitlements` contain the keys in `conventions.md` (sandbox, network client, CloudKit container, EventKit, CoreLocation, app group).
- The CloudKit container identifier is **exactly** `iCloud.com.theblueman.leo` — the same one iOS uses (verify by reading `LEO/Resources/LEO.entitlements`).
- App group identifier matches iOS for widget sharing: `group.com.theblueman.leo`.

**How to build it**
1. Read `LEO/Resources/LEO.entitlements` to confirm the iOS CloudKit container identifier and app group identifier.
2. Create `LEO/Resources/LEO-mac.entitlements`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>com.apple.security.app-sandbox</key>
     <true/>
     <key>com.apple.security.network.client</key>
     <true/>
     <key>com.apple.security.personal-information.calendars</key>
     <true/>
     <key>com.apple.security.personal-information.reminders</key>
     <true/>
     <key>com.apple.security.personal-information.location</key>
     <true/>
     <key>com.apple.security.files.user-selected.read-write</key>
     <true/>
     <key>com.apple.developer.icloud-container-identifiers</key>
     <array>
       <string>iCloud.com.theblueman.leo</string>
     </array>
     <key>com.apple.developer.icloud-services</key>
     <array>
       <string>CloudKit</string>
     </array>
     <key>com.apple.developer.ubiquity-kvstore-identifier</key>
     <string>$(TeamIdentifierPrefix)com.theblueman.leo</string>
     <key>com.apple.security.application-groups</key>
     <array>
       <string>group.com.theblueman.leo</string>
     </array>
   </dict>
   </plist>
   ```
3. Create `LEO/Resources/LEO-mac-debug.entitlements` — identical to release for now.
4. Create `LEO/Resources/Info-mac.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>CFBundleDevelopmentRegion</key><string>en</string>
     <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
     <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
     <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
     <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
     <key>CFBundleDisplayName</key><string>LEO</string>
     <key>CFBundlePackageType</key><string>APPL</string>
     <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
     <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
     <key>LSMinimumSystemVersion</key><string>14.0</string>
     <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
     <key>NSCalendarsUsageDescription</key><string>LEO reads and writes calendar events you choose to share, so your schedule stays in one place.</string>
     <key>NSCalendarsFullAccessUsageDescription</key><string>LEO reads and writes calendar events you choose to share, so your schedule stays in one place.</string>
     <key>NSRemindersUsageDescription</key><string>LEO reads and writes reminders so your tasks live in one place.</string>
     <key>NSRemindersFullAccessUsageDescription</key><string>LEO reads and writes reminders so your tasks live in one place.</string>
     <key>NSLocationWhenInUseUsageDescription</key><string>LEO triggers location-based reminders when you arrive at or leave saved places.</string>
     <key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>LEO triggers location-based reminders even when LEO isn't open.</string>
     <key>NSMicrophoneUsageDescription</key><string>LEO uses the microphone for voice capture of tasks and notes.</string>
     <key>NSSpeechRecognitionUsageDescription</key><string>LEO transcribes your voice captures into tasks and notes.</string>
     <key>NSAppleEventsUsageDescription</key><string>LEO uses Apple Events to integrate with the system menu bar.</string>
     <key>NSHumanReadableCopyright</key><string>© 2026 The Blueman</string>
     <key>LSUIElement</key><false/>
   </dict>
   </plist>
   ```
5. Run `xcodegen generate`. Build the Mac scheme.

**Verification**
- [ ] `xcodebuild -scheme LEO-Mac build` succeeds.
- [ ] Launching the Mac app from Xcode prompts no entitlement warnings in the console.
- [ ] Right-click the built `.app` → Show Package Contents → Contents/Info.plist contains the expected keys.

**Notes / decisions**
_(empty)_

---

### MM0-T03 — Scaffold `PlatformIOS/` and `PlatformMac/`; move iOS-only files
- **Status:** TODO
- **Depends on:** MM0-T01
- **Estimated effort:** M

**Goal**
Move iOS-only services into `PlatformIOS/` so the Mac target can exclude them cleanly, and create the empty `PlatformMac/` skeleton.

**What to build (acceptance criteria)**
- `LEO/PlatformIOS/Services/` contains: `AlarmEngine.swift`, `LocationReminderManager.swift`, `TravelTimePreReminder.swift`.
- `LEO/PlatformIOS/Integrations/LiveActivities/` contains the existing live-activity files (`AlarmActivity.swift`, `NextEventActivity.swift`).
- `LEO/PlatformIOS/Integrations/Focus/` contains `LEOFocusFilter.swift`.
- `LEO/PlatformMac/{Services, Capture, Commands, Features}/` exist as empty directories with `.gitkeep`.
- All existing imports still resolve. iOS scheme still builds.
- `project.yml` excludes blocks updated to reference the new locations (remove old `Alarms/`, `Notifications/LocationReminderManager.swift` etc. since they've moved).

**How to build it**
1. `git mv LEO/Alarms/AlarmEngine.swift LEO/PlatformIOS/Services/AlarmEngine.swift`. Update any other files in `Alarms/` if any exist (`ls LEO/Alarms/` before moving).
2. `git mv LEO/Notifications/LocationReminderManager.swift LEO/PlatformIOS/Services/LocationReminderManager.swift`.
3. `git mv LEO/Notifications/TravelTimePreReminder.swift LEO/PlatformIOS/Services/TravelTimePreReminder.swift`.
4. `git mv LEO/Integrations/LiveActivities LEO/PlatformIOS/Integrations/LiveActivities`.
5. `git mv LEO/Integrations/Focus LEO/PlatformIOS/Integrations/Focus`.
6. Update `project.yml`:
   - iOS target excludes: remove old paths since the directories no longer exist there.
   - Mac target excludes: replace old paths with the new `PlatformIOS/**` glob (covers everything moved).
7. Create empty directories with `.gitkeep`:
   - `LEO/PlatformMac/Services/.gitkeep`
   - `LEO/PlatformMac/Capture/.gitkeep`
   - `LEO/PlatformMac/Commands/.gitkeep`
   - `LEO/PlatformMac/Features/.gitkeep`
8. `xcodegen generate`. Build iOS scheme — must still succeed without changes to any `import` statements (Swift imports are by module, not file path).
9. Verify by grepping: `git grep "import" LEO/PlatformIOS/Services/AlarmEngine.swift` — no broken imports.

**Verification**
- [ ] `xcodebuild -scheme LEO build` succeeds with the new file layout.
- [ ] `git status` shows only moves (no edits to file contents).
- [ ] `LEO/Alarms/` and `LEO/Integrations/LiveActivities/` no longer exist.
- [ ] iOS app launches and alarms still arm in a smoke test (run `Seeder.seedAlarms()` from `DebugMenu`, observe one fires).

**Notes / decisions**
_(empty)_

---

### MM0-T04 — Extract service protocols
- **Status:** TODO
- **Depends on:** MM0-T03
- **Estimated effort:** M

**Goal**
Pull the iOS-only services' public surface into protocols in shared code so `AppEnvironment` and view models depend on the protocol, not the concrete iOS class.

**What to build (acceptance criteria)**
- New file `LEO/Notifications/AlarmEngineProtocol.swift` declares `AlarmEngineProtocol` (actor protocol).
- New file `LEO/Notifications/LocationReminderProviding.swift` declares `LocationReminderProviding`.
- New file `LEO/Notifications/MenuBarStatusProviding.swift` declares `MenuBarStatusProviding` (so iOS can stub it with no-op, Mac will implement).
- `AlarmEngine` (in `PlatformIOS/`) conforms to `AlarmEngineProtocol`.
- `LocationReminderManager` (in `PlatformIOS/`) conforms to `LocationReminderProviding`.
- A no-op `MenuBarStatusProvidingIOS` stub satisfies the protocol on iOS.
- All call sites that previously used `appEnv.alarmEngine` etc. continue to compile (because `AppEnvironment` exposes `any AlarmEngineProtocol`).
- iOS still builds and behavior is unchanged.

**How to build it**
1. Create `LEO/Notifications/AlarmEngineProtocol.swift`:
   ```swift
   import Foundation

   public protocol AlarmEngineProtocol: Actor {
       func arm(_ alarm: AlarmItem) async
       func disarm(id: UUID) async
       func snooze(alarm: AlarmItem, minutes: Int) async
       func startAudioPlayback(sound: AlarmSound, escalates: Bool) async
       func stopAudio() async
   }
   ```
   Match the methods currently public on `AlarmEngine` (read `PlatformIOS/Services/AlarmEngine.swift` first).
2. Edit `PlatformIOS/Services/AlarmEngine.swift`: change `actor AlarmEngine {` to `actor AlarmEngine: AlarmEngineProtocol {`.
3. Create `LEO/Notifications/LocationReminderProviding.swift`:
   ```swift
   import Foundation

   @MainActor
   public protocol LocationReminderProviding: AnyObject {
       func requestWhenInUsePermission()
       func requestAlwaysPermission()
       func sync(items: [any Item])
       func stopAll()
   }
   ```
4. Edit `PlatformIOS/Services/LocationReminderManager.swift`: add `: LocationReminderProviding` to the class declaration.
5. Create `LEO/Notifications/MenuBarStatusProviding.swift`:
   ```swift
   import Foundation

   @MainActor
   public protocol MenuBarStatusProviding: AnyObject {
       /// Update the menu-bar status with the user's next event/alarm.
       /// On iOS this is a no-op; Mac implementation drives MenuBarExtra contents.
       func updateNextItem(_ item: (any Item)?) async
       func showActiveAlarm(_ alarm: AlarmItem?) async
   }
   ```
6. Add `LEO/PlatformIOS/Services/MenuBarStatusProvidingIOS.swift` (no-op stub):
   ```swift
   import Foundation

   @MainActor
   final class MenuBarStatusProvidingIOS: MenuBarStatusProviding {
       func updateNextItem(_ item: (any Item)?) async {}
       func showActiveAlarm(_ alarm: AlarmItem?) async {}
   }
   ```
7. Run `xcodebuild -scheme LEO build`. Fix any compile errors.

**Verification**
- [ ] Both `git grep "appEnv.alarmEngine"` and `git grep "appEnv.locationReminderManager"` still resolve.
- [ ] `xcodebuild -scheme LEO build` succeeds.
- [ ] No call site needs editing — the protocol surface is broad enough to cover existing usage.

**Notes / decisions**
_(empty)_

---

### MM0-T05 — Make `AppEnvironment` compile on both platforms
- **Status:** TODO
- **Depends on:** MM0-T04
- **Estimated effort:** M

**Goal**
Update `AppEnvironment` to use `#if os` factories for iOS-only services, so the same `AppEnvironment.swift` compiles for both schemes. Mac services are still stubs/no-ops at this stage.

**What to build (acceptance criteria)**
- `LEO/App/AppEnvironment.swift` references protocol types for `alarmEngine`, `locationReminderManager` (when added), `menuBarStatus`, `travelTimePreReminder`, `alarmActivityManager`.
- Concrete instantiation uses `#if os(iOS)` / `#if os(macOS)` blocks at each site.
- On macOS, the Mac stub services are no-ops in MM0 (they're filled in during MM6).
- `LocationReminderManager` reference moves from `LEOApp.swift` to inside `AppEnvironment` so the Mac entry point doesn't need to know about it.
- No imports of `BackgroundTasks` or `UIKit` survive in `AppEnvironment.swift`.

**How to build it**
1. Read current `AppEnvironment.swift` and `LEOApp.swift` to identify every iOS-only service touched.
2. In `AppEnvironment.swift`, change the typed declarations:
   ```swift
   let alarmEngine: any AlarmEngineProtocol
   let menuBarStatus: any MenuBarStatusProviding
   // locationReminderManager added later — currently still lives in LEOApp; we leave it for now since it's main-thread-bound; in MM6 we'll move it cleanly.
   ```
3. In the initializer, swap concrete `AlarmEngine(…)` for:
   ```swift
   #if os(iOS)
   self.alarmEngine = AlarmEngine(notificationManager: nm)
   self.menuBarStatus = MenuBarStatusProvidingIOS()
   #else
   self.alarmEngine = AlarmEngineMacStub()
   self.menuBarStatus = MenuBarStatusProvidingMacStub()
   #endif
   ```
4. Add `LEO/PlatformMac/Services/AlarmEngineMacStub.swift`:
   ```swift
   import Foundation
   actor AlarmEngineMacStub: AlarmEngineProtocol {
       func arm(_ alarm: AlarmItem) async {}
       func disarm(id: UUID) async {}
       func snooze(alarm: AlarmItem, minutes: Int) async {}
       func startAudioPlayback(sound: AlarmSound, escalates: Bool) async {}
       func stopAudio() async {}
   }
   ```
5. Add `LEO/PlatformMac/Services/MenuBarStatusProvidingMacStub.swift` — same pattern, no-ops.
6. The existing `AlarmActivityManager` is iOS-only (uses `ActivityKit`). Wrap its init and any references in `#if os(iOS)` blocks in `AppEnvironment`, OR (preferred) make `AlarmActivityManager` a protocol with iOS+Mac variants in the same MM0 pass. Choose: simple `#if`; we'll do the proper protocol in MM6-T05.
7. Build both schemes. Fix any compile errors.

**Verification**
- [ ] `xcodebuild -scheme LEO build` succeeds.
- [ ] `xcodebuild -scheme LEO-Mac build` succeeds.
- [ ] iOS smoke test: alarms still arm and fire.

**Notes / decisions**
_(empty)_

---

### MM0-T06 — Add `LEOMacApp.swift` with empty `MacShellView`
- **Status:** TODO
- **Depends on:** MM0-T05
- **Estimated effort:** M

**Goal**
Replace the placeholder Mac entry with a real `@main` that constructs `AppEnvironment`, owns a `Settings` scene, and shows a stubbed three-column `NavigationSplitView` so we can prove the wiring works.

**What to build (acceptance criteria)**
- `LEO/App/Mac/LEOMacApp.swift` is `@main` for the Mac target.
- `LEO/App/Mac/MacRootView.swift` mirrors `RootView.swift` but routes to `MacShellView` instead of `AppTabView`. Onboarding gating uses the same `UserDefaults.hasCompletedOnboarding`.
- `LEO/App/Mac/MacShellView.swift` is an empty `NavigationSplitView(sidebar: …, content: …, detail: …)` with placeholder text in each column.
- `LEO/App/Mac/MacNavigationModel.swift` declares `@Observable final class MacNavigationModel` with a `selection: SidebarSection` enum (cases: today, inbox, habits, ask, calendar, settings).
- The Mac app launches, shows three columns ("Today" highlighted in sidebar, empty content area, empty inspector).
- A `Settings` scene exists (use SwiftUI's `Settings { Text("Settings — MM8") }` for now).
- The app's icon shows in the Dock when launched (so `LSUIElement` is not set).

**How to build it**
1. Replace placeholder `LEO/App/Mac/LEOMacApp.swift`:
   ```swift
   import SwiftUI
   import SwiftData
   import OSLog

   private let logger = Logger(subsystem: "com.theblueman.leo.mac", category: "app")

   @main
   struct LEOMacApp: App {
       @State private var appEnvironment: AppEnvironment? = nil

       var body: some Scene {
           WindowGroup("LEO") {
               Group {
                   if let env = appEnvironment {
                       MacRootView()
                           .environment(env)
                           .modelContainer(env.persistenceController.container)
                   } else {
                       loadingView
                   }
               }
               .task {
                   guard appEnvironment == nil else { return }
                   logger.info("Mac AppEnvironment init start")
                   let env = await Task.detached(priority: .userInitiated) {
                       AppEnvironment()
                   }.value
                   appEnvironment = env
                   logger.info("Mac AppEnvironment init complete")
                   _ = await env.notificationManager.requestAuthorization()
                   if let items = try? await env.itemRepository.fetch() {
                       await env.notificationManager.sync(for: items)
                   }
               }
           }
           .windowStyle(.titleBar)
           .windowToolbarStyle(.unified)
           .commands {
               // populated in MM2-T03
           }

           Settings {
               Text("Settings — implemented in MM8")
                   .frame(minWidth: 400, minHeight: 300)
           }
       }

       @ViewBuilder
       private var loadingView: some View {
           ZStack {
               Color.black.ignoresSafeArea()
               VStack(spacing: 16) {
                   Text("LEO")
                       .font(.system(size: 48, weight: .bold))
                       .foregroundStyle(.white)
                   ProgressView().tint(.white)
               }
           }
           .frame(minWidth: 800, minHeight: 600)
       }
   }
   ```
2. Create `LEO/App/Mac/MacRootView.swift`:
   ```swift
   import SwiftUI

   struct MacRootView: View {
       @Environment(AppEnvironment.self) private var appEnv
       @State private var nav = MacNavigationModel()
       @State private var onboardingDone = UserDefaults.standard.hasCompletedOnboarding

       var body: some View {
           if onboardingDone {
               MacShellView()
                   .environment(nav)
           } else {
               // MM8 will replace with proper onboarding
               VStack {
                   Text("Onboarding placeholder (MM8)")
                   Button("Skip") {
                       UserDefaults.standard.hasCompletedOnboarding = true
                       onboardingDone = true
                   }
               }
           }
       }
   }
   ```
3. Create `LEO/App/Mac/MacNavigationModel.swift`:
   ```swift
   import Foundation

   enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
       case today, inbox, habits, ask, calendar, settings
       var id: String { rawValue }
   }

   @Observable
   final class MacNavigationModel {
       var selection: SidebarSection = .today
       var selectedItemID: UUID? = nil
       var inspectorVisible: Bool = true
   }
   ```
4. Create `LEO/App/Mac/MacShellView.swift`:
   ```swift
   import SwiftUI

   struct MacShellView: View {
       @Environment(MacNavigationModel.self) private var nav

       var body: some View {
           @Bindable var navBinding = nav
           NavigationSplitView {
               List(SidebarSection.allCases, selection: $navBinding.selection) { section in
                   NavigationLink(value: section) {
                       Label(section.rawValue.capitalized, systemImage: icon(for: section))
                   }
               }
               .navigationTitle("LEO")
               .frame(minWidth: 200)
           } content: {
               Text("Content for \(nav.selection.rawValue) — MM3")
                   .frame(minWidth: 400)
           } detail: {
               Text("Inspector — MM3")
                   .frame(minWidth: 280)
           }
       }

       private func icon(for s: SidebarSection) -> String {
           switch s {
           case .today: return "sun.max.fill"
           case .inbox: return "tray"
           case .habits: return "repeat.circle.fill"
           case .ask: return "sparkles"
           case .calendar: return "calendar"
           case .settings: return "gearshape"
           }
       }
   }
   ```
5. Run `xcodegen generate`. Build and run the Mac scheme.

**Verification**
- [ ] Mac app launches. Dock icon appears.
- [ ] Three columns visible: sidebar, content area (with placeholder text), inspector.
- [ ] Clicking each sidebar item updates the content placeholder text.
- [ ] `⌘,` opens an empty Settings window.
- [ ] No crashes. Console shows "Mac AppEnvironment init complete".
- [ ] `xcodebuild -scheme LEO build` still passes (no iOS regression).

**Notes / decisions**
_(empty)_

---

### MM0-T07 — Verify dual-platform builds and iCloud sign-in
- **Status:** TODO
- **Depends on:** MM0-T06
- **Estimated effort:** S

**Goal**
Smoke test the wiring end-to-end and confirm iCloud authentication on the Mac.

**What to build (acceptance criteria)**
- iOS app launches on the simulator and behaves identically to before the port started.
- Mac app launches, AppEnvironment initializes, `PersistenceController` opens the store, the store URL is in `~/Library/Application Support/`.
- Mac is signed into iCloud (System Settings → Apple ID → iCloud enabled). The CloudKit container `iCloud.com.theblueman.leo` is resolvable (no `CKErrorNotAuthenticated` in the console).
- A debug button "Insert test task" in the Mac sidebar (temporary, removed in MM3) creates a `TaskItem` via the repository and the SwiftData store persists it across relaunch.

**How to build it**
1. Add a temporary debug button in `MacShellView` sidebar (above the list):
   ```swift
   Button("Insert test task") {
       Task {
           let task = TaskItem(id: UUID(), title: "Mac smoke task", notes: nil,
                               createdAt: .now, updatedAt: .now,
                               importance: .normal, anchor: .untimed, completion: .open,
                               tags: [])
           try? await appEnv.itemRepository.add(task)
       }
   }
   ```
2. Inject `appEnv` into the view (`@Environment(AppEnvironment.self) private var appEnv`).
3. Launch. Click the button. Quit. Relaunch.
4. Use the SwiftData browser (`Utilities/Dev/DatabaseBrowserView.swift` — port to Mac in MM9; for now, query the store via lldb or LLDB-free by re-running `appEnv.itemRepository.fetch()`).
5. Confirm by adding `print(try await appEnv.itemRepository.fetch().count)` to the `.task` block in `LEOMacApp` and observing the count survives a relaunch.
6. Remove the temporary button before MM3 (track in MM3-T01 dependency).

**Verification**
- [ ] Mac app inserts a TaskItem and prints count > 0 on next launch.
- [ ] Xcode → Signing & Capabilities for `LEO-Mac` target shows iCloud capability with the right container.
- [ ] Console shows no CloudKit errors (only `cloudKitDatabase: .none` is set, so no sync yet — that's MM1).
- [ ] iOS app fully functional on simulator.

**Notes / decisions**
_(empty)_

---

### MM0-T08 — Update tracker and commit
- **Status:** TODO
- **Depends on:** MM0-T07
- **Estimated effort:** S

**Goal**
Roll up MM0 status and commit.

**What to build (acceptance criteria)**
- Every task above shows `Status: DONE`.
- Milestone summary checklist at top of this file shows every box checked.
- `MAC_IMPLEMENTATION_PLAN.md` table row for MM0 shows `Done · 8/8`.
- Current milestone is updated to MM1 in master plan.
- Commits exist for each task, each prefixed with the task ID.

**How to build it**
1. Edit each task's `Status:` field to `DONE`. Check the boxes in `Verification`.
2. Update the checklist at the top of this file.
3. Update `MAC_IMPLEMENTATION_PLAN.md` table row and `Current milestone`.
4. Stage all changes, commit: `MM0-T08: close MM0 — Mac scheme green, AppEnvironment dual-platform`.

**Verification**
- [ ] `git log --oneline | grep MM0` shows ≥ 7 commits.
- [ ] Status tracker reads `MM1 — Data Sync` as current.

**Notes / decisions**
_(empty)_
