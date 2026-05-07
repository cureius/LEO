# LEO — Product Requirements Document

**Status:** Draft v0.1
**Owner:** Raj
**Last updated:** 2026-05-07
**Platform:** iOS (iPhone first; iPad and Apple Watch later)

---

## 1. Snapshot

LEO is an AI-first personal operating system for your time. It unifies tasks, calendar events, reminders, alarms, recurring obligations, deadlines, and habits into **one timeline** — and pairs that timeline with an assistant that can actually *plan* with you, not just parse what you type.

The thesis in one sentence: **everything you owe your future self belongs on the same surface, and an AI that understands all of it is more useful than five apps that each understand one slice.**

---

## 2. Why now

- **Apple Intelligence + Foundation Models** put a capable on-device LLM in every supported iPhone, removing the latency, privacy, and cost objections that historically blocked AI-heavy productivity apps.
- **SwiftData + CloudKit** make local-first, multi-device sync possible without running a backend — a one-person team can credibly ship this.
- **The incumbents are stuck:** Apple Reminders is a checkbox app, Things is beautiful but un-AI, Fantastical merges calendar and reminders but ignores tasks/habits, TickTick is feature-rich but UX-noisy. None of them reason about your week.
- **Habit and "second brain" categories have plateaued** because they're disconnected from the calendar where time actually gets spent. LEO collapses that gap.

The window: ~12–18 months before Apple itself or one of the big players ships a unified, agentic productivity surface. LEO has to land before that.

---

## 3. Target user

**Primary persona — "The Overcommitted Operator"**
- 25–45, knowledge worker, founder, grad student, or independent professional.
- Already pays for at least one productivity tool (Things, Fantastical, Notion, Sunsama, TickTick, Motion).
- Lives between calendar and todo list and feels the seam every day.
- Comfortable talking to AI; expects natural-language input as table stakes.
- Pays for tools that save time. Will pay $5–$15/mo or $60–$120/yr for one that *actually* does.

**Secondary — "The Aspiring Self-Manager"**
- Wants to build habits, hit deadlines, stop dropping balls.
- More casual; lives in iOS Reminders today.
- Will not pay if v1 feels like a calendar.

**Anti-personas (explicitly not v1):**
- Teams / shared projects (LEO is single-player in v1).
- Power users who need full GTD ritual (areas, projects, contexts, tags, filters).
- Time-tracking / billable-hours users.

### Top jobs-to-be-done

1. *Capture* anything I owe my future self in under three seconds, by typing or speaking.
2. *Plan* a realistic day/week given my constraints, deadlines, and energy.
3. *Be reminded* at the right time and place, including with real alarms when it matters.
4. *Hold myself accountable* to recurring commitments (habits, weekly reviews, deadlines).
5. *Recover* gracefully when life slips — reschedule everything affected, don't just guilt-trip me.

---

## 4. Positioning

| | Apple Reminders | Things | Fantastical | TickTick | Motion | **LEO** |
|---|---|---|---|---|---|---|
| Tasks | ✅ basic | ✅ best-in-class | ⚠️ via Reminders | ✅ | ✅ | ✅ |
| Calendar events | ❌ | ❌ | ✅ best-in-class | ✅ | ✅ | ✅ |
| Real alarms | ⚠️ via Clock | ❌ | ❌ | ⚠️ | ❌ | ✅ first-class |
| Rich recurring rules | ⚠️ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ stronger |
| Habits / streaks | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ |
| Conversational AI planner | ❌ | ❌ | ⚠️ NL parse | ⚠️ NL parse | ✅ auto-schedule | ✅ chat + propose |
| Privacy-first / on-device | ✅ | ✅ | ✅ | ⚠️ | ❌ | ✅ |

**Positioning line:** *The calendar that thinks. The to-do list that talks back. One app for everything you owe your future self.*

---

## 5. Product principles

