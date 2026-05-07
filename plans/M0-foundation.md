# M0 — Foundation

**Goal of this milestone:** A working Xcode project with the data model running, sync configured, CI green, and dev seeding in place. **No user-facing features ship in M0.** Every later milestone depends on this being solid.

**Target ship:** 2026-05-21 (2 weeks).

**Read before starting:** [`AGENTS.md`](../AGENTS.md), [`IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md), [`conventions.md`](conventions.md), [`PRD.md`](../PRD.md) §6 (data model) and §10 (architecture).

---

## Task summary

- [x] M0-T01 — Create Xcode project
- [x] M0-T02 — Set up project folder structure
- [x] M0-T03 — Define design system foundations
- [x] M0-T04 — Define Domain types
- [x] M0-T05 — Implement SwiftData persistence + repositories
- [x] M0-T06 — Configure CloudKit private DB sync
- [x] M0-T07 — Set up CI, formatter, linter
- [x] M0-T08 — Dev seeding + MetricKit + debug menu

---

### M0-T01 — Create Xcode project
- **Status:** DONE
- **Depends on:** —
- **Estimated effort:** S

**Goal**
Create the LEO Xcode project with the right capabilities and minimum settings.

**What to build (acceptance criteria)**
- Xcode project at `/Users/raj/Raj/personal/IOS/LEO/LEO.xcodeproj`.
- App target `LEO`, bundle ID `com.leo.app` (placeholder; user can change).
- Minimum deployment iOS 18.0.
- Swift 6.0+, strict concurrency = "Complete".
- SwiftUI lifecycle. Single scene.
- Capabilities enabled: **iCloud (CloudKit)**, **Background Modes (Remote notifications, Background processing)**, **Push Notifications**, **App Groups** (group ID `group.com.leo.app`).
- Test targets `LEOTests` (unit) and `LEOUITests` (UI) created.
- App launches in simulator showing a placeholder "LEO" text.
- `.gitignore` set up for Xcode (`xcuserdata/`, `.DS_Store`, `*.xcworkspace/xcuserdata/`, `.env.local`).

**How to build it**
1. Use Xcode's "App" template. SwiftUI, Swift, Storage = "SwiftData", Include Tests = on.
2. After creation, in target settings:
   - General → Minimum Deployments → iOS 18.0.
   - Signing & Capabilities → enable the capabilities listed above.
   - Build Settings → Swift Compiler - Concurrency → Strict Concurrency Checking = Complete.
3. The default `LEOApp.swift` keeps its `@main` and `WindowGroup`. Delete the default `Item` model and `ContentView`'s sample list; replace `ContentView` body with `Text("LEO")`.
4. Create `.gitignore` with the Xcode template from `https://github.com/github/gitignore/blob/main/Swift.gitignore` (vendor-copy, do not fetch at build time).
5. `git init`, initial commit "M0-T01: bootstrap Xcode project".

**Verification**
- [ ] `xcodebuild -scheme LEO -destination 'platform=iOS Simulator,name=iPhone 15' build` succeeds.
- [ ] App launches in simulator and shows "LEO".
- [ ] `git status` clean after first commit.

**Notes / decisions**
*(empty)*

---

### M0-T02 — Set up project folder structure
- **Status:** DONE
- **Depends on:** M0-T01
- **Estimated effort:** S

**Goal**
Mirror the folder structure documented in `conventions.md` so subsequent tasks have a place to put files.

**What to build (acceptance criteria)**
- All folders from `conventions.md` "Project structure" exist on disk under `LEO/` and as Xcode groups (in-sync with disk).
- A `README.md` is **not** added (PRD/ROADMAP/AGENTS suffice).
- Each folder contains a `.gitkeep` so git tracks empty dirs.

**How to build it**
1. Create folders on disk with `mkdir -p` matching the structure in `conventions.md`.
2. In Xcode, drag each folder into the project navigator with "Create groups" (not folder references). Verify the disk path equals the group path for each.
3. Touch `.gitkeep` in every empty folder.
4. Commit as "M0-T02: set up project folder structure".

**Verification**
- [ ] Folders visible in Xcode navigator with the exact names/case from conventions.
- [ ] `find LEO -type d` matches the expected list.
- [ ] Build still succeeds.

---

### M0-T03 — Define design system foundations
- **Status:** DONE
- **Depends on:** M0-T02
- **Estimated effort:** M

**Goal**
A `Theme` namespace + a small set of reusable components so M1 views can be built without one-off styling.

**What to build (acceptance criteria)**
- `DesignSystem/Theme.swift` exposes:
  - `Theme.Color` (semantic): `background`, `surface`, `surfaceElevated`, `accent`, `accentMuted`, `textPrimary`, `textSecondary`, `divider`, `success`, `warning`, `danger`. Light + dark resolved automatically (use Asset Catalog colors).
  - `Theme.Spacing`: `xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`.
  - `Theme.Radius`: `sm=6, md=10, lg=16`.
  - `Theme.Typography`: scaled Dynamic Type styles via `Font` extensions for `largeTitle`, `title`, `headline`, `body`, `callout`, `caption` — all backed by SF Pro and supporting AX5.
- `DesignSystem/Components/`:
  - `LEOButton(style: .primary | .secondary | .destructive)` — SwiftUI button with consistent padding, radius, color, accessibility.
  - `LEOTextField(placeholder:text:)` — for quick-add and forms.
  - `LEOChip(label:icon:)` — small pill component used by tags/categories.
  - `LEOCard` — surface container with consistent corner radius + shadow.
  - `LEOEmptyState(title:message:icon:)` — for empty list states (used by Inbox, Today when nothing scheduled, etc.).
- All colors from a single Asset Catalog `Theme.xcassets` with light/dark variants.

**How to build it**
1. Add `Theme.xcassets` under `DesignSystem/`. Define each named color with both light and dark appearances. Use OKLCH-equivalent steps if eyeballing — avoid pure black/white.
2. `Theme.swift` exposes the values via `static let` on nested enums. Example pattern:
   ```swift
   enum Theme {
     enum Color {
       static let background = SwiftUI.Color("Theme/Background")
       // …
     }
   }
   ```
3. Each component is a struct conforming to `View`. Take a `@Environment(\.dynamicTypeSize)` where it affects layout. Provide accessibility labels where structure isn't enough.
4. Add a `DesignSystemPreview.swift` with `#Preview` blocks showing every component in light + dark + AX5 sizes. This is the visual smoke test — used in T08's debug menu too.

**Verification**
- [ ] `#Preview { DesignSystemPreview() }` renders every component in both color schemes.
- [ ] Components scale through Dynamic Type AX5 without truncation or overflow.
- [ ] No hardcoded colors anywhere outside `Theme.xcassets` (`grep -rn "Color(" LEO/` should only show usages routed through `Theme.Color`).

**Notes / decisions**
- We deliberately keep the system small; resist adding components until M1 views actually need them.

---

### M0-T04 — Define Domain types
- **Status:** DONE
- **Depends on:** M0-T02
- **Estimated effort:** L

**Goal**
Write the pure-Swift Domain types per PRD §6. No SwiftData, no SwiftUI in this layer. These types are what the rest of the app reasons about.

**What to build (acceptance criteria)**
- File `Domain/Items/Item.swift`:
  - `protocol Item: Identifiable, Hashable, Sendable` with shared properties:
    - `var id: UUID { get }`
    - `var title: String { get set }`
    - `var notes: String? { get set }` (single line, max 280 chars; enforced at boundary not in protocol)
    - `var createdAt: Date { get }`
    - `var updatedAt: Date { get set }`
    - `var importance: Importance { get set }` (enum: `low`, `normal`, `high`, `urgent`)
    - `var anchor: Anchor { get set }`
    - `var completion: Completion { get set }`
    - `var tags: [Tag] { get set }`
- `Domain/Items/Anchor.swift`:
  - `enum Anchor`:
    - `.untimed` (Inbox)
    - `.dueAt(Date)` (a Task with a deadline)
    - `.timeBlock(start: Date, end: Date)` (an Event)
    - `.point(Date)` (a Reminder/Alarm)
    - `.location(LocationTrigger)` (a location reminder)
- `Domain/Items/Completion.swift`:
  - `enum Completion`: `.open`, `.completed(at: Date)`, `.skipped(at: Date, reason: String?)`, `.dismissed`.
- `Domain/Items/Importance.swift` — `enum Importance: Int { case low, normal, high, urgent }`.
- `Domain/Items/Tag.swift` — `struct Tag: Hashable, Sendable { let id: UUID; let name: String; let color: TagColor }` with `enum TagColor` of named palette (no free-form hex in v1).
- Concrete types as `struct`s conforming to `Item`:
  - `Domain/Items/TaskItem.swift` — adds `estimatedDuration: Duration?`, `deadline: Date?` (separate from anchor; deadline is the hard date even when work is scheduled earlier).
  - `Domain/Items/EventItem.swift` — adds `location: String?`, `attendees: [String]` (just names/emails; no contacts integration v1).
  - `Domain/Items/ReminderItem.swift` — adds `leadTime: TimeInterval?` (for "remind 10 min before").
  - `Domain/Items/AlarmItem.swift` — adds `soundProfile: AlarmSound`, `escalates: Bool`.
  - `Domain/Items/HabitInstanceItem.swift` — adds `habitID: UUID`, `targetDuration: Duration?`.
- `Domain/Items/LocationTrigger.swift` — `struct LocationTrigger: Hashable, Sendable { let coordinate: Coordinate; let radiusMeters: Double; let direction: TriggerDirection (entering/leaving) }` with `Coordinate` being a plain `(lat: Double, lon: Double)` so this layer doesn't depend on CoreLocation.
- `Domain/Recurrence/RecurrenceRule.swift` — sketch only in M0; the engine ships in M2:
  ```swift
  struct RecurrenceRule: Hashable, Sendable {
    let raw: String        // RFC 5545 RRULE string
    let extensions: [LEORuleExtension]   // empty in v1 stub; populated in M2
  }
  enum LEORuleExtension: Hashable, Sendable { case workdaysOnly, skipUSHolidays, firstWeekdayOfMonth }
  ```
- `Domain/Habits/Habit.swift` — `struct Habit { id, name, frequency: HabitFrequency, timeHint: TimeOfDay?, targetDuration: Duration?, recurrenceRule: RecurrenceRule, forgiveness: HabitForgiveness, createdAt }`. Define supporting enums.
- `Domain/Diff/ItemChange.swift` — `enum ItemChange: Hashable, Sendable`:
  - `.add(Item)`
  - `.update(id: UUID, patch: ItemPatch)`
  - `.delete(id: UUID)`
- `Domain/Diff/Diff.swift` — `struct Diff: Hashable, Sendable { let changes: [ItemChange]; let rationale: String? }`.
- All types are `Sendable`. All `enum`s with associated values are `Hashable` (manual conformance if needed).

Tests:
- `LEOTests/Domain/Items/ItemTests.swift` — minimal: each concrete type conforms to `Item`; round-trips via Codable if you add Codable conformance (defer Codable — NOT required in M0).
- `LEOTests/Domain/Diff/DiffTests.swift` — `Diff` equality, change union sanity.

**How to build it**
1. Existential or generic? Use `any Item` at the boundary (e.g., views see `[any Item]`). Don't try to make `Item` a generic constraint everywhere; the heterogeneity is the point.
2. **Don't** add Codable yet. Persistence happens through SwiftData mapping (T05), not Codable serialization.
3. Date handling: store all dates as `Date` (UTC under the hood). Time-zone interpretation happens at display time using `Calendar.current`. Document this on every date property.
4. Concurrency: types are value types, so `Sendable` is automatic for structs of `Sendable` parts. Verify the compiler agrees with strict concurrency on.

**Verification**
- [ ] All types compile under strict concurrency.
- [ ] Unit tests pass (`xcodebuild test`).
- [ ] No imports of `SwiftUI`, `SwiftData`, `EventKit`, or `CoreLocation` in any `Domain/` file (`grep -rn "import" LEO/Domain/` shows only `Foundation`).

**Notes / decisions**
- Why `Item` is a protocol, not a sealed enum: extensibility without modifying every switch site, and SwiftData persistence wants concrete types per `@Model`. Trade-off: pattern-matching is verbose.

---

### M0-T05 — Implement SwiftData persistence + repositories
- **Status:** DONE
- **Depends on:** M0-T04
- **Estimated effort:** L

**Goal**
SwiftData `@Model`s, the `ModelContainer` setup, and repository types that map between Domain and storage.

**What to build (acceptance criteria)**
- `Persistence/SwiftData/Schema/SchemaV1.swift` — `enum SchemaV1: VersionedSchema` with `static var versionIdentifier = Schema.Version(1, 0, 0)` and the array of model types listed below.
- `Persistence/SwiftData/Migrations/MigrationPlanV1.swift` — `enum MigrationPlanV1: SchemaMigrationPlan` with `static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]` and `static var stages: [MigrationStage] = []`. (Empty in v1; in place so future migrations have a home.)
- `@Model` types in `Persistence/SwiftData/Models/` matching each Domain `Item` concrete type:
  - `StoredItemBase` is **not** modeled (SwiftData class inheritance is fragile). Instead, each concrete model has its own `@Model` with the shared fields duplicated. Mapping handles the protocol.
  - Models: `StoredTask`, `StoredEvent`, `StoredReminder`, `StoredAlarm`, `StoredHabit`, `StoredHabitInstance`, `StoredTag`, `StoredRecurrenceRule`.
  - Relationships: `StoredHabit` has `instances: [StoredHabitInstance]?` with cascade delete; `StoredTask`/`StoredEvent`/etc. have optional `tags: [StoredTag]?` (many-to-many).
  - **No `@Attribute(.unique)`** anywhere (CloudKit constraint).
  - Every relationship is optional or has a default.
- `Persistence/SwiftData/PersistenceController.swift`:
  - `actor PersistenceController` with a single shared `ModelContainer(for: SchemaV1.self, migrationPlan: MigrationPlanV1.self, configurations: ...)`.
  - Two configurations: `default` (CloudKit-synced) and `inMemory` (for tests/previews).
  - Init can take `useInMemory: Bool = false`.
- `Persistence/Mapping/ItemMapping.swift` — pure functions that map each Stored* ↔ Domain concrete type. Tests for round-trip.
- Repositories in `Persistence/Repositories/`:
  - `actor ItemRepository` — `func fetch(predicate: ItemPredicate) async throws -> [any Item]`, `add(_:)`, `update(_:)`, `delete(id:)`.
  - `actor HabitRepository` — habit CRUD + `instances(in: DateInterval)`.
  - `actor TagRepository` — list, find or create.
  - `ItemPredicate` is a value type the repo translates to `#Predicate<StoredX>` per backing model.
- Repositories are injected into views via the environment; never used directly in views.

**How to build it**
1. Define `SchemaV1` first; add models incrementally and re-run tests after each one.
2. Mapping functions: keep them in one file per direction (`ItemMapping+ToDomain.swift`, `ItemMapping+ToStored.swift`) if they grow large. For M0 keep one file.
3. `ItemPredicate` minimal v1 cases: `.all`, `.byID(UUID)`, `.inDateInterval(DateInterval)`, `.completionState(Completion.Filter)`. The repository switches over these and builds typed `#Predicate`s.
4. **CloudKit gotcha:** `Date` and `String` work, but `[String]` requires `@Attribute(.transformable)` or storing as JSON. Use a `Data` field with JSON for `attendees: [String]` and `tags`-via-relationships for tags. Document the choice inline.
5. Tests in `LEOTests/Persistence/`:
   - `PersistenceControllerTests` — opens an in-memory container, inserts each model type.
   - `ItemRepositoryTests` — CRUD round-trip for each Item kind.
   - `MappingTests` — domain ↔ stored fidelity for sample fixtures.

**Verification**
- [ ] All persistence tests pass.
- [ ] `PersistenceController(useInMemory: true)` opens cleanly and is reusable across tests.
- [ ] No warnings about non-Sendable types crossing actor boundaries.

**Notes / decisions**
- We *did not* try to make `Item` a single SwiftData type with a discriminator. Subclassing `@Model` types is officially supported but historically buggy. One model per concrete kind is safer and the mapping cost is trivial.

---

### M0-T06 — Configure CloudKit private DB sync
- **Status:** DONE
- **Depends on:** M0-T05
- **Estimated effort:** M

**Goal**
SwiftData syncs through CloudKit private database across devices signed into the same iCloud account.

**What to build (acceptance criteria)**
- iCloud capability in target uses container `iCloud.com.leo.app` (placeholder — user can rename).
- `ModelConfiguration` for `default` uses `cloudKitDatabase: .private("iCloud.com.leo.app")`.
- A schema-push helper in `Persistence/CloudKit/SchemaSync.swift` — debug-only function that calls `try await container.schema.uploadSchemaToCloudKit()`-equivalent path (the actual API: SwiftData auto-creates record types on first write; the dev menu offers a "force schema push" that writes a sample record per type).
- Documented in this task's notes: which production records to seed for first sync, which to wipe.
- Two-simulator test: write an Item on Sim A, observe it in Sim B within 60s.

**How to build it**
1. Sign Xcode into an Apple ID. The user has one personal account already; ask if they want to use it for development.
2. CloudKit container creation happens automatically once the capability is set and the app is run on a device or sim signed into iCloud.
3. SwiftData will auto-create record types on first write. **It does not delete fields when you remove them** — schema becomes append-only in production. Note this in the task body.
4. **Don't deploy the schema to production yet** (CloudKit Dashboard → Deploy Schema) — keep it Development-only until the schema stabilizes at end of M3.
5. Write `SchemaSync.forceSeed()` that inserts then deletes one of every model. Bind to a debug menu button (T08).

**Verification**
- [ ] Two simulators, same iCloud account: insert on A, see on B within 60s.
- [ ] CloudKit Dashboard shows the expected record types in Development.
- [ ] Toggle airplane mode on A, edit an Item, return online → change syncs.

**Notes / decisions**
- **STOP AND ASK** before setting `cloudKitDatabase: .public(...)` — that changes the entire trust model.
- Container ID is environment-dependent. Document final ID in `IMPLEMENTATION_PLAN.md` decision log when chosen.

---

### M0-T07 — Set up CI, formatter, linter
- **Status:** DONE
- **Depends on:** M0-T05
- **Estimated effort:** M

**Goal**
Every push runs build + tests; every commit is auto-formatted and lint-clean.

**What to build (acceptance criteria)**
- `swiftformat` config at `.swiftformat` matching project conventions (4-space indent, max line ~120, etc.).
- `swiftlint` config at `.swiftlint.yml` with the rules listed in conventions (no force-unwrap in non-test code, no implicit-getter unless trivial, etc.).
- Pre-commit hook script at `scripts/pre-commit.sh` running both tools; doc'd in `conventions.md`.
- GitHub Actions workflow at `.github/workflows/ci.yml`:
  - Runs on push and PR.
  - Steps: checkout, select Xcode 16.x, `xcodebuild -scheme LEO -destination 'platform=iOS Simulator,name=iPhone 15' test`.
  - Caches DerivedData and SPM cache.
  - Reports test results.
- README-style notes are **not** added — instructions for new contributors live in `conventions.md` (already present).

**How to build it**
1. Install `swiftformat` and `swiftlint` via Homebrew locally; vendor versions in CI (don't depend on `brew` in CI).
2. CI uses `mxcl/xcodebuild` action or raw shell. Prefer raw shell for transparency.
3. Pre-commit hook is opt-in (`scripts/install-hooks.sh` symlinks it). Don't force-install git hooks.
4. Confirm CI green on a deliberately-failing branch (e.g., a test asserting `false`) — it must turn red.

**Verification**
- [ ] Local: `./scripts/pre-commit.sh` exits 0 on a clean tree.
- [ ] CI: a green run on `main`.
- [ ] CI: a red run on a deliberately-failing branch (then revert).

---

### M0-T08 — Dev seeding + MetricKit + debug menu
- **Status:** DONE
- **Depends on:** M0-T05, M0-T06, M0-T07
- **Estimated effort:** M

**Goal**
A debug-only menu inside the app that seeds data, wipes data, exposes the design-system preview, and a MetricKit subscriber that captures crashes/non-fatals from M0 onward.

**What to build (acceptance criteria)**
- `Utilities/Dev/DebugMenu.swift` — a `View` shown only in `#if DEBUG`, accessible from a long-press on app icon (or a hidden gesture on a placeholder Today screen during M0; finalized location TBD in M1).
- Debug menu options:
  - "Seed 100 items" (mix of every Item kind and recurrence flavors).
  - "Wipe all data" (confirmation modal).
  - "Force CloudKit schema seed" (uses M0-T06 helper).
  - "Open design-system preview" (presents the M0-T03 preview).
  - "Show MetricKit log" (last 30 events).
  - App build/version readout, current iCloud account, container ID.
- `Utilities/Telemetry/MetricsSubscriber.swift` — conforms to `MXMetricManagerSubscriber`, persists payloads to a debug store, surfaces them in the debug menu.
- `Utilities/Dev/Seeder.swift` — pure logic that produces fixtures for every `Item` kind plus a couple of habits. No randomness in CI tests; randomness only when invoked from the debug menu.

**How to build it**
1. Wrap the entire `DebugMenu` in `#if DEBUG`. Strip from Release. Verify in a Release build.
2. MetricKit setup happens in `LEOApp.init`, also wrapped to be safe in tests.
3. "Wipe all data" deletes both SwiftData store and a CloudKit zone-clear (if user is signed in). The CloudKit clear is async and confirmed in UI.
4. Confirm the Release build no longer includes `DebugMenu` symbols — `nm` the binary briefly.

**Verification**
- [ ] Debug build: menu opens, all options work end-to-end.
- [ ] Seed inserts the documented mix of items; wipe removes them; sync to second sim follows.
- [ ] MetricKit subscriber receives test payloads when injected.
- [ ] Release build: menu is unreachable; `nm` shows no `DebugMenu` symbols.

**Notes / decisions**
*(empty)*

---

## Exit criteria for M0

Mark M0 complete only when **all** of the following hold:

- [ ] All eight tasks `DONE`.
- [ ] App launches on a real iPhone (not just simulator) with iCloud signed in.
- [ ] Two-device sync demonstrated.
- [ ] CI green on `main` for at least one push.
- [ ] No outstanding `BLOCKED` tasks.
- [ ] Debug menu functional in Debug, absent from Release.
- [ ] User has reviewed and signed off on M0 in chat.

When complete: update `IMPLEMENTATION_PLAN.md` to mark M0 Done and bump the current milestone to M1.
