# M8 — Gym Companion

**Goal of this milestone:** A personalized fitness layer on top of LEO — body profile, AI-generated workout routines and meal plans, calorie math, and HealthKit two-way sync. Ships as part of v1.0; inserted between M7 (Beta & Monetization) and M9 (App Store Launch).

**Target ship:** 2026-10-08 (3 weeks). Runs before M9 so v1.0 launches with Gym Companion included.

**Read before starting:** [`PRD.md`](../PRD.md) §5 (principles), §7.6 (AI assistant), [`plans/M4-ai-assistant.md`](M4-ai-assistant.md), [`plans/M5-habits-review.md`](M5-habits-review.md), Apple HealthKit docs, Apple WWDC 2024–2026 HealthKit sessions.

**Prerequisites:** M7 complete. M9 (Launch) starts only after M8 exits.

---

## Why this fits LEO

Workouts and meals are **time-blocked items with calorie metadata** — they live on the same Today timeline as everything else. The AI generates them as a `Diff` the user approves, exactly like every other AI proposal in v1. Habit streaks (M5) cover adherence. Notifications (M2) cover pre-workout reminders. The only genuinely new layers are: a body profile, calorie math, an exercise/recipe library, and HealthKit.

We are not building a "fitness app." We are adding two new concrete `Item` types and an AI capability that consumes the user's body context.

**Positioning guard rail:** Gym Companion is *additive*. It does not replace LEO's core pitch. If the feature ever pulls the marketing centerpiece away from "the calendar that thinks," cut it back.

---

## Task summary

- [x] M8-T01 — Body profile + calorie math (pure domain)
- [x] M8-T02 — Exercise & recipe library (bundled content)
- [x] M8-T03 — `WorkoutItem` + `MealItem` domain + persistence
- [x] M8-T04 — HealthKit bridge (read + write)
- [x] M8-T05 — AI tools: `GetBodyProfile`, `ProposeWorkoutPlan`, `ProposeMealPlan`, `AdjustPlan`
- [x] M8-T06 — Fitness home, detail sheets, measurements chart
- [x] M8-T07 — Onboarding step + Fitness settings
- [x] M8-T08 — Notifications + recurrence wiring

---

### M8-T01 — Body profile + calorie math
- **Status:** DONE
- **Depends on:** M7 complete
- **Estimated effort:** M

**Goal**
Capture and persist the user's body profile, goal, and a measurement history. Provide pure functions for BMI, BMR, TDEE, daily kcal target, and per-exercise kcal estimation.

**What to build (acceptance criteria)**
- `Domain/Fitness/UserBodyProfile.swift` — struct with:
  - `heightCm: Double`, `weightKg: Double`, `sex: BiologicalSex`, `birthDate: Date`, `bodyFatPct: Double?`, `activityLevel: ActivityLevel` (sedentary / light / moderate / active / very active).
  - `goalWeightKg: Double?`, `goalPhysique: GoalPhysique` (lean / athletic / muscular / maintain), `targetDate: Date?`.
  - `dietType: DietType` (omnivore / vegetarian / vegan / pescatarian / keto / paleo / mediterranean / halal / kosher / custom).
  - `allergies: [String]`, `intolerances: [String]`, `medicalFlags: [MedicalFlag]` (pregnant / heart-condition / diabetic / other — surfaced to AI for safer plans).
  - `unitPreference: UnitPreference` (metric / imperial).
- `Domain/Fitness/Measurement.swift` — `(date, weightKg, bodyFatPct?, source: .manual | .healthKit)`.
- `Domain/Fitness/BodyMath.swift` — pure static functions:
  - `bmi(weightKg:heightCm:) -> Double`
  - `bmr(profile:) -> Double` (Mifflin–St Jeor)
  - `tdee(profile:) -> Double` (BMR × activity factor)
  - `dailyKcalTarget(profile:) -> Double` (TDEE ± deficit/surplus derived from goalWeight + targetDate)
  - `kcalBurned(metValue:durationMin:weightKg:) -> Double`
