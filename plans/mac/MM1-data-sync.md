# MM1 — Data Sync (CloudKit)

**Goal:** Items added on iPhone appear on Mac within ~60 seconds, and vice-versa, with no manual sync. Existing iOS users' data must migrate cleanly when CloudKit is enabled.

**Exit criteria:**
- Both targets use `cloudKitDatabase: .automatic` against `iCloud.com.theblueman.leo`.
- 48-hour soak test: ≥ 50 items pushed each direction without loss, duplicates, or corruption.
- A test iPhone with the prior `cloudKitDatabase: .none` store migrates to the synced store without data loss.
- CloudKit production schema is deployed (user clicks Deploy in CloudKit Dashboard after MM1-T03).

**This milestone touches `Persistence/`. Re-read Anti-divergence rule #6 and #9 in `MAC_AGENTS.md` before starting any task.**

## Summary checklist
- [ ] MM1-T01 — Enable `cloudKitDatabase: .automatic` in `PersistenceController` behind a flag
- [ ] MM1-T02 — Verify schema deploys to CloudKit Development environment
- [ ] MM1-T03 — Deploy schema to Production (BLOCKED on user action)
- [ ] MM1-T04 — Bidirectional sync smoke test (iPhone simulator ↔ Mac)
- [ ] MM1-T05 — Migration path for existing iOS users (TestFlight)

---

### MM1-T01 — Enable `cloudKitDatabase: .automatic` behind a flag
- **Status:** TODO
- **Depends on:** MM0-T08
- **Estimated effort:** M

**Goal**
Wire `cloudKitDatabase: .automatic` into `PersistenceController` but gate it behind a launch flag (`-LEOEnableCloudKitSync 1`) so we can roll back instantly if something breaks.

