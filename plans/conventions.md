# Conventions

Read this once. Then re-read whenever you're about to make a project-shape decision.

---

## Project structure

```
LEO.xcodeproj                       # created in M0-T01
LEO/
  App/
    LEOApp.swift                    # @main, scene, root injection
    AppDelegate.swift               # only if APNs/PushKit forces it
  Features/                         # vertical slices, one folder per feature
    Today/
      Views/
      ViewModels/
      Today.swift                   # entry point view exported by the feature
    Capture/
    Inbox/
    Recurrence/
    Notifications/
    Habits/
    Review/
    AssistantChat/
    Settings/
    Onboarding/
    Paywall/
  Domain/                           # value types, business logic, no UI
    Items/                          # Item protocol + concrete types
    Recurrence/                     # RRULE engine
    Scheduling/                     # slot-finding, conflict detection
    Habits/                         # streak math, instance materialization
    Diff/                           # ItemChange, Diff types
  Persistence/
    SwiftData/                      # @Model types, ModelContainer, migrations
    CloudKit/                       # container config, conflict policy
    EventKit/                       # bridge: import, write-back, sync state
  AI/
    OnDevice/                       # FoundationModels wrappers
    Cloud/                          # Claude API client + tool definitions
    Routing/                        # picks tier per request
    Prompts/                        # system prompts as resources
  Notifications/                    # UNUserNotificationCenter scheduling
  Alarms/                           # AVAudioSession, Live Activity controller
  Integrations/
    Widgets/                        # WidgetKit extension target lives outside, but shared models here
    LiveActivities/
    AppIntents/
    Shortcuts/
  DesignSystem/
    Theme.swift                     # colors, type, spacing tokens
    Components/                     # reusable views (Buttons, Chips, ItemRow…)
  Utilities/                        # date helpers, formatters, etc.
  Resources/
    Localizable.xcstrings
    Assets.xcassets
    Info.plist
LEOTests/                           # unit tests (XCTest)
LEOUITests/                         # UI tests (XCUITest)
LEOWidgets/                         # widget extension target (added M3)
LEOWatch/                           # watchOS target (added M6)
```

**Rules:**
- Features depend on `Domain`, `Persistence`, `DesignSystem`, `Utilities`. Features **do not import other features**. Cross-feature reuse goes into `Domain` or `DesignSystem`.
- `Domain` types are pure (no SwiftUI, no SwiftData). They have unit tests.
- `Persistence/SwiftData` types are `@Model`s and exist only there. Map to/from Domain types at the boundary.
- `AI/`, `Notifications/`, `Alarms/`, `Integrations/` are services consumed by features via dependency injection.

---

## Naming

- **Types:** `UpperCamelCase`. Avoid abbreviations except: `URL`, `ID`, `UI`, `AI`, `OS`.
- **Methods/properties:** `lowerCamelCase`.
- **Concrete `Item` types:** `TaskItem`, `EventItem`, `ReminderItem`, `AlarmItem`, `HabitInstanceItem`. Suffix `Item` is mandatory — avoids collision with `_Concurrency.Task`, `EKEvent`, etc.
- **View files:** `<Name>View.swift` for the SwiftUI view, `<Name>ViewModel.swift` for the `@Observable` view model.
- **Protocols:** name by capability, not "I" prefix. `ItemRepository`, not `IItemRepository`.
- **Test files:** mirror the source path. `Domain/Recurrence/RecurrenceEngine.swift` → `LEOTests/Domain/Recurrence/RecurrenceEngineTests.swift`.

---

## SwiftUI patterns

- Use `@Observable` view models. Do **not** use `ObservableObject` / `@Published`.
- Inject services via `@Environment(\.someService)` — define environment keys in `App/Environment+Keys.swift`.
- Views never call SwiftData directly. Views call view models. View models call repositories. Repositories call SwiftData.
- Keep view files under ~300 lines. Split with `private struct` subviews in the same file before reaching for new files; split into a new file when the subview becomes reusable.

---

## SwiftData patterns

