# Conventions — macOS port

Mac-specific conventions. Additive to `plans/conventions.md` (iOS). When the two conflict, this file wins for Mac code.

---

## Where new files go

```
LEO/
├── App/
│   ├── LEOApp.swift                ← unchanged (iOS @main)
│   └── Mac/                        ← NEW Mac scene scaffolding
│       ├── LEOMacApp.swift         ← @main for Mac scheme
│       ├── MacRootView.swift       ← scene root (gates onboarding/paywall)
│       ├── MacShellView.swift      ← NavigationSplitView container
│       ├── MacSidebar.swift        ← left column
│       ├── MacInspector.swift      ← right column (replaces ItemDetailSheet)
│       ├── MacCommands.swift       ← menu bar commands struct
│       └── MacNavigationModel.swift← selection state, @Observable
├── PlatformIOS/                    ← iOS-only services & features (moved from existing locations in MM0-T04)
│   ├── Services/
│   │   ├── AlarmEngine.swift               ← moved from Alarms/
│   │   ├── LocationReminderManager.swift   ← moved from Notifications/
│   │   └── TravelTimePreReminder.swift     ← moved from Notifications/
│   ├── Integrations/
│   │   ├── LiveActivities/                 ← moved from Integrations/
│   │   └── Focus/                          ← moved from Integrations/
│   └── Features/                            ← any iOS-only screens (e.g. lock-screen widget previews)
├── PlatformMac/                    ← NEW macOS-only services & features
│   ├── Services/
│   │   ├── AlarmEngineMac.swift            ← NSSound-based, window-bringing
│   │   ├── LocationReminderManagerMac.swift← CoreLocation on macOS 14+
│   │   ├── MenuBarStatusController.swift   ← MenuBarExtra orchestration
│   │   └── GlobalHotkeyManager.swift       ← NSEvent global monitor
│   ├── Capture/
│   │   ├── MenuBarCaptureView.swift
│   │   ├── FloatingCaptureWindow.swift
│   │   └── MacQuickAddView.swift
│   ├── Commands/
│   │   ├── CommandPaletteView.swift
│   │   └── MacKeyboardShortcuts.swift
│   └── Features/
│       ├── Today/
│       ├── Inbox/
│       ├── Habits/
│       ├── AssistantChat/
│       ├── Recurrence/
│       ├── Fitness/
│       ├── ItemDetail/             ← MacInspector content
│       ├── Settings/               ← Mac settings panes
│       └── Onboarding/             ← Mac onboarding window
└── Resources/
    ├── LEO-mac.entitlements        ← NEW
    ├── LEO-mac-debug.entitlements  ← NEW
    └── Info-mac.plist              ← NEW
```

**Rules:**
- A file goes in `PlatformIOS/` if it imports any of: `UIKit`, `AlarmKit`, `ActivityKit`, `BackgroundTasks`, `WatchKit`, `WidgetKit` iOS-only types, lock-screen-specific APIs.
- A file goes in `PlatformMac/` if it imports any of: `AppKit`, `ServiceManagement`, `Carbon` hotkey APIs, `IOKit`, macOS-only `AppIntents` subclasses.
- Anything else (Domain, Persistence, AI, DesignSystem, Monetization, Utilities) stays where it is and is shared.

## Platform-conditional patterns

### Pattern A — protocol with two impls (preferred)

For services with significant divergence (AlarmEngine, LocationReminder, MenuBarStatus):

```swift
// Core/Notifications/AlarmEngineProtocol.swift
protocol AlarmEngineProtocol: Actor {
    func arm(_ alarm: AlarmItem) async
    func disarm(id: UUID) async
    func snooze(alarm: AlarmItem, minutes: Int) async
}

// PlatformIOS/Services/AlarmEngine.swift
actor AlarmEngine: AlarmEngineProtocol { /* AVAudioSession impl */ }

// PlatformMac/Services/AlarmEngineMac.swift
actor AlarmEngineMac: AlarmEngineProtocol { /* NSSound impl */ }

// App/AppEnvironment.swift
let alarmEngine: any AlarmEngineProtocol = {
    #if os(iOS)
    return AlarmEngine(notificationManager: nm)
    #else
    return AlarmEngineMac(notificationManager: nm)
    #endif
}()
```

### Pattern B — conditional view body (small divergences only)

For views that are 95% shared but differ in 1–2 modifiers:

```swift
var body: some View {
    content
        #if os(iOS)
        .sheet(isPresented: $showDetail) { ItemDetailSheet(item: item) }
        #else
        .inspector(isPresented: $showDetail) { MacInspectorContent(item: item) }
        #endif
}
```

**Threshold:** if `#if os` covers more than 10 lines or 3 modifier chains, split into two files instead.

### Pattern C — two files, shared view model

For views with significantly different shell but identical state:

```
Features/Today/
├── ViewModels/TodayViewModel.swift   ← shared, no platform code
├── Views/TodayView.swift             ← iOS version
PlatformMac/Features/Today/
└── MacTodayView.swift                ← Mac version, uses TodayViewModel
```

Both views observe the same `TodayViewModel`. Selection, filtering, drag-reschedule logic lives in the view model so neither view re-implements it.

## Naming