**What to build (acceptance criteria)**
- `PersistenceController.init` accepts `cloudKitEnabled: Bool` and chooses `.automatic` or `.none` accordingly.
- Default value: read from `UserDefaults.standard.bool(forKey: "LEOEnableCloudKitSync")`, defaulting to `true` once verified.
- During MM1-T01 development, default is `false`. Flip to `true` only after MM1-T04 passes.
- iOS and Mac both pass `cloudKitEnabled` through; default for the Mac target is also `false` initially.
- Schema unchanged. No new `Stored*` types. No new `SchemaV*`. (Critical — see anti-divergence rule #6.)
- `useInMemory: true` continues to force `.none`.

**How to build it**
1. Read current `PersistenceController.swift` (already done in conversation prep — re-read if cold).
2. Update `init`:
   ```swift
   init(useInMemory: Bool = false, cloudKitEnabled: Bool? = nil) {
       let enabled = cloudKitEnabled ?? UserDefaults.standard.bool(forKey: "LEOEnableCloudKitSync")
       logger.info("PersistenceController init (inMemory=\(useInMemory), ck=\(enabled))")
       let schema = Schema(SchemaV3.models)
       do {
           container = try Self.makeContainer(schema: schema, useInMemory: useInMemory, cloudKit: enabled)
           // …rest unchanged
       } // …
   }
   ```
3. Update `makeContainer`:
   ```swift
   private static func makeContainer(schema: Schema, useInMemory: Bool, cloudKit: Bool) throws -> ModelContainer {
       let ckMode: ModelConfiguration.CloudKitDatabase = (useInMemory || !cloudKit) ? .none : .automatic
       let config: ModelConfiguration
       if useInMemory {
           config = ModelConfiguration("LEO-inMemory", schema: schema,
                                       url: URL(fileURLWithPath: "/dev/null"),
                                       cloudKitDatabase: .none)
       } else {
           config = ModelConfiguration("LEO", schema: schema, cloudKitDatabase: ckMode)
       }
       return try ModelContainer(for: schema, migrationPlan: MigrationPlanV1.self, configurations: config)
   }
   ```
4. **Important:** the CloudKit container identifier is taken from the project entitlements; we do not pass it explicitly. The schema must already have a value for every property (CloudKit requires defaults or optionals). Audit `Stored*` types: every property must be optional OR have a default. If audit finds a non-optional / no-default property, **stop and ask user** — schema changes require approval.
5. Audit script: `grep -E "^\s*var [a-zA-Z]+: [A-Z][a-zA-Z]+$" LEO/Persistence/SwiftData/Models/Stored*.swift` — any line that matches is a non-optional with no default. (Best-effort grep; a manual review of each `Stored*.swift` is required.)
6. Document any audit findings in **Notes / decisions** below.
7. Build both schemes with `LEOEnableCloudKitSync=false` (default). Confirm no behavior change.

**Verification**
- [ ] `xcodebuild -scheme LEO build` passes.
- [ ] `xcodebuild -scheme LEO-Mac build` passes.
- [ ] With the flag off, iOS smoke test: existing seeded data still visible.
- [ ] Audit of `Stored*` confirms CloudKit compatibility (all properties optional or defaulted); findings documented in this task's notes.

**Notes / decisions**
_(record schema audit findings here)_

---

### MM1-T02 — Verify schema deploys to CloudKit Development
- **Status:** TODO
- **Depends on:** MM1-T01
- **Estimated effort:** M

**Goal**
With the flag flipped on locally, launch both apps signed in to the same Apple ID and confirm CloudKit Development picks up the schema automatically.

**What to build (acceptance criteria)**
- iOS Simulator (signed into iCloud test account) and Mac (signed into same iCloud test account) both run with `LEOEnableCloudKitSync=true`.
- After launching once on each, the CloudKit Dashboard for `iCloud.com.theblueman.leo` (Development env) shows record types: `StoredTask`, `StoredEvent`, `StoredReminder`, `StoredAlarm`, `StoredHabit`, `StoredHabitInstance`, `StoredTag`, `StoredRecurrenceRule`, `StoredOverride`, `StoredBodyProfile`, `StoredMeasurement`, `StoredWorkoutItem`, `StoredMealItem` (13 total — matches `SchemaV3.models`).
- No error in console mentioning `CKErrorPartialFailure`, `CKErrorBadDatabase`, or `CKErrorInvalidArguments`.
- An item added on iOS appears on Mac within 60 seconds.

**How to build it**
1. Enable the flag on both devices. The simplest way: edit the scheme's Launch Arguments → add `-LEOEnableCloudKitSync 1`. Do this for both `LEO` and `LEO-Mac` schemes.
2. Sign both the iOS simulator and Mac into the same Apple ID. In iOS Simulator: Settings → Sign in to your iPhone. In Mac: System Settings → Apple ID (the developer ID is fine; production iCloud users follow a different path in MM1-T05).
3. Launch the iOS app. Add 3 test items: a task, an event, a reminder. Quit.
4. Open CloudKit Dashboard → `iCloud.com.theblueman.leo` → Development → Schema. Confirm record types listed.
5. Launch Mac app. Wait up to 60s. Confirm items appear in the Mac UI (use the MM0 debug button or temporarily add a list in the sidebar that calls `appEnv.itemRepository.fetch()` and prints count).
6. Add an item on the Mac. Switch to iOS. Wait. Confirm appearance.
7. If anything fails: read the console for `CKError` codes and consult the SwiftData CloudKit troubleshooting list at the bottom of this file.

**Verification**
- [ ] All 13 record types present in CloudKit Dashboard Development.
- [ ] Items round-trip iPhone → Mac and Mac → iPhone within 60 seconds.
- [ ] No `CKError*` codes in console after 5 minutes of soak.
- [ ] Screenshot of CloudKit Dashboard schema attached to the commit message (file under `docs/cloudkit-schema-screenshots/`).

**Notes / decisions**
_(empty)_

---

### MM1-T03 — Deploy schema to Production
- **Status:** TODO
- **Depends on:** MM1-T02
- **Estimated effort:** S (but BLOCKED on user action)

**Goal**
Get the Mac and iOS apps talking to CloudKit Production so TestFlight builds (which use Production by default) sync correctly.

**What to build (acceptance criteria)**
- CloudKit Dashboard shows all 13 record types deployed to Production.
- A TestFlight or Release build of either app sees data from the same Apple ID across both devices.

**How to build it**
1. **STOP — this requires user action.** Open CloudKit Dashboard → `iCloud.com.theblueman.leo` → Development → Schema → click **Deploy Schema to Production**. Confirm in the modal.
2. Wait ~5 minutes for propagation.
3. Build a Release configuration of the Mac app: `xcodebuild -scheme LEO-Mac -configuration Release archive`. Run it. Verify it can sync with the iOS TestFlight build.
4. If deployment to Production fails (record type schema rejected), capture the error message and **stop and ask user**.

**Verification**
- [ ] User has clicked Deploy Schema to Production in CloudKit Dashboard.
- [ ] Production schema matches Development.
- [ ] Release-config Mac app syncs with an iOS Release-config (TestFlight) build.

**Notes / decisions**
_(user must paste deployment timestamp here)_

---

### MM1-T04 — Bidirectional sync smoke test
- **Status:** TODO
- **Depends on:** MM1-T03
- **Estimated effort:** L

**Goal**
Run a 48-hour soak to confirm sync robustness before any real user data lands.

**What to build (acceptance criteria)**
- Across 48 hours, a script-driven plus manual test pushes ≥ 50 items in each direction (add, update, complete, delete).
- Zero data loss, zero duplicate items, zero schema errors.
- Sync latency P50 ≤ 30s, P95 ≤ 5 minutes.
- Conflict behavior verified: editing the same item on both devices while offline, then both reconnecting, results in one survivor (last-write-wins by `updatedAt`).

**How to build it**
1. Write a test harness in `LEOMacTests/SyncSoakTests.swift` that:
   - Inserts 10 items via `appEnv.itemRepository.add`
   - Updates 10 items
   - Deletes 5
   - Polls `fetch()` until all changes are observed via the change-stream notification
2. On iOS, manually mirror the above via `Utilities/Dev/Seeder.swift` and observe on Mac.
3. Offline conflict test:
   - Disable network on both. Edit item X on both. Reconnect. Wait 2 min. Confirm both ends agree on the surviving version.
4. Log all sync events with `OSLog` subsystem `com.theblueman.leo.sync` for later debugging.
5. Document soak results in this task's notes.

**Verification**
- [ ] 48-hour soak completed without loss/duplicates.
- [ ] Conflict resolution confirmed.
- [ ] `LEOEnableCloudKitSync` flag defaulted to `true` in `PersistenceController` after this task passes.

**Notes / decisions**
_(soak results)_

---

### MM1-T05 — Migration for existing iOS users
- **Status:** TODO
- **Depends on:** MM1-T04
- **Estimated effort:** M

**Goal**
Existing iOS users currently use `cloudKitDatabase: .none` (data lives locally only). When they update to the version that enables sync, their existing local data must seed CloudKit; the Mac app then receives it.

**What to build (acceptance criteria)**
- On first launch with sync enabled, existing local items are written to CloudKit automatically by SwiftData (this is the framework default behavior — verify, don't implement).
- A test: create an iOS Simulator install with sync disabled, seed 30 items, then upgrade to the new build with sync enabled. Confirm all 30 items appear in CloudKit Dashboard and propagate to Mac.
- Document any user-visible delay (first-launch sync push can be several minutes for large datasets) in `Features/Settings/Views/CalendarSettingsView.swift` or a new `SyncStatusView`.

**How to build it**
1. Set up a test simulator with the current (unsync'd) build. Add 30 items via Seeder + manual.
2. Quit. Build the new (sync-enabled) version against the same simulator. Launch.
3. Open CloudKit Dashboard Production → confirm items appear within ~5 minutes.
4. Confirm Mac (signed into same Apple ID) receives them.
5. If items don't push, check `Persistence/CloudKit/SchemaSync.swift` and look for any iOS-only initial-sync code.
6. Add a one-time toast/sheet on first launch after upgrade: "Your data is syncing to iCloud. This may take a few minutes." (Use `UserDefaults` flag `leo.hasShownInitialCloudKitSyncToast`.)
7. If you discover that some data shape is incompatible (a `Stored*` field is required-non-optional and CloudKit rejects it), **stop and ask user**.

**Verification**
- [ ] Upgrade test: 30 pre-existing items survive the sync-enable.
- [ ] Items appear on Mac for the same Apple ID.
- [ ] First-launch toast shown exactly once.
- [ ] Master plan's "What still needs user action" updated: CloudKit Production deploy item is marked complete.

**Notes / decisions**
_(empty)_

---

## Troubleshooting reference (read if stuck)

### `CKErrorNotAuthenticated`
- Mac is not signed into iCloud, or the signed-in account has CloudKit disabled.
- Fix: System Settings → Apple ID → iCloud → enable iCloud Drive. CloudKit auth piggybacks on Drive.

### `CKErrorPartialFailure` with `CKErrorServerRecordChanged`
- Conflict: both devices wrote the same record while offline.
- Expected. SwiftData resolves via `updatedAt`. If you see actual data loss, **stop**.

### Schema reset (Development env only)
- CloudKit Dashboard → Development → Schema → Reset Development Schema. Use if you accidentally created a bad schema during MM1-T02. **Never reset Production.**

### "Schema mismatch detected"
- A `Stored*` type changed shape after first deploy.
- Schema is now incompatible. Options: (a) revert the change, or (b) bump SchemaV3 → SchemaV4 with a lightweight migration. **Stop and ask user.**

### Items aren't appearing across devices
1. Check both devices are signed into the same Apple ID.
2. Check `cloudKitDatabase: .automatic` is actually in effect — log `PersistenceController` initialization.
3. Check the device has network. CloudKit fails silently when offline (queues changes).
4. Check the CloudKit Dashboard — if the record is there but the other device doesn't see it, the issue is on the receiving side. Check the subscription list in Dashboard → Subscriptions.
5. Wait 5 minutes. Cold-start sync can be slow.

### Migration runs every launch
- Your `SchemaV*` checksum is changing between launches. Likely cause: a property's type or default value isn't deterministic.
- Re-read `feedback_swiftui_layout.md` memory: the V2→V3 duplicate checksum trap.