- Every `@Model` has an explicit `init`. No `@Attribute(.unique)` unless that field is genuinely a primary key.
- All `@Model` types live in `Persistence/SwiftData/`. They are *not* the Domain types. Domain types are plain structs in `Domain/`.
- Repositories (`ItemRepository`, `HabitRepository`, etc.) own the mapping. Views/view models never see `@Model` types directly.
- Schema migrations: `VersionedSchema` from day one. Increment the schema version on every breaking change. Never silently mutate an existing `@Model` in a way that loses data.
- CloudKit constraints: every relationship must be optional or have a default value. `@Attribute(.unique)` is forbidden (CloudKit doesn't support it).

---

## Concurrency

- All async work uses `async`/`await`. No completion handlers in new code (wrap legacy APIs with `withCheckedContinuation`).
- Long-running services (sync, AI client, notification manager) are `actor`s.
- View models are `@MainActor`. Repositories may be `actor`s; their async methods are awaited by view models.
- Never block the main thread with file I/O, network, EventKit, or CloudKit calls. Always `await` them off-main.

---

## Errors

- Throw concrete error types, not `NSError`.
- Each subsystem defines a single error enum: `RecurrenceError`, `SyncError`, `AIError`, etc.
- View models translate domain errors into user-facing strings at the boundary; views display via a single `ErrorBanner` component.
- Do **not** swallow errors. Either handle, propagate, or log to MetricKit.

---

## Logging

- Use `os.Logger` with subsystem `com.leo.app` and category-per-subsystem (`recurrence`, `sync`, `ai`, `notifications`, etc.).
- `logger.debug` for dev tracing, `.info` for user-visible lifecycle, `.error` for things we want to see in MetricKit.
- No `print()` in committed code outside one-off scripts.

---

## Testing

- **XCTest** for unit + UI tests in v1. Re-evaluate Swift Testing in v1.x.
- Every Domain type that has logic has unit tests. View models have tests for state transitions; views are exercised via UI tests, not snapshot tests in v1.
- **Recurrence engine has a golden-file test suite.** Add a test for every new RRULE pattern before implementing it.
- Tests run in CI on every push (M0-T07 wires this).
- Performance tests (XCTest's `measure`) for: timeline rendering, quick-add parse, recurrence expansion. Wire in M2.

---

## Commits

- One commit per task ID. Subject line:
  ```
  M{N}-T{NN}: <short imperative summary>
  ```
- Body: bullet list of what changed. Reference any open question or decision.
- No `WIP` commits on `main`. Use a feature branch per milestone (`m0-foundation`, `m1-capture`, …) and merge with a single squash-style commit per task. (If the user prefers trunk-based with many small commits, the user will say so; default to milestone branches.)
- Pre-commit: `swiftformat` + `swiftlint` clean, build green, all unit tests passing.

---

## Documentation

- Public types in `Domain/` get a one-line `///` doc comment. Nothing more unless the WHY is non-obvious.
- Don't write file headers (`// File created by …`).
- Don't write redundant comments (`// increment counter`).

---

## Approved Swift packages

This list grows by user approval only.

| Package | Purpose | Approved on |
|---|---|---|
| *(none yet — vendor or stdlib only)* | | |

When proposing one: name, purpose, license, weight (LOC + binary size), maintainer, alternatives. The user accepts or rejects in chat. If accepted, add a row above and update task notes.

---

## Things to never do (specific to this project)

- Never call `EKEventStore` directly from a view or view model. Go through `EventKitBridge`.
- Never call `UNUserNotificationCenter` directly from a feature. Go through `NotificationManager`.
- Never store user content in `UserDefaults`. SwiftData only. (Settings flags are fine.)
- Never use `DispatchQueue.main.async`. Use `await MainActor.run` or `@MainActor` annotations.
- Never write a TODO without a follow-up task in the relevant milestone file.
- Never commit secrets. Claude API key lives in Keychain at runtime, in `.env.local` at dev time (gitignored), and in CI secrets for tests.