- **Mac-only types:** suffix with `Mac`. Examples: `AlarmEngineMac`, `MacShellView`, `MacInspector`, `MacQuickAddView`, `MenuBarCaptureView`.
- **Shared types:** no suffix. If you need to disambiguate from a Mac variant, prefix instead: `ItemDetailSheet` (iOS) vs `MacInspector` (Mac).
- **Files in `App/Mac/`** can be prefixed `Mac*` because they're inherently scene-scoped.
- **Files in `PlatformMac/`** should be named for their function, not for "Mac" — context already says Mac. Exception: shared protocol implementations (`AlarmEngineMac` etc.) keep the suffix to read clearly in `AppEnvironment`.

## Imports

- **Shared code (in `Domain`, `Persistence`, `AI`, `DesignSystem`, `Monetization`):** only import `Foundation`, `SwiftUI`, `SwiftData`, `Combine`, `OSLog`, `Charts`. Never `UIKit`, `AppKit`, `WatchKit`.
- **iOS-only files in `PlatformIOS/`:** import what they need. `import UIKit` is fine here.
- **Mac-only files in `PlatformMac/`:** `import AppKit` is fine here.
- **Files in `App/Mac/`:** import `SwiftUI` plus `AppKit` only when needed (e.g. `NSApplication.shared.activate(ignoringOtherApps:)` calls).
- **`AppEnvironment.swift`:** must compile on both platforms. No `UIKit` or `AppKit`. Use `#if os` for the few platform-specific service factories.

## Build system (xcodegen)

`project.yml` gains a second target `LEO-Mac`:

```yaml
targets:
  LEO:
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - path: LEO
        excludes:
          - "**/.gitkeep"
          - "PlatformMac/**"
          - "App/Mac/**"
          - "Resources/LEO-mac.entitlements"
          - "Resources/LEO-mac-debug.entitlements"
          - "Resources/Info-mac.plist"
    # ... existing settings
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
          - "Resources/LEO.entitlements"
          - "Resources/LEO-debug.entitlements"
          - "Resources/Info.plist"
    resources:
      - LEO/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.theblueman.leo
        INFOPLIST_FILE: LEO/Resources/Info-mac.plist
        # ... see MM0-T01 for full block
```

**Rule:** every Mac-only file must be excluded from the iOS target, and every iOS-only file from the Mac target, using `excludes:` globs. The build will warn at first if you miss one — fix immediately, don't suppress.

After adding new Swift files: `xcodegen generate`.

## Testing

- **Shared unit tests** stay in `LEOTests/` and are run by both schemes (target membership includes both).
- **Mac-specific unit tests** (e.g. `AlarmEngineMacTests`) live in `LEOMacTests/`, target membership `LEO-Mac` only.
- **iOS-specific unit tests** (e.g. `LocationReminderManagerTests` that monitor regions) stay in `LEOTests/`, target membership `LEO` only.
- **UI tests:** iOS UI tests in `LEOUITests/`. Mac UI tests deferred to post-launch (XCUITest on macOS is tolerable but slow).

Run before any commit:
```bash
xcodebuild -scheme LEO test -destination 'platform=iOS Simulator,id=FB3865AE-D134-4831-8A18-5CC7394D16C5'
xcodebuild -scheme LEO-Mac test -destination 'platform=macOS,arch=arm64'
```

## Commit conventions

- Prefix every commit with the Mac task ID: `MM3-T02: …`.
- iOS-touching commits during the port (e.g. extracting a protocol from an iOS service into Core) get the Mac task ID, not an iOS task ID. The change is in service of the port.
- If a commit really only changes iOS behavior incidentally, split it into two commits, one prefixed `MM?-T?` and the other an iOS task ID.

## Entitlements

The Mac app's entitlements file (`LEO-mac.entitlements`) must include:
- `com.apple.developer.icloud-container-identifiers` = `iCloud.com.theblueman.leo` (same container as iOS)
- `com.apple.developer.icloud-services` = `CloudKit`
- `com.apple.developer.ubiquity-kvstore-identifier` = `$(TeamIdentifierPrefix)com.theblueman.leo`
- `com.apple.security.app-sandbox` = true (App Store requires sandbox)
- `com.apple.security.network.client` = true (Claude API)
- `com.apple.security.personal-information.calendars` = true (EventKit)
- `com.apple.security.personal-information.reminders` = true (EventKit)
- `com.apple.security.personal-information.location` = true (CoreLocation)
- `com.apple.security.files.user-selected.read-write` = true (file exports, fitness images)
- `com.apple.security.application-groups` = `group.com.theblueman.leo` (widgets snapshot)

Debug variant adds nothing extra; production is identical.

## Code-signing & provisioning

- Same team ID as iOS (`ZT397U24CA`).
- New App ID in Apple Developer for `com.theblueman.leo` macOS distribution (the bundle ID is shared with iOS but the platform-specific entitlements differ). Confirm in MM0-T02 whether the existing App ID covers both platforms (typically yes for unified bundle ID).
- Automatic signing for Debug. Manual signing for Release (matches iOS workflow).

## Things explicitly forbidden

- Don't import `UIKit` anywhere outside `PlatformIOS/`.
- Don't use `#if !targetEnvironment(macCatalyst)`. We are not Catalyst — we are a true macOS app. Use `#if os(macOS)` exclusively.
- Don't add a `Mac.target.json` or any per-platform overlay file. One `project.yml` for both.
- Don't fork Domain types. If a Mac-only field is genuinely needed, propose it to the user before adding.
- Don't change the iOS deployment target to chase a SwiftUI API. Find a Mac-only alternative.