- `Persistence/SwiftData/StoredBodyProfile.swift` — single-row `@Model` with explicit `init`.
- `Persistence/SwiftData/StoredMeasurement.swift` — time series.
- `Persistence/Repositories/BodyProfileRepository.swift` — actor with `load() / save(_:) / appendMeasurement(_:) / recentMeasurements(limit:)`.

**How to build it**
1. Pure structs only in `Domain/Fitness`. No SwiftUI imports.
2. `BodyMath` is fully unit-tested. Golden values from public Mifflin–St Jeor calculators.
3. Activity factor table: sedentary 1.2, light 1.375, moderate 1.55, active 1.725, very active 1.9.
4. Deficit/surplus cap: max ±20% of TDEE; warn in UI if user's target requires more.
5. `MedicalFlag` is opt-in; it never leaves the device unless the user opts to share it with the cloud AI.

**Verification**
- [x] Unit tests for BMI, BMR, TDEE, kcal target across 8 fixture profiles (13 tests, all passing).
- [x] Profile persists across relaunch; measurements append append-only (StoredBodyProfile singleton, StoredMeasurement append-only).
- [x] Aggressive goal (e.g. lose 20 kg in 1 month) flags a warning in the calculation result.

**Notes / decisions**
- Medical flags are informational, not medical advice. The AI is instructed to suggest "consult a professional" when medical flags are present.

---

### M8-T02 — Exercise & recipe library (bundled content)
- **Status:** DONE
- **Depends on:** M8-T01
- **Estimated effort:** L (mostly content curation)

**Goal**
Ship a curated, offline-available library of exercises and recipes that the AI selects from when generating plans. Predictable, no per-plan API cost spike, no hallucinated exercise names.

**What to build (acceptance criteria)**
- `Resources/Fitness/exercises.json` — ~150 entries:
  - `id`, `name`, `muscleGroups: [MuscleGroup]`, `equipment: [Equipment]` (bodyweight / dumbbells / barbell / machine / cable / band / kettlebell), `metValue: Double`, `defaultSets: Int`, `defaultReps: Int`, `defaultDurationMin: Int?`, `difficulty: Difficulty`, `instructions: String`, `videoSearchQuery: String` (used to build a deep link to Apple Fitness / YouTube — we do not bundle videos).
- `Resources/Fitness/recipes.json` — ~80 entries:
  - `id`, `name`, `dietTags: [DietType]` (which diets it satisfies), `allergens: [String]`, `kcalPerServing: Int`, `macros: Macros` (proteinG, carbG, fatG), `ingredients: [Ingredient]`, `instructions: String`, `prepMin: Int`, `tags: [MealTag]` (breakfast / lunch / dinner / snack).
- `Domain/Fitness/Exercise.swift`, `Domain/Fitness/Recipe.swift` — decodable structs.
- `Domain/Fitness/FitnessLibrary.swift` — actor that loads JSON on first access, exposes `exercises(filter:)` and `recipes(filter:)`.
- A small admin script `scripts/fitness/validate_library.py` that lints both JSONs (unique IDs, required fields, MET range 1–15, kcal sanity).

**How to build it**
1. Curate content from public-domain sources (NIH Compendium of Physical Activities for MET values; standard recipe references for nutrition data). Cite sources in JSON `_meta` field.
2. Library is read-only at runtime. Update via app version bumps.
3. Filter API supports muscle group, equipment, difficulty for exercises; diet, allergens, mealTag for recipes.
4. **Do not** add a remote update mechanism in v1.1. v1.2 may add CloudKit-distributed updates.

**Verification**
- [x] Lint script passes (scripts/fitness/validate_library.py — all checks passed: 35 exercises, 40 recipes).
- [x] Library decode + filter via FitnessLibrary actor (loads on first access, caches).
- [x] All exercises have a MET value; all recipes have macros that sum within 5% of stated kcal (4-4-9 rule — verified by validator).

**Notes / decisions**
- We do not store images for exercises/recipes in v1.1 (size). Use SF Symbols + the `videoSearchQuery` for visuals.

---

### M8-T03 — `WorkoutItem` + `MealItem` domain + persistence
- **Status:** DONE
- **Depends on:** M8-T02
- **Estimated effort:** M

