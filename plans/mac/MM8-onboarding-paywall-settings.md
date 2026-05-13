# MM8 — Onboarding, Paywall, Settings

**Goal:** First-launch flow on Mac (welcome → permissions → sign in to iCloud check → gym opt-in → paywall). Settings scene fully populated with every iOS Settings pane reproduced.

**Exit criteria:**
- First-launch experience matches iOS feel.
- All entitlement permissions requested up front in order (notifications, calendar, reminders, microphone, location, accessibility for global hotkey).
- StoreKit 2 paywall works on Mac (sandbox + production).
- Settings tabs each fully implemented.

## Summary checklist
- [ ] MM8-T01 — `MacOnboardingFlow` (welcome → permissions → gym opt-in)
- [ ] MM8-T02 — Accessibility permission step (for global hotkey)
- [ ] MM8-T03 — `MacPaywallView` + StoreKit on macOS verification
- [ ] MM8-T04 — Settings → General + Sync panes
- [ ] MM8-T05 — Settings → AI + Fitness + Feedback panes
- [ ] MM8-T06 — Settings → Keyboard pane (reads `MacKeyboardShortcuts.all`)

---

### MM8-T01 — `MacOnboardingFlow`
- **Status:** TODO
- **Depends on:** MM7-T06
- **Estimated effort:** L

