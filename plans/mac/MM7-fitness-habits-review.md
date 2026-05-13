# MM7 — Fitness (Gym Companion), Habits Polish, Weekly Review

**Goal:** Gym Companion ports cleanly to Mac with the same plan-generation, workout/meal detail, and measurements chart. Habits gets weekly-heatmap polish on Mac. Weekly Review surfaces in a dedicated window.

**Exit criteria:**
- Fitness sidebar section reachable (add to `SidebarSection`).
- Generate plan flow works end-to-end on Mac (body profile → plan preferences → AI proposal → diff review → accept).
- Workout/meal detail open in their own windows (multi-window) so users can keep a workout open while browsing today.
- Measurements chart renders with `Charts`.
- HealthKit two-way sync: macOS has limited HealthKit — document and degrade gracefully.
- Weekly Review window with the AI-generated insights from iOS.

## Summary checklist
- [ ] MM7-T01 — Add `.fitness` sidebar section + routing
- [ ] MM7-T02 — `MacFitnessHomeView`
- [ ] MM7-T03 — `MacGeneratePlanFlowView`
- [ ] MM7-T04 — `MacWorkoutDetailWindow` + `MacMealDetailWindow` (own windows)
- [ ] MM7-T05 — `MacMeasurementsChartView`
- [ ] MM7-T06 — `MacWeeklyReviewView` (own window)

---

### MM7-T01 — Add `.fitness` sidebar section
- **Status:** TODO
- **Depends on:** MM3-T05
- **Estimated effort:** S

**Goal**
Add `.fitness` to `SidebarSection` and route it in `MacContentPane`.

**What to build (acceptance criteria)**
- `SidebarSection` gains `case fitness`.
- Sidebar shows "Fitness" under "Tools" section with `figure.run` icon.
- `MacContentPane` switches `.fitness → MacFitnessHomeView()`.
- Keyboard shortcut `⌘6` (extend View menu shortcuts).

**How to build it**
1. Add the case to the enum.
2. Update `MacSidebar` and `MacCommands.sectionShortcut(.fitness)` with `⌘6`.
3. Add `MacFitnessHomeView()` placeholder (real impl in MM7-T02).

**Verification**
- [ ] `⌘6` selects Fitness.
- [ ] Sidebar shows it under Tools.

**Notes / decisions**
_(empty)_

---

### MM7-T02 — `MacFitnessHomeView`
- **Status:** TODO
- **Depends on:** MM7-T01
- **Estimated effort:** L

**Goal**
Port `FitnessHomeView` (iOS Gym Companion landing page).

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Fitness/MacFitnessHomeView.swift` shows:
  - Body profile summary card (height, weight, goal).
  - Today's workout (or "Rest day") with a "Open" button → workout detail window (MM7-T04).
  - Today's meals (3–5 cards) → meal detail windows.
  - Measurements quick chart (last 30 days, mini chart).
  - "Generate new plan" button → MM7-T03 flow.
- Reuses `FitnessHomeViewModel` (existing) unchanged.

**How to build it**
1. Read `LEO/Features/Fitness/Views/FitnessHomeView.swift` and `FitnessHomeViewModel.swift`.
2. Build the Mac view using a `ScrollView { LazyVGrid(...) }` for the two-column card layout on a wide window.
3. Workout/meal cards: tap → open in new window via `@Environment(\.openWindow)` with window IDs (defined in MM7-T04).
4. Replace `MacContentPane.fitness → MacFitnessHomeView()`.

**Verification**
- [ ] Fitness home loads with body profile + today's workout + today's meals.
- [ ] Cards clickable → open in new windows.
- [ ] Generate plan launches the flow.

**Notes / decisions**
_(empty)_

---

### MM7-T03 — `MacGeneratePlanFlowView`
- **Status:** TODO
- **Depends on:** MM7-T02
- **Estimated effort:** L

**Goal**
Port the multi-step plan-generation flow.

**What to build (acceptance criteria)**
- `MacGeneratePlanFlowView` runs through: confirm body profile → preferences (split, days/week, dietary restrictions) → AI generates proposal → user reviews diff (uses `MacDiffReviewPane`) → accept.
- Same logic as iOS `GeneratePlanFlowView`; UI is a multi-step `NavigationStack` in a sheet.
- Calls into existing `FitnessPlanGenerator.swift` and AI tools `ProposeWorkoutPlanTool` / `ProposeMealPlanTool`.
- AI response routes through `ToolRuntime` and surfaces in the diff review pane (or as a sheet on top of the flow if that reads cleaner — TBD during build).

**How to build it**
1. Read `LEO/Features/Fitness/Views/GeneratePlanFlowView.swift`.
2. Port step-by-step; each step is its own SwiftUI view.
3. Reuse `BodyProfileRepository`, `FitnessPlanGenerator`, `PlanPreferences` — all platform-neutral.
4. On generation: show progress indicator while the tool runs; show diff review when complete.

**Verification**
- [ ] Flow walks through all steps.
- [ ] AI tool call succeeds.
- [ ] Generated workouts + meals appear after accept.

**Notes / decisions**
_(empty)_

---

### MM7-T04 — `MacWorkoutDetailWindow` + `MacMealDetailWindow`
- **Status:** TODO
- **Depends on:** MM7-T02
- **Estimated effort:** M

**Goal**
Open workout and meal details in dedicated windows so users can keep them open alongside Today.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Fitness/MacWorkoutDetailWindow.swift` and `MacMealDetailWindow.swift`.
- Each is a `WindowGroup("Workout", for: UUID.self) { id in ... }` registered in `LEOMacApp.body`.
- Body adapts iOS `WorkoutDetailSheet` / `MealDetailSheet`.
- Cards in `MacFitnessHomeView` open via `openWindow(id: "workout", value: workoutID)`.