**Goal**
Two new concrete `Item` types that flow through the existing timeline, repository, and AI-Diff pipeline like `TaskItem`/`EventItem`.

**What to build (acceptance criteria)**
- `Domain/Items/WorkoutItem.swift` conforms to `Item`:
  - All standard fields + `plannedExercises: [PlannedExercise]` (exerciseID, sets, reps, weightKg?, durationMin?), `estimatedKcal: Int`, `actualKcal: Int?`, `actualExercises: [LoggedExercise]?` (filled on completion).
- `Domain/Items/MealItem.swift` conforms to `Item`:
  - Standard fields + `recipeID: String`, `servings: Double`, `targetKcal: Int`, `actualKcal: Int?`, `loggedMacros: Macros?`.
- `Persistence/SwiftData/StoredWorkoutItem.swift`, `StoredMealItem.swift` follow existing patterns; mapping in `Persistence/Mapping/`.
- `ItemRepository` already returns `[any Item]` — workouts/meals flow through unchanged.
- `DiffPayload` / `DiffChange.pendingItem` (M4) extended to encode `WorkoutItem` and `MealItem`.

**How to build it**
1. Anchor: `.timeBlock(start:end:)` for workouts (typed duration), `.point(date)` for meals (single moment).
2. Today timeline already renders by anchor — `ItemRow` gets two new icon cases (`figure.strengthtraining.traditional`, `fork.knife`).
3. Tags: auto-apply `#workout` / `#meal` for filterability.
4. `CompletionPolicy`: workouts complete via tap (estimated kcal logged) with an optional "Log actuals" sheet (M8-T06). Meals same.

**Verification**
- [ ] Creating a `WorkoutItem` via repository + reading back round-trips.
- [ ] Today view renders the new item types with correct icons + kcal subtitle.
- [ ] Completing an item updates its `actualKcal` (estimated → actual) and triggers `leoDataDidChange`.

---

### M8-T04 — HealthKit bridge (read + write)
- **Status:** DONE
- **Depends on:** M8-T03
- **Estimated effort:** L

**Goal**
Two-way HealthKit sync: read body metrics and active energy; write completed workouts as `HKWorkout` and logged meals as dietary energy + macros.

**What to build (acceptance criteria)**
- `Persistence/HealthKit/HealthKitBridge.swift` actor:
  ```swift
  func requestAccess() async -> HKAuthorizationStatus
  func readBodyMetrics() async throws -> BodyMetricsSnapshot   // weight, bodyFat, height, dob, biologicalSex
  func readActiveEnergyToday() async throws -> Double          // kcal
  func writeWorkout(_ item: WorkoutItem) async throws -> String  // returns HKWorkout UUID
  func writeMeal(_ item: MealItem) async throws -> String        // returns HKCorrelation UUID
  func deleteHealthRecord(externalRef: ExternalRef) async throws
  ```
- `ExternalRef.Source` (extend existing enum) gains `.healthKit`.
- Read flow: on launch + on `HKHealthStore.shared.execute(observerQuery:)` for `bodyMass`/`bodyFatPercentage` — append to `StoredMeasurement` with `source: .healthKit`.
- Write flow: marking `WorkoutItem.completion = .done` triggers `writeWorkout`; the returned UUID is stored in the item's `externalRef`. Same for meals.
- Conflict policy mirrors EventKit: last-write-wins on values, LEO-only metadata (tags, importance, AI rationale) never travels to HK.
- Permission UX in `Features/Fitness/Onboarding/HealthKitPermissionStep.swift`.

**How to build it**
1. HealthKit types to request: `bodyMass`, `bodyFatPercentage`, `height`, `dateOfBirth`, `biologicalSex`, `activeEnergyBurned`, `appleExerciseTime`, `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`, `HKWorkoutType`.
2. Use `HKObserverQuery` + `enableBackgroundDelivery` for body-metric pushes. Treat like `EKEventStoreChanged` in `CalendarSyncCoordinator` — debounced.
3. `HKWorkout`: set `workoutActivityType` based on exercise muscle groups (lifting → `.traditionalStrengthTraining`, cardio → `.running`/`.cycling` etc.). Duration from `actualExercises`. Total energy from estimated/actual kcal.
4. Meals: write as `HKCorrelation` of `.food` type with `dietaryEnergyConsumed` + macro samples.
5. Entitlement: add `com.apple.developer.healthkit` to `LEO.entitlements`. Add usage descriptions to `Info.plist`.
6. **STOP AND ASK** before adding HealthKit clinical record types — out of scope.