**Goal**
Port `OnboardingFlow` to Mac. Multi-page horizontal flow inside a fixed-size window. Sets `UserDefaults.hasCompletedOnboarding = true` at the end.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Onboarding/MacOnboardingFlow.swift` shows pages:
  1. Welcome (value prop, illustration).
  2. Capture (how quick-add works, mentions global hotkey).
  3. Plan (AI assistant teaser).
  4. Sync (iCloud account check + opt-in).
  5. Notifications + Calendar + Reminders + Location + Microphone permissions (one combined screen, request in sequence).
  6. Gym opt-in.
  7. Paywall (MM8-T03; can be skipped to free tier).
- Window is fixed-size 720 × 540 during onboarding, no sidebar/inspector chrome.
- "Get started" button on last page sets `hasCompletedOnboarding = true` and transitions to `MacShellView`.

**How to build it**
1. Read `LEO/Features/Onboarding/Views/OnboardingFlow.swift` and `OnboardingPageGym.swift`.
2. Port each page. Use `TabView` with `.tabViewStyle(.page)` or a custom horizontal pager.
3. For permission requests: each request is a button that, when pressed, calls the relevant manager (`appEnv.notificationManager.requestAuthorization()`, `EKEventStore.requestFullAccessToEvents`, `CLLocationManager.requestWhenInUseAuthorization()`, `SFSpeechRecognizer.requestAuthorization`).
4. On the iCloud check page: verify `FileManager.default.ubiquityIdentityToken != nil`. If nil, show a hint linking to System Settings.

**Verification**
- [ ] First launch shows onboarding window, all 7 pages.
- [ ] Permission prompts appear at the right step.
- [ ] iCloud detection works.
- [ ] After completion, regular shell appears; relaunching does not re-trigger onboarding.

**Notes / decisions**
_(empty)_

---

### MM8-T02 — Accessibility permission step
- **Status:** TODO
- **Depends on:** MM8-T01, MM4-T03
- **Estimated effort:** S

**Goal**
A separate step inside the onboarding (or a post-onboarding nag) prompts the user to grant Accessibility access so the global hotkey works.

**What to build (acceptance criteria)**
- Page in onboarding (or post-onboarding sheet): "Enable Quick Capture from anywhere".
- Button: "Open System Settings". Opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- Detect status with `AXIsProcessTrusted()`; show check mark when granted.
- Can skip — the rest of the app works without it; only global hotkey is degraded.

**How to build it**
1. Use `AXIsProcessTrustedWithOptions`:
   ```swift
   let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
   let trusted = AXIsProcessTrustedWithOptions(opts)
   ```
2. Open System Settings:
   ```swift
   NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
   ```
3. Poll status every 2s while the page is visible; show check when granted.

**Verification**
- [ ] Permission step shows in onboarding.
- [ ] Open System Settings link works.
- [ ] Status check correctly reflects granted/not.

**Notes / decisions**
_(empty)_

---

### MM8-T03 — `MacPaywallView` + StoreKit on macOS verification
- **Status:** TODO
- **Depends on:** MM8-T01
- **Estimated effort:** L

**Goal**
Port `PaywallView` to Mac, verify StoreKit 2 IAP flow (sandbox) works on macOS, decide whether iOS/macOS IAP products are shared.

**What to build (acceptance criteria)**
- `LEO/PlatformMac/Features/Paywall/MacPaywallView.swift` renders:
  - Hero pitch.
  - Plans (monthly, annual, lifetime — same as iOS).
  - "Continue with free" link.
  - Purchase button.
- Uses `StoreClient` (existing) unchanged.
- StoreKit 2 sandbox transaction succeeds with the developer sandbox account on Mac.
- Decision documented: are IAP products shared between iOS and macOS, or separate? Test with App Store Connect's "unify products" option.

**How to build it**
1. Read `LEO/Features/Paywall/Views/PaywallView.swift` and `LEO/Monetization/StoreClient.swift`.
2. Port the Mac view. Layout: wider hero, side-by-side plan cards.
3. Test purchase with a sandbox account on macOS.
4. **STOP and ask user** about the App Store Connect product setup before flipping anything in production.

**Verification**
- [ ] Paywall renders all three plans.
- [ ] Sandbox purchase completes; `ProGate.isPro` returns true on Mac.
- [ ] Same Apple ID's purchase on iOS unlocks on Mac (if products unified).

**Notes / decisions**
_(empty)_

---

### MM8-T04 — Settings → General + Sync panes
- **Status:** TODO
- **Depends on:** MM8-T03
- **Estimated effort:** M

**Goal**
Build the General and Sync panes in `MacSettingsScene` (replace placeholders).

**What to build (acceptance criteria)**
- General pane: app version, default Today mode (list vs timeline), week-start day, time format (12h/24h), reset onboarding (dev).
- Sync pane: iCloud status (account name, last successful sync timestamp), "Sync now" button, "Reset local cache" button (destructive, confirm dialog).
- Both panes use `Form` layout with sections.

**How to build it**
1. Each pane is a separate file under `PlatformMac/Features/Settings/`.
2. General reads/writes `UserDefaults`/`AppStorage`.
3. Sync pane reads from `PersistenceController` (last sync) and calls `appEnv.calendarSyncCoordinator.syncOnForeground()`.

**Verification**
- [ ] Settings opens with new content in General and Sync tabs.
- [ ] Changing default Today mode and reopening Today reflects.

**Notes / decisions**
_(empty)_

---

### MM8-T05 — Settings → AI + Fitness + Feedback panes
- **Status:** TODO
- **Depends on:** MM8-T04
- **Estimated effort:** M

**Goal**
Build the AI, Fitness, and Feedback Settings panes.

**What to build (acceptance criteria)**
- AI pane: Claude API key entry (secure text field, stored in Keychain), tier preference (on-device vs cloud), usage stats (from `AITelemetry`).
- Fitness pane: body profile editor, dietary preferences, HealthKit permission button.
- Feedback pane: text field, send button (writes to a Mailto URL or to a backend if defined; same as iOS).

**How to build it**
1. Port each iOS settings view to Mac (`CalendarSettingsView.swift`, `FitnessSettingsView.swift`, `FeedbackView.swift`).
2. Mount in `MacSettingsScene` tabs.

**Verification**
- [ ] Each pane functional.
- [ ] Claude API key saved in Keychain; AI calls work afterward.

**Notes / decisions**
_(empty)_

---

### MM8-T06 — Settings → Keyboard pane
- **Status:** TODO
- **Depends on:** MM8-T05, MM4-T06
- **Estimated effort:** S

**Goal**
A read-only table of all keyboard shortcuts in the Mac app, sourced from `MacKeyboardShortcuts.all`.

**What to build (acceptance criteria)**
- `MacKeyboardSettingsPane.swift` renders a `Table` (or `List`) with two columns: Action, Shortcut.
- Reads from `MacKeyboardShortcuts.all` (MM4-T06).
- No customization yet — that's v1.1.

**How to build it**
1. Mount in `MacSettingsScene` as a new tab "Keyboard".
2. `Table` with `TableColumn("Action") { $0.label }` and `TableColumn("Shortcut") { $0.combo }`.

**Verification**
- [ ] Table shows every shortcut.
- [ ] Order is stable.

**Notes / decisions**
_(empty)_