1. **One timeline, one truth.** Today shows everything: time-blocked events, due-today tasks, today's habits, alarms. No tabs to switch between domains.
2. **Capture in three seconds.** Quick-add (text or voice) is one tap from anywhere — lock screen, widget, Watch, Shortcut, share sheet.
3. **The AI plans, it doesn't just parse.** Natural-language input is the floor. The bar is "plan my week" with constraints understood.
4. **Local-first, private by default.** All data lives on-device and in the user's iCloud private DB. The Claude API is opt-in for advanced reasoning and never sees raw event content unless the user invokes it.
5. **Honor the OS.** Use EventKit, App Intents, WidgetKit, Live Activities, Focus filters, Siri, Shortcuts. Don't build parallel surfaces.
6. **Reschedule, don't shame.** When the user slips, the app proposes recovery. Streaks are forgiving, not punitive.
7. **Beautiful, then powerful.** v1 ships with one opinionated UI. Customization is earned in v2+.

---

## 6. Core concepts (the data model)

LEO's domain model unifies five primitive types behind a common interface called an **Item**.

```
Item (abstract)
├─ Task          (open-ended, due/deferred dates, optional duration, priority)
├─ Event         (time-blocked, start+end, location, attendees)
├─ Reminder      (point-in-time or location-triggered notification)
├─ Alarm         (point-in-time, audio-prioritized, escalation)
└─ HabitInstance (a single occurrence of a recurring habit)

Plus:
RecurrenceRule  (RFC 5545 RRULE, plus extensions for "skip on holidays", "on workdays only")
Habit           (a definition; spawns HabitInstances)
Deadline        (a hard date attached to a Task or Project; surfaces countdown + risk)
Project         (a grouping of Tasks/Events with an optional deadline) — v1.x, not v1
Tag             (lightweight; not the primary org unit)
EnergyBlock     (user-defined "morning deep-work / afternoon shallow / evening off") — used by AI planner
```

**Key insight:** by giving every primitive the same `Item` superclass with `(start, end, anchor, importance, completion)` fields, the unified timeline is just a query, not a feature.

**Storage:** SwiftData. Items synced via CloudKit private database. EventKit is a *bridge*, not the source of truth — LEO mirrors the user's iOS calendars and reminders into its own store so the AI and recurrence engine can reason across them.

---

## 7. Functional requirements (v1)

### 7.1 Capture
- **F-CAP-1** Quick-add bar accepts free-form text. NL parser extracts type, title, time, recurrence, location, people. Examples that must work:
  - "call mom every Sunday at 6pm"
  - "draft Q3 report by Friday"
  - "wake me up at 6:30 tomorrow with a real alarm"
  - "gym MWF 7am for 1 hour"
  - "dentist June 12 at 2pm at 401 Pine St"
- **F-CAP-2** Voice quick-add via Whisper/SFSpeechRecognizer; same pipeline as text.
- **F-CAP-3** Share sheet extension: turn any selected text or URL into an Item.
- **F-CAP-4** Siri / App Intents: "Hey Siri, add to LEO…".
- **F-CAP-5** Lock-screen widget for one-tap quick-add.

### 7.2 Today / Timeline
- **F-TIM-1** Today view: vertical timeline showing all Items for today, sorted chronologically, with un-timed tasks pinned to a "no time set" lane.
- **F-TIM-2** Drag to reschedule. AI proposes ripple effects (e.g., "this conflicts with your 3pm — move it?").
- **F-TIM-3** Week view: 7-day grid with Items rendered at their times.
- **F-TIM-4** Inbox: items captured without enough info (no date, ambiguous type) collect here for triage.
- **F-TIM-5** Upcoming: deadlines/recurring/important items in the next 14 days, sorted by risk.

### 7.3 Recurring engine
- **F-REC-1** Full RFC 5545 RRULE support (DAILY/WEEKLY/MONTHLY/YEARLY, BYDAY, BYMONTHDAY, INTERVAL, COUNT, UNTIL).
- **F-REC-2** Extensions: "every other Tuesday unless US holiday", "first weekday of each month", "every workday at 9am", "every 3 days starting today".
- **F-REC-3** Per-occurrence overrides (skip this one, move this one) without breaking the series.
- **F-REC-4** Visual rule builder + natural-language input ("every other Tuesday") that round-trips.