**How to build it**
1. Register window groups in `LEOMacApp.body`:
   ```swift
   WindowGroup("Workout", id: "workout", for: UUID.self) { $id in
       if let id = id.wrappedValue {
           MacWorkoutDetailWindow(workoutID: id)
               .environment(appEnvironment!)
       }
   }
   .defaultSize(width: 700, height: 800)

   WindowGroup("Meal", id: "meal", for: UUID.self) { $id in
       if let id = id.wrappedValue {
           MacMealDetailWindow(mealID: id)
               .environment(appEnvironment!)
       }
   }
   .defaultSize(width: 600, height: 700)
   ```
2. Build the views by adapting iOS sheets.

**Verification**
- [ ] Click a workout card → new window opens.
- [ ] Multiple workout windows can be open simultaneously.
- [ ] Closing the main app closes child windows.

**Notes / decisions**
_(empty)_

---

### MM7-T05 — `MacMeasurementsChartView`
- **Status:** TODO
- **Depends on:** MM7-T02
- **Estimated effort:** S

**Goal**
Port `MeasurementsChartView` — uses Swift Charts which is cross-platform.

**What to build (acceptance criteria)**
- `MacMeasurementsChartView` renders weight, body-fat %, etc., over time.
- Range picker: 30 days, 90 days, 1 year.
- HealthKit pull: on Mac, HealthKit is more limited (no continuous read). Use what's available; fall back to manual entry.

**How to build it**
1. Read `LEO/Features/Fitness/Views/MeasurementsChartView.swift`.
2. Port directly; `Charts` framework works on macOS 14+.
3. HealthKit Mac caveat: `HKHealthStore` is available on macOS 13+, but with reduced capabilities (no daily background updates). Document in Settings → Fitness.

**Verification**
- [ ] Chart renders with seeded measurements.
- [ ] Range picker works.

**Notes / decisions**
_(empty)_

---

### MM7-T06 — `MacWeeklyReviewView`
- **Status:** TODO
- **Depends on:** MM7-T05
- **Estimated effort:** M

**Goal**
Port `WeeklyReviewView` to Mac, with the AI-generated insights from `WeeklyReviewGenerator`.

**What to build (acceptance criteria)**
- `MacWeeklyReviewView` opens in its own window (`WindowGroup("Weekly Review", id: "review")`).
- Generates the review when first opened (or on demand).
- Sections: This week, Last week, Streaks, Recommendations.
- Reuses `WeeklyReviewGenerator.swift` unchanged.
- Reachable from menu bar: Window → Weekly Review.

**How to build it**
1. Read `LEO/Features/Review/Views/WeeklyReviewView.swift`.
2. Port directly. Layout in a tall window.
3. Add window registration and menu bar entry.

**Verification**
- [ ] "Window → Weekly Review" opens.
- [ ] Generation succeeds (uses Claude).
- [ ] Sections populated.

**Notes / decisions**
_(empty)_
