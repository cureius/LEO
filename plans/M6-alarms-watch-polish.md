# M6 — Alarms, Watch, Polish

**Goal of this milestone:** Real alarms (best-effort given iOS constraints), Apple Watch presence, onboarding, error & empty states, settings.

**Target ship:** 2026-09-03 (2 weeks).

**Read before starting:** [`PRD.md`](../PRD.md) §7.4 (alarms) and §11 (R1 risk).

**Prerequisites:** M5 complete.

**Open question (resolve before starting):** Watch app at v1 launch or v1.1? See [`IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md) open questions.

---

## Task summary

- [x] M6-T01 — Real alarm playback
- [x] M6-T02 — Alarm Live Activity
- [x] M6-T03 — Alarm UX (set / silent fallback / snooze)
- [ ] M6-T04 — Apple Watch app (DEFERRED to v1.1 — see open question)
- [x] M6-T05 — Onboarding flow
- [x] M6-T06 — Settings surface
- [x] M6-T07 — Empty / error / loading states

---

### M6-T01 — Real alarm playback
- **Status:** TODO
- **Depends on:** M5 complete
- **Estimated effort:** L

**Goal**
An alarm that overrides silent mode and reliably wakes the device — best-effort within iOS limitations.

**What to build (acceptance criteria)**
- `Alarms/AlarmEngine.swift` actor:
  - `func arm(_ alarm: AlarmItem) async`
  - `func disarm(id: UUID) async`
- Two-layer strategy:
  1. **Notification layer:** UNNotificationRequest with critical sound (requires user-granted critical alerts) + a custom sound bundled in the app.
  2. **Audio layer (when foregrounded or Live Activity active):** AVAudioSession `.playback` category, escalating volume from low to max over 30s, plays a chosen alarm sound on loop.
- Pre-arm: 5 minutes before fire, the app schedules a Live Activity (M6-T02). When the activity is live, the audio layer can fire reliably.
- Post-arm: if device is locked and silenced and no Live Activity active, only the notification fires — clearly documented as "best-effort".
- Settings: "Use real alarm sounds (overrides silent)" toggle; ask for critical alerts permission on first toggle.

**How to build it**
1. Critical alerts require entitlement granted by Apple — apply early. Note in `IMPLEMENTATION_PLAN.md` decision log when granted/denied.
2. Bundle 4–6 alarm tones at `Resources/AlarmSounds/`. ≤ 30s each. Loop in audio layer.
3. AVAudioSession activation in `audioPlayerDidFinishPlaying`-equivalent so we don't hold the session when not actively alarming.
4. Test on device — simulator's audio behavior misleads.
5. **STOP AND ASK** if it looks like we need to abuse always-on audio. App Store will reject.

**Verification**
- [ ] Set alarm 60s out, lock device, silent on → notification fires; if Live Activity active, audio plays and escalates.
- [ ] Disarm cancels both layers cleanly.
- [ ] Switching to a different alarm tone applies on next fire.

**Notes / decisions**
- Document caveats clearly in onboarding (M6-T05).

---

### M6-T02 — Alarm Live Activity
- **Status:** TODO
- **Depends on:** M6-T01
- **Estimated effort:** M

**Goal**
A Live Activity for armed alarms with snooze/dismiss controls; supports the audio layer.

**What to build (acceptance criteria)**
- `Integrations/LiveActivities/AlarmActivity.swift` with `ActivityAttributes` for the alarm.
- Lock-screen layout: alarm time, name, "Snooze 9 min" + "Dismiss" buttons.
- Dynamic Island compact: bell icon + countdown; expanded: full controls.
- Started 5 min before fire; ends on dismiss or 30 min after fire (max iOS allows).
- Buttons use `LiveActivityIntent` (App Intents) routing to `AlarmEngine`.

**How to build it**
1. Use `ActivityKit`'s local update path; don't push.
2. Snooze: schedule a new alarm for `now + 9min` and end this activity; Dismiss: disarm and end.
3. Test on a real Dynamic Island device (15 Pro+) and a non-DI device.

**Verification**
- [ ] Alarm 6 min out triggers Live Activity 1 min later (= 5 min before).
- [ ] Snooze button works from lock screen.
- [ ] Activity ends correctly on dismiss.

---

### M6-T03 — Alarm UX
- **Status:** TODO
- **Depends on:** M6-T02
- **Estimated effort:** S

**Goal**
The user can set, edit, and trust alarms.

**What to build (acceptance criteria)**
- Quick-add "wake me at 6:30" creates an `AlarmItem` armed automatically.
- Detail sheet for alarms: time, sound, escalation toggle, "use system Clock as backup" toggle.
- A small banner in Today shows the next armed alarm with a "test" button.
- "Test" button arms the alarm 5 sec out — useful for users to validate behavior on their device.

**How to build it**
1. Don't auto-arm a "test" — show a dialog "Test alarm in 5s? Sound will play." with confirmation.
2. Banner is dismissible; remembers dismissal per-alarm.

**Verification**
- [ ] Capturing "wake me at X" sets and arms.
- [ ] Test button reliably plays sound.
- [ ] User can disable an alarm without deleting it.

---

### M6-T04 — Apple Watch app
- **Status:** TODO
- **Depends on:** M5 complete (or DEFERRED to v1.1)
- **Estimated effort:** L

**Goal**
A read-mostly Watch app with quick capture by dictation. (If deferred per open-question resolution, the task moves to v1.1.)

**What to build (acceptance criteria)**
- New target `LEOWatch` with shared `WatchConnectivity` link.
- Watch app screens:
  - Today (next 5 items).
  - Habits (today's rings, tap to complete).
  - Quick-add via dictation only (Siri-style mic button).
- Complications:
  - Circular: today's habit ring summary.
  - Modular: next item title + time.
- Sync via `WCSession.transferUserInfo`; reconcile on activate.

**How to build it**
1. Watch can't use SwiftData directly across devices in iOS 18 — share via WatchConnectivity messages.
2. Limit capture to dictation; full keyboard input on Watch is bad UX.
3. The Watch is a *companion*, not a primary surface in v1.

**Verification**
- [ ] Today screen renders next 5 items within 1s of activate.
- [ ] Dictation capture creates an item visible on iPhone within 5s.
- [ ] Complications refresh on item changes.

---

### M6-T05 — Onboarding flow
- **Status:** TODO
- **Depends on:** M5 complete
- **Estimated effort:** M

**Goal**
A 4-screen onboarding that demonstrates LEO's value and collects permissions in the right order.

**What to build (acceptance criteria)**
- `Features/Onboarding/Views/OnboardingFlow.swift`:
  - Screen 1: "Capture in three seconds" — interactive demo of quick-add, parses a sample.
  - Screen 2: "Ask LEO" — interactive demo where user types a planning prompt; we run a canned response (no API call) to avoid first-run cost.
  - Screen 3: "Permissions" — notifications, calendar, reminders, location (when in use), microphone, Apple Intelligence; each with a brief why.
  - Screen 4: "Connect calendars" — pick which iOS calendars/lists to mirror.
- Skippable except permissions screen; permissions can be deferred but flagged.
- p50 completion < 90s.
- Feature flag to re-show ("reset onboarding" in debug menu).

**How to build it**
1. Use `TabView(.page)` with custom indicator.
2. Permission requests one-at-a-time with explainer cards before the system prompt.
3. Don't gate features on incomplete onboarding; just nudge.

**Verification**
- [ ] First-launch flow completes in < 90s p50 (timed manually).
- [ ] Each permission screen shows the system prompt only after user taps "Continue".
- [ ] Resetting and rerunning works.

---

### M6-T06 — Settings surface
- **Status:** TODO
- **Depends on:** all prior M6 tasks
- **Estimated effort:** M

**Goal**
A consolidated Settings screen exposing everything currently scattered.

**What to build (acceptance criteria)**
- Sections:
  - Account (iCloud status from M3-T07).
  - Capture (default importance, default tag).
  - Today (start hour, end hour, energy blocks).
  - Notifications (allow critical alerts, default reminder lead times).
  - Calendars & Reminders (toggle imports + write-back targets).
  - AI (model preference, monthly budget, privacy toggles, payload inspector).
  - Habits (default forgiveness rule).
  - Alarms (default sound, escalate by default).
  - About (version, build, links to Privacy Policy, Terms, support email).
- Energy blocks: a small editor where the user defines ranges like "Mon–Fri 9–11am: deep work" — used by AI planner (M4 already reads if present).
- All settings persisted in user defaults for flags, in `StoredAppPrefs` for structured (energy blocks).

**How to build it**
1. Build sections incrementally; each links to a sub-view if it has more than 3 fields.
2. Don't invent settings that the rest of the app doesn't use yet — every setting must wire to a feature.

**Verification**
- [ ] Every setting has a verifiable effect.
- [ ] Energy blocks edited in settings flow into the AI's standing context cache.

---

### M6-T07 — Empty / error / loading states
- **Status:** TODO
- **Depends on:** all M6 tasks
- **Estimated effort:** S

**Goal**
Every surface handles "nothing here", "something broke", "we're working" gracefully.

**What to build (acceptance criteria)**
- Audit every screen: Today, Inbox, Habits, Habit detail, AssistantChat, Settings, Calendars settings, Onboarding.
- Each gets:
  - **Empty state:** illustration (SF Symbols), one-line guidance, primary action where useful.
  - **Error state:** `LEOErrorBanner` with retry where applicable.
  - **Loading state:** skeleton or progress, never a blank screen for > 200ms.
- Network-down behavior: AI assistant shows "Offline — using on-device only".

**How to build it**
1. Add a small QA pass per screen; document gaps in this task's notes.
2. Skeleton loaders for Today and Habits use shimmering rectangles for ~5 rows.
3. Error copy: human, not "Error code 17". Include a "Report" link that opens an email pre-filled with diagnostic info.

**Verification**
- [ ] Every screen audited (checklist in this task's notes after run).
- [ ] Forced offline mode → no broken screens; clear messaging.

---

## Exit criteria for M6

- [ ] All seven tasks `DONE` (Watch may be deferred per open question; if deferred, decision logged).
- [ ] Real alarm wakes device in 95%+ of test trials when user has granted needed permissions.
- [ ] Onboarding < 90s p50.
- [ ] Every screen has empty/error/loading states.
- [ ] App Store screenshots + preview video drafted (used in M7).
- [ ] User signs off in chat.