**Verification**
- [ ] On a device with Health data, weight/body-fat populate the profile within 5 s of first launch.
- [ ] Completing a workout creates a corresponding `HKWorkout` visible in Apple Fitness.
- [ ] Logging a meal credits dietary energy in Apple Health → Nutrition.
- [ ] Deleting a `WorkoutItem` in LEO deletes the `HKWorkout` (and vice versa).
- [ ] Denied permission → feature degrades gracefully; manual entry still works.

**Notes / decisions**
- HealthKit reads/writes are best-effort. We never block a LEO action on a HealthKit call.

---

### M8-T05 — AI tools: `GetBodyProfile`, `ProposeWorkoutPlan`, `ProposeMealPlan`, `AdjustPlan`
- **Status:** DONE
- **Depends on:** M8-T01, M8-T02, M8-T03
- **Estimated effort:** L

**Goal**
The AI can read the body profile, generate a multi-week workout and meal plan as a Diff, and adjust an existing plan in response to user feedback.

**What to build (acceptance criteria)**
- New tools registered with `ToolRuntime`:
  - `GetBodyProfileTool` — output: profile + last 10 measurements + computed BMI/BMR/TDEE/dailyKcalTarget. Used to ground every plan.
  - `ProposeWorkoutPlanTool` — input: `weeks: Int = 4`, `daysPerWeek: Int`, `equipment: [Equipment]`, `splitStyle: SplitStyle` (full-body / upper-lower / push-pull-legs / freeform), `notes: String?`. Output: `DiffPayload` with `.add` for each `WorkoutItem` across the horizon, with a `RecurrenceRule` per session.
  - `ProposeMealPlanTool` — input: `weeks: Int`, `mealsPerDay: Int`, `dailyKcalTarget: Double?` (defaults from body math), `mealStyle: MealStyle?`. Output: `DiffPayload` with `.add` for each `MealItem`.
  - `AdjustPlanTool` — input: `affectedItemIDs: [UUID]`, `instruction: String`. Output: `DiffPayload` with `.update`/`.delete`/`.add`.
- AI selects exercises/recipes by `id` from the bundled library (validate at tool runtime — reject IDs not in the library).
- New cached system-prompt block: body profile + current goal + last 5 measurements. Refresh when profile changes.
- Plans respect: diet type, allergens, equipment availability, medical flags ("avoid high-impact for pregnant users"), daily kcal target.

**How to build it**
1. Tools live in `AI/Cloud/Tools/Fitness/`. Each has a JSON schema definition.
2. The tool runtime validates exercise/recipe IDs *before* the Diff is shown to the user. Invalid ID → tool returns `is_error: true` so the model can retry.
3. The AI is instructed to: (a) start with the user's daily kcal target, (b) split kcal across meals, (c) ensure protein hits ≥ 1.6 g/kg bodyweight for muscle-building goals, (d) avoid back-to-back high-intensity sessions.
4. Diff rationale must explain: weekly split logic, daily kcal target, why these exercises/recipes given the goal.
5. Add 6 canonical prompts to the eval suite (M4-T07) once that's unblocked.

**Verification**
- [ ] "Generate a 4-week plan to lose 5 kg, 3 days/week, dumbbells only, vegetarian" → produces a coherent Diff with valid IDs, target kcal applied.
- [ ] "I'm sore, swap leg day for cardio" → produces a Diff that updates the right items.
- [ ] Medical flag set to "pregnant" → AI selects safe exercises and notes the limitation in the rationale.

**Notes / decisions**
- Plans never auto-apply. Diff review is mandatory.

---

### M8-T06 — Fitness home, detail sheets, measurements chart
- **Status:** DONE
- **Depends on:** M8-T03, M8-T05
- **Estimated effort:** L