### 7.4 Reminders & alarms
- **F-REM-1** Time-based reminders via UNUserNotificationCenter.
- **F-REM-2** Location-based reminders (arrive/leave).
- **F-REM-3** "Real alarm" mode: plays audio that overrides silent switch (using AVAudioSession `.playback`), escalating volume, snooze/dismiss UI in Live Activity. **See risks §11.**
- **F-REM-4** Smart pre-reminders: "leave for dentist in 20 min" computed from travel time (MapKit ETA).

### 7.5 Habits & accountability
- **F-HAB-1** Define habits with frequency (daily / N times per week / specific days), duration target, and time hint.
- **F-HAB-2** Streak tracking with **forgiving streaks** — one allowed miss per week without breaking.
- **F-HAB-3** Today view shows habit instances inline with everything else; check off in place.
- **F-HAB-4** Weekly retrospective (Sunday evening): what completed, what slipped, AI-generated insight, prompt to adjust next week.

### 7.6 AI assistant
- **F-AI-1** Chat surface ("Ask LEO") with full read access to the user's Items, calendars, habits.
- **F-AI-2** Capabilities (must-haves):
  - "What's my Friday look like?"
  - "Plan my week. I have these deliverables and gym M/W/F."
  - "I'm sick today — push everything that can wait."
  - "Why is my calendar so crowded next Tuesday?"
  - "Find me 90 min for deep work this week."
- **F-AI-3** AI proposes diffs the user reviews and accepts/rejects (never auto-mutates without confirmation in v1).
- **F-AI-4** Hybrid model routing: simple parses → on-device Foundation Models; multi-step planning → Claude API (opt-in, with token budget transparency).

### 7.7 OS integrations
- **F-OS-1** EventKit two-way sync with selected iOS calendars and reminder lists.
- **F-OS-2** Home/Lock-screen widgets: Today, Next-up, Quick-add, Habit ring.
- **F-OS-3** Live Activities for active alarms, in-progress events, countdown deadlines.
- **F-OS-4** Focus filters: hide non-work Items in Work focus, etc.
- **F-OS-5** Shortcuts actions for every common operation (add task, complete task, start timer, get today).
- **F-OS-6** Siri intents (App Intents).

### 7.8 Onboarding & monetization
- **F-ONB-1** 4-screen onboarding: capture demo → AI demo (live) → permissions (notifications, calendar, location, mic, Foundation Models) → import existing calendars/reminders.
- **F-MON-1** Free tier: unlimited capture, today/week, basic recurring, system reminders, EventKit sync, 5 AI prompts/week.
- **F-MON-2** Pro ($9.99/mo or $79.99/yr): unlimited AI, real alarms, habits, weekly review, advanced recurring, widgets, Live Activities, Watch app.
- **F-MON-3** 7-day Pro trial; StoreKit 2; family sharing supported.

---

## 8. AI capability tiers

| Tier | Where it runs | When it triggers | Cost |
|---|---|---|---|
| **L0 — Parse** | On-device (Foundation Models / regex+chrono) | Every quick-add | Free |
| **L1 — Summarize** | On-device | Daily brief, weekly review | Free |
| **L2 — Plan** | Claude API (Sonnet/Haiku) | User asks "plan my…" or "find me time…" | Counted against monthly quota |
| **L3 — Reason** | Claude API (Opus/Sonnet) | Conflict resolution across many items, deadline risk analysis | Pro only |

**Privacy contract:** the user sees a clear indicator when a request leaves the device. Item content is sent only for L2/L3 and only the slice relevant to the prompt. No analytics, no third parties.

---

## 9. Non-functional requirements

