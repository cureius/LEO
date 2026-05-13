# MAC_AGENTS.md — Read this first (macOS port)

You are an AI coding agent porting **LEO** (iPhone app) to **macOS**. Feature parity is the bar. Same UX feel. CloudKit-backed sync between iPhone and Mac is critical.

This file is your entry point. Everything else is reachable from here.

## What you are building

The macOS sibling of LEO. Same data model, same Domain logic, same AI client, same persistence. The differences are:
- Mac-native shell (3-column `NavigationSplitView`, menu bar, MenuBarExtra, global hotkey, command palette, keyboard-first interactions, multi-window).
- Platform-conditional services where iOS APIs don't exist on macOS (`AlarmKit`, `ActivityKit`, `BGTaskScheduler`, share extensions etc.).
- A new Xcode target, new entitlements, new code-signing identity.

**Sync is the headline feature.** If a user adds an item on iPhone, it appears on Mac within ~60 seconds, and vice-versa, with no manual action.

## Reading order (do this every session)

1. `plans/mac/MAC_AGENTS.md` (this file) — orientation.
2. `plans/mac/MAC_IMPLEMENTATION_PLAN.md` — global rules + the live status tracker. **The status tracker is the source of truth** for what's done and what's next.
3. `plans/mac/conventions.md` — Mac-specific project structure, where new files go, platform-conditional patterns, testing.
4. `PRD.md` — product spec (shared with iOS).
5. `IMPLEMENTATION_PLAN.md` (iOS master) — read once at the start of the port to understand the existing app's milestone history. After that, only re-read when porting a specific feature.
6. The current Mac milestone file in `plans/mac/`, identified by the status tracker. Skim it end-to-end before picking a task.

If you skip these, you will redo work, duplicate code, fork the data model, or break the iOS app.

## Pick one task, in order