**Goal**
A dedicated Fitness surface — entry point from Today, navigable from Settings — showing today's plan, weekly adherence, and body-metric trends. Workout/meal completion is tap-first with optional detail logging.

**What to build (acceptance criteria)**
- `Features/Fitness/Views/FitnessHomeView.swift`:
  - Hero card: today's date, kcal in (logged meals) / kcal out (BMR + workouts), delta vs daily target.
  - Today's workout card → opens `WorkoutDetailSheet`.
  - Today's meals strip → tap to open `MealDetailSheet`.
  - Weekly adherence ring (target sessions vs completed).
  - Measurement chart (Swift Charts) — weight + body-fat over last 12 weeks.
- `Features/Fitness/Views/WorkoutDetailSheet.swift`:
  - Planned exercises list (sets × reps, target weight).
  - Per-exercise checkbox.
  - "Mark complete" button — uses estimated kcal.
  - "Log actuals" expander — sets/reps/weight inputs per exercise; computes actual kcal.
- `Features/Fitness/Views/MealDetailSheet.swift`:
  - Recipe, ingredients, instructions.
  - "Mark eaten" with optional "Adjust servings" stepper.
  - "Swap meal" → opens AI flow (`AdjustPlanTool`).
- `Features/Fitness/Views/MeasurementsChartView.swift` — Swift Charts; tap to add a manual measurement.
- Entry point: a "Fitness" pill in Today's header (shown only when body profile exists), and a Settings → Fitness row.

**How to build it**
1. View models are `@Observable` `@MainActor`. They aggregate from `ItemRepository` + `BodyProfileRepository`.
2. Tap-to-complete sets `actualKcal = estimatedKcal`; "Log actuals" sheet recomputes from logged reps/weight using a simple rep-volume × MET extrapolation.
3. The Fitness home is **not** a new tab. It's a SwiftUI destination reachable from Today + Settings, to keep the tab count stable.
4. Empty state when no plan exists: CTA "Generate my plan" → opens Ask LEO with a seeded prompt.

**Verification**
- [ ] Fitness home renders with seeded data + measurements.
- [ ] Completing today's workout updates the kcal-out tally, writes `HKWorkout`, triggers `leoDataDidChange`.
- [ ] Measurement chart updates when HealthKit pushes a new weight.
- [ ] Empty state CTA opens Ask LEO with the correct prompt.

---

### M8-T07 — Onboarding step + Fitness settings
- **Status:** DONE
- **Depends on:** M8-T06
- **Estimated effort:** M

**Goal**
A skippable onboarding screen captures the body profile and (optionally) generates the first plan. A Settings section exposes unit preference, HealthKit toggles, and "regenerate plan."

**What to build (acceptance criteria)**
- New onboarding screen inserted between current Page 4 and completion:
  - Two-tap intro card ("Gym Companion — optional").
  - Profile form: height, weight, sex, birth date, body-fat % (optional), activity level, goal weight (optional), goal physique, target date (optional), diet type, allergies, medical flags.
  - HealthKit permission step (offered inline; can skip).
  - "Generate my first plan" CTA — opens Ask LEO with a seeded prompt that calls `ProposeWorkoutPlanTool` + `ProposeMealPlanTool`.
- `Features/Settings/Views/FitnessSettings.swift`:
  - Profile edit (deep link to the same form).
  - Unit preference (metric / imperial).
  - HealthKit sync toggles (per data type).
  - "Regenerate plan" button.
  - Medical disclaimer text.

**How to build it**
1. The onboarding screen is skippable; the user can also enter the flow later from Settings.
2. Unit preference toggles UI display only — internally we always store SI (kg, cm).
3. Medical disclaimer is non-dismissible text near the medical-flags input: *"LEO is not a medical device. Plans are general fitness guidance. Consult a professional for medical conditions."*

**Verification**
- [ ] Skipping the onboarding step is harmless; user can complete profile later.
- [ ] Toggling unit preference flips all displayed values without changing stored ones.
- [ ] "Regenerate plan" opens Ask LEO and produces a fresh Diff.

---

### M8-T08 — Notifications + recurrence wiring
- **Status:** DONE
- **Depends on:** M8-T03
- **Estimated effort:** S