- **Performance:** Today view renders < 300ms cold; quick-add visible < 100ms; AI response (L0/L1) < 500ms perceived; (L2) < 4s.
- **Offline:** All capture, edit, reminder firing, recurring expansion works fully offline. AI L2/L3 degrades gracefully.
- **Battery:** Background sync ≤ 1% per day in typical use.
- **Reliability:** Notifications/alarms must fire even after force-quit and across reboots (use UNNotificationCenter + Background Tasks framework).
- **Accessibility:** Full VoiceOver, Dynamic Type up to AX5, reduced motion, color-blind safe, haptic-only alarm option.
- **Privacy:** No third-party SDKs. Crash reporting via Apple's MetricKit. No user-content telemetry.
- **iOS support:** iOS 18+ minimum (covers Apple Intelligence devices and SwiftData maturity). iPhone only at v1 launch.

---

## 10. Architecture (proposed)

```
┌──────────────────────────────────────────────────────────────────┐
│ SwiftUI views (Today, Week, Inbox, Habits, Ask LEO, Settings)    │
└──────────────────────────────────────────────────────────────────┘
                          │  Observable view models
┌──────────────────────────────────────────────────────────────────┐
│ Domain layer                                                     │
│   • Items repository (SwiftData)                                 │
│   • Recurrence engine (RRULE expansion + extensions)             │
│   • Scheduler (slot-finding, conflict detection)                 │
│   • Notification manager (UNUserNotificationCenter)              │
│   • Alarm manager (AVAudioSession, Live Activity)                │
│   • Habit engine (instance materialization, streak math)         │
└──────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────┐
│ Integration layer                                                │
│   • EventKit bridge (mirror calendars + reminders, write-back)   │
│   • CloudKit sync (private DB)                                   │
│   • App Intents / Shortcuts / Siri                               │
│   • WidgetKit / Live Activities                                  │
└──────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────┐
│ AI layer                                                         │
│   • On-device: FoundationModels framework (Apple Intelligence)   │
│     - parseQuickAdd(), summarizeDay(), categorize()              │
│   • Cloud: Claude API client (prompt-cached)                     │
│     - planWeek(constraints), resolveConflicts(), reviewWeek()    │
│   • Tool use: AI calls into typed tools that return Item diffs   │
│     for user approval (no direct mutations).                     │
└──────────────────────────────────────────────────────────────────┘
```

**Key architectural calls (with reasoning):**

- **Native SwiftUI + Swift Concurrency, not React Native / Flutter.** Widgets, Live Activities, App Intents, Foundation Models, Watch — all of these are native-only or first-class only in native. Cross-platform would force a v1 compromise we'd never recover from.
- **SwiftData over Core Data.** Modern, less boilerplate, integrates with Observation. Risk: SwiftData migrations are still rougher than Core Data — model schema must be versioned carefully from day one. Worth the trade.
- **CloudKit private DB, no backend.** Free, encrypted, multi-device, no server to run. Trade-off: no shared/multi-user features ever without a backend. Acceptable for v1 single-player positioning.
- **EventKit as bridge, not source.** If Items live in EventKit, we can't attach our metadata (energy levels, AI rationale, habit linkage). Mirror approach lets LEO own its model while staying in sync with the system.
- **AI proposes diffs.** AI never silently rewrites the calendar. Every plan returns a structured diff the user accepts. This is both safety and trust-building.
- **Prompt caching on Claude API.** The user's standing context (preferences, energy blocks, recurring obligations) is cached; only the deltas are billed at full price. Critical for unit economics on the Pro tier.

---