- Mac tasks have IDs like `MM0-T03` (the `MM` prefix avoids collision with iOS's `M0-T03`).
- Take the first task in the current Mac milestone whose status is `TODO` and whose dependencies are all `DONE`.
- Do not skip ahead. If blocked, mark the task `BLOCKED` with a one-line note, move on, and flag the block to the user.

## Working the task

1. Set the task's `Status:` to `IN-PROGRESS` before you start.
2. Read **What to build** and **How to build it**. These are the contract.
3. Stay inside scope. New scope = a new follow-up task in the milestone file.
4. When done, set the task `DONE` and check the boxes in **Verification**.
5. Update the milestone summary and the master tracker before ending the session.

## Anti-divergence rules (non-negotiable, additive to iOS rules)

1. **Never break iOS.** Every commit must build green on both iOS and macOS schemes. The iOS app is in production-prep; the Mac port cannot regress it.
2. **One canonical Domain.** `LEO/Domain/`, `LEO/Persistence/`, `LEO/AI/Cloud/`, `LEO/Monetization/`, `LEO/DesignSystem/` are platform-neutral. **Do not** create a `Domain-Mac/` or fork models — extend the existing ones.
3. **Platform code lives in `PlatformIOS/` and `PlatformMac/`.** A file that imports `UIKit`, `AlarmKit`, `ActivityKit`, `BGTaskScheduler`, `WidgetKit` iOS-only APIs, or `WatchKit` belongs in `PlatformIOS/`. A file that imports `AppKit`, `ServiceManagement`, `Carbon` for hotkeys, or macOS-only AppIntents belongs in `PlatformMac/`.
4. **Service protocols live in `Core` (existing folders).** iOS implementations stay in their current homes (`Notifications/`, `Alarms/`, `Integrations/`). Mac implementations live in `PlatformMac/Services/`. The protocol contract is the source of truth; both impls satisfy it.
5. **No new dependencies without approval.** Same rule as iOS. If you need `KeyboardShortcuts` (sindresorhus) for the global hotkey, ask first. Document the decision in `plans/mac/conventions.md`.
6. **No CloudKit schema changes without approval.** Any change to `Stored*` models or `SchemaV*` ripples to every installed iPhone. Stop and ask before touching `Persistence/SwiftData/Schema/` or `Persistence/SwiftData/Models/`.
7. **No new architectural patterns.** The iOS app uses `@Observable` view models, actor repositories, async/await throughout. Don't introduce Combine, no Redux, no TCA.
8. **Sync regressions are P0.** If a code path could change CloudKit container behavior, push back to user before merging. We dogfood the sync — a broken sync silently drops data.
9. **Stop and ask** before: enabling CloudKit auto-sync on a previously-deployed schema, changing entitlements, touching `PersistenceController.swift`, modifying the `Item` protocol, modifying any `Schema*.swift`, submitting to TestFlight.

## File map (post-port)

```
LEO/
├── AGENTS.md                       ← iOS agents entry
├── PRD.md                          ← shared product spec
├── ROADMAP.md                      ← shared roadmap
├── IMPLEMENTATION_PLAN.md          ← iOS master plan
├── plans/                          ← iOS milestone files (M0–M9)
│   └── mac/                        ← macOS port milestone files (MM0–MM9)
│       ├── MAC_AGENTS.md           ← you are here
│       ├── MAC_IMPLEMENTATION_PLAN.md
│       ├── conventions.md
│       ├── MM0-foundation.md
│       ├── MM1-data-sync.md
│       ├── MM2-shell.md
│       ├── MM3-today-inbox.md
│       ├── MM4-capture.md
│       ├── MM5-ai-recurrence.md
│       ├── MM6-platform-services.md
│       ├── MM7-fitness-habits-review.md
│       ├── MM8-onboarding-paywall-settings.md
│       └── MM9-widgets-ship.md
├── LEO/                            ← existing source (kept; refactored in MM0)
│   ├── App/
│   │   ├── LEOApp.swift            ← iOS entry (kept)
│   │   ├── LEOMacApp.swift         ← NEW macOS entry
│   │   ├── AppEnvironment.swift    ← platform-neutral, uses protocols
│   │   ├── RootView.swift          ← iOS root (kept)
│   │   ├── AppTabView.swift        ← iOS tabs (kept)
│   │   └── Mac/                    ← NEW
│   │       ├── MacRootView.swift
│   │       ├── MacShellView.swift
│   │       ├── MacSidebar.swift
│   │       ├── MacInspector.swift
│   │       ├── MacCommands.swift
│   │       └── MacNavigationModel.swift
│   ├── Domain/                     ← shared (no changes for platform)
│   ├── Persistence/                ← shared
│   ├── AI/                         ← shared
│   ├── DesignSystem/               ← shared
│   ├── Monetization/               ← shared
│   ├── PlatformIOS/                ← NEW — iOS-only services + features
│   │   ├── Services/               ← AlarmEngine (iOS), LocationReminders (iOS), …
│   │   ├── Integrations/           ← LiveActivities, Focus, iOS Widgets
│   │   └── Features/               ← any iOS-only screens that can't be ported
│   ├── PlatformMac/                ← NEW — macOS-only services + features
│   │   ├── Services/               ← AlarmEngineMac, LocationRemindersMac, MenuBarStatus
│   │   ├── Capture/                ← MenuBarExtra, global hotkey, floating capture
│   │   ├── Commands/               ← Menu bar, command palette
│   │   └── Features/               ← Mac-shaped Today, Inbox, Detail Inspector, etc.
│   └── Resources/
│       ├── LEO-mac.entitlements    ← NEW
│       └── Info-mac.plist          ← NEW
├── LEOTests/                       ← iOS unit tests
├── LEOMacTests/                    ← NEW Mac-only unit tests
├── LEOUITests/                     ← iOS UI tests
├── LEOWidgets/                     ← shared widget extension (made multi-platform in MM9)
└── project.yml                     ← updated for new target
```

## When you're stuck

- **Acceptance criteria unclear?** Ask the user. Do not guess.
- **An iOS pattern doesn't map cleanly to macOS?** Don't invent a third pattern — propose two options to the user, pick one, document it in `plans/mac/conventions.md`.
- **CloudKit sync isn't working between simulators?** First read `IMPLEMENTATION_PLAN.md` task `M3-T07` and `MM1` notes — there are known gotchas.
- **A SourceKit error says "Cannot find type X in scope"?** Per existing project notes, this is usually a SourceKit indexer false-positive. Run `xcodebuild` to verify.
- **A test fails on iOS that didn't before your change?** Stop and revert your platform-conditional logic. You leaked a Mac-only API into the iOS path.

## What "done" looks like for a task

A task is `DONE` when **all of these** are true:
- All **What to build** acceptance criteria met and demonstrated.
- All **Verification** boxes checked.
- Both iOS and macOS schemes build green: `xcodebuild -scheme LEO build` AND `xcodebuild -scheme LEO-Mac build`.
- For sync-touching tasks: verified bidirectional iPhone↔Mac with the recipe in `MM1-data-sync.md`.
- Code committed with task ID prefix (e.g. `MM2-T03: add NavigationSplitView shell`).
- Status line in milestone file says `DONE`.
- Progress table in `MAC_IMPLEMENTATION_PLAN.md` reflects new state.

If you're unsure whether something is done, it isn't.