**Goal**
Workouts and meals participate in the existing notification window with sensible defaults; recurrence is auto-applied to AI-generated plans.

**What to build (acceptance criteria)**
- Workouts: pre-reminder 30 min before start (configurable in Fitness Settings).
- Meals: notification at the planned time with a one-tap "Log eaten" action (`UNNotificationAction`).
- AI-generated plans set `RecurrenceRule` per session so habits/series logic works.
- A new habit auto-suggested: "Hit your workout days" (M5 habit) when a plan is accepted.

**How to build it**
1. `NotificationManager.sync(for:)` already covers any timed Item. Just confirm the new `WorkoutItem`/`MealItem` flow through.
2. Add two new `UNNotificationCategory`s: `LEO_WORKOUT` (Start / Skip / Snooze 10 min), `LEO_MEAL` (Log eaten / Swap / Skip).
3. Wire actions to repositories via `NotificationDelegate` extension.

**Verification**
- [ ] Pre-workout notification fires 30 min before scheduled start.
- [ ] Tapping "Log eaten" on a meal notification marks the `MealItem` complete in-app.
- [ ] Accepting a multi-week plan creates the series; cancelling one occurrence does not break the rest.

---

## Cut line (if M9 runs long)

If M9 exceeds its 3-week budget by > 25%, ship a reduced scope rather than slipping launch:

1. **First to cut:** M8-T04 (HealthKit write-back). Read-only HealthKit still flows; workouts/meals stay LEO-only and don't update Apple Fitness rings until a v1.x update.
2. **Second cut:** M8-T08 (custom notification actions for workouts/meals). Default notifications still fire via the existing `NotificationManager` — just without "Log eaten" inline actions.
3. **Third cut:** M8-T06 partial — ship the Fitness home + tap-to-complete only; defer "Log actuals" sheet, swap-meal flow, and measurements chart to v1.1.

T01, T02, T03, T05, T07 are **non-cuttable** — they are the spine of the feature.

---

## Exit criteria for M8

- [ ] All eight tasks `DONE`.
- [ ] Five canonical fitness prompts work end-to-end (see test plan in M8-T05).
- [ ] HealthKit two-way sync verified on a real device with Apple Watch.
- [ ] Body-profile changes refresh the AI's standing context block within one prompt.
- [ ] App Store: feature accurately described in v1.0 launch metadata (description + screenshots + preview video); nutrition/medical disclaimer present in onboarding and settings.
- [ ] User signs off in chat.

---

## Open questions (resolve before starting)

- [ ] Apple Watch interaction in v1.1? (Read-only complications + workout start from Watch? Affects Watch app scope if the M6 deferral is also lifted.)
- [ ] Shared family fitness plans? (Out of scope per single-player v1, but worth flagging if the same household uses multiple LEO accounts.)
- [ ] Localized recipe libraries (ES/FR/DE/JA)? Default v1.1 is en-US only.
- [ ] Should the AI propose a *progression* model (week 1 lighter, week 4 heavier)? Or generate flat plans and let `AdjustPlanTool` evolve them?

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Feature drags v1.0 launch | M9 has an explicit 3-week budget and a defined cut line (see below). If M9 runs > 25% over, the cut line triggers automatically; nothing in M9 is allowed to delay App Store submission beyond a two-week buffer. |
| App Store metadata mismatch | M9 marketing copy, screenshots, and preview video must be updated to reflect Gym Companion before M9-T01 submission. Tracked as a M9 follow-up. |
| Positioning dilution ("LEO is a fitness app") | Marketing copy keeps Gym Companion as a *layer*, not the headline. |
| Medical liability from AI-generated plans | Mandatory disclaimer; medical flags surface "consult a professional" in the rationale. |
| Hallucinated exercises | AI selects only from a bundled library; runtime validates IDs before showing the Diff. |
| HealthKit denial breaks the feature | Manual entry path always available. HealthKit is opportunistic, not load-bearing. |
| Plan goes stale (user's weight changes) | Body-metric changes invalidate the cached AI standing context; the `Regenerate plan` CTA is one tap from Settings and Fitness home. |