## 11. Risks & open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | **iOS doesn't allow third-party "real alarms" that override silent mode reliably**. AVAudioSession `.playback` works while app/Live Activity is alive but is not officially sanctioned for alarm clock use. | Ship "best-effort real alarm" with clear UX caveats. Offer fallback to system Clock app integration via Shortcut. Watch for App Store review pushback. |
| R2 | **Apple ships its own unified AI scheduler in iOS 19/20.** | LEO's wedge becomes UX quality, recurring engine depth, and habit features Apple won't prioritize. Move fast on differentiated features. |
| R3 | **Foundation Models API limitations.** Output structure, latency, model capability may be insufficient for L0 parsing reliably. | Hybrid: on-device + small cloud fallback. Keep parser deterministic where possible (chrono-style date parsing) and use LM only for ambiguity. |
| R4 | **SwiftData + CloudKit edge cases at scale** (large item counts, schema migrations). | Cap item history to 2 years, archive older. Version models from v0. Write migration tests early. |
| R5 | **AI planning quality**. "Plan my week" is hard; bad plans erode trust fast. | Diff-based proposal model — user always reviews. Start with narrow prompts ("find time for X") before broad ones ("plan my week"). |
| R6 | **App Store review of alarm + always-on audio.** | Carefully scope use of audio session; document in review notes. |
| R7 | **Pricing & willingness to pay.** Productivity is crowded. | Generous free tier (capture is free forever). Pro paywall behind AI + alarms + habits — the high-leverage features. |
| R8 | **Solo-dev scope risk.** v1 list is long. | Roadmap (separate doc) explicitly cuts to a beta scope; v1 is what survives that cut. |

**Open questions for the next decision pass:**
- Do we ship a Watch app at v1 launch or v1.1?
- Do we support Google Calendar directly in v1, or rely on the user adding their Google account to iOS first?
- Is the chat assistant a separate tab, or does it live as a sheet over Today?
- How aggressive should the AI be by default — quiet (only when summoned) or proactive (daily morning brief)?
- Voice-first mode (a "talk to LEO while I drive" experience) — v1 or v1.x?

---

## 12. Success metrics

**North star:** *Daily Active Capture* — % of installs that capture ≥ 1 Item per day in week 4.

**Activation funnel:**
- Install → onboarding complete: ≥ 70%.
- Onboarding → first capture (day 1): ≥ 85%.
- Day 1 → day 7 retention: ≥ 40%.
- Day 7 → day 28 retention: ≥ 25%.
- Trial → paid conversion: ≥ 8%.

**Engagement quality:**
- Median Items captured/active day: ≥ 5.
- AI prompts/active week (Pro): ≥ 3.
- Habit instances completed/active week: ≥ 4.

**Quality bars:**
- Crash-free sessions: ≥ 99.7%.
- Notification delivery success (compared to scheduled): ≥ 99%.
- App Store rating: ≥ 4.6 by month 3 post-launch.

---

## 13. Out of scope for v1 (intentional cuts)

- Team / shared lists / collaboration.
- Time tracking / time-blocking automation.
- Email triage / Gmail integration.
- iPad-optimized layout (universal binary, but iPhone-grade only).
- Watch app beyond complications + glance widget.
- Web app or macOS Catalyst version.
- Multiple themes / icon packs / custom fonts.
- Full GTD ritual (areas, contexts, perspectives).
- Markdown notes inside Items (one-line note only).
- Project management features (Gantt, dependencies).
- Third-party integrations beyond EventKit (no Notion, Slack, Linear, Todoist import in v1).

These are not "never" — they're "not before LEO has earned the right to add them." Each one is a v1.x or v2 candidate.

---

## 14. Appendix — glossary

- **Item:** any captured unit of user intent (Task, Event, Reminder, Alarm, HabitInstance).
- **Anchor:** the time point (or window) an Item is bound to. Tasks may be anchored to a deadline; events to a start time.
- **Energy block:** a user-defined recurring window (e.g., "9–11am deep work") used by the AI planner.
- **Diff:** a structured proposal from the AI to add/modify/remove a set of Items, surfaced for user review.
- **Forgiving streak:** a streak that allows N misses per period without resetting.
- **Real alarm:** a notification that plays audio overriding the silent switch, intended to wake the user.

---

*This PRD is the **what** and **why**. Implementation order, milestones, and dates live in [`ROADMAP.md`](ROADMAP.md).*
