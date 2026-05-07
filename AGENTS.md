# AGENTS.md — Read this first

You are an AI coding agent working on **LEO**, an iOS productivity app. This file is your entry point. Everything else is reachable from here.

## What LEO is (one paragraph)

LEO unifies tasks, calendar events, reminders, alarms, recurring obligations, deadlines, and habits into a single timeline, paired with an AI assistant that does real planning. Native SwiftUI, SwiftData + CloudKit private DB, EventKit bridge, hybrid AI (Apple Foundation Models on-device + Claude API for planning). Solo dev. Public App Store target. **Read [`PRD.md`](PRD.md) for the full product spec.**

## How to work on this project

### 1. Start every session by reading these, in order

1. **`AGENTS.md`** (this file) — orientation.
2. **`IMPLEMENTATION_PLAN.md`** — global rules + the live status tracker. **The status tracker is the source of truth** for what's done and what's next.
3. **`plans/conventions.md`** — project structure, naming, testing, commit conventions. Follow these without exception.
4. **The current milestone file** in `plans/`, identified by the status tracker. Skim it end-to-end before picking a task.

If you skip these, you will redo work, duplicate code, or violate conventions that already exist.

### 2. Pick one task, in order

- Tasks have IDs like `M0-T03`. They have `Status:` and `Depends on:` fields.
- Take the first task in the current milestone whose status is `TODO` and whose dependencies are all `DONE`.
- **Do not skip ahead.** If you're blocked, mark the task `BLOCKED` with a one-line note, then move to the next eligible task — but flag the block to the user before continuing.

### 3. Work the task

- Update the task's status to `IN-PROGRESS` *before* you start.
- Read the task's **What to build** (acceptance criteria) and **How to build it** (concrete steps). These are the contract.
- Stay inside scope. If you discover scope outside the task, **add a follow-up task** to the milestone file rather than expanding the current one.
- When you finish, update the status to `DONE` and check the boxes in **Verification**.

### 4. End every session by updating state

- Set the task status (`DONE`, `IN-PROGRESS`, or `BLOCKED`).
- Update the milestone summary checklist at the top of the milestone file.
- Update the global progress table in `IMPLEMENTATION_PLAN.md`.
- Commit (see commit conventions in `plans/conventions.md`).

If a future session can't tell from these files alone what state the project is in, you didn't update enough.

## Anti-divergence rules (non-negotiable)

These exist because AI agents drift. Re-read them when you feel tempted to "just also fix this real quick."

1. **One task at a time.** Finish or explicitly stop the current task before starting another.
2. **No unrequested refactors.** If the task is "add quick-add bar," don't also reorganize the view layer. File a follow-up task.
3. **No new dependencies without approval.** Adding a Swift Package = ask the user first, in chat. Document the dependency in `plans/conventions.md` once approved.
4. **No new architectural patterns.** If conventions don't say to use X, don't introduce X. If you think conventions should say to use X, propose it; don't unilaterally add it.
5. **No deleting files or branches without confirmation.** Even "obviously dead" code.
6. **No skipping tests.** If a task says "write tests," tests must exist and pass before status becomes `DONE`.
7. **No skipping verification.** Run the app or simulator and confirm the feature behaves per the acceptance criteria. Compilation success is not verification.
8. **Stop and ask** before: changing the data model in a way that requires migration, modifying any file in `Persistence/`, touching CloudKit container config, or anything that costs real money (App Store submission, Claude API calls beyond eval scope).

## File map

```
LEO/
├── AGENTS.md                    ← you are here
├── PRD.md                       ← product spec
├── ROADMAP.md                   ← milestone targets + dates
├── IMPLEMENTATION_PLAN.md       ← rules + global status tracker
├── plans/
│   ├── conventions.md           ← project structure, naming, testing
│   ├── M0-foundation.md         ← milestone task files (the work)
│   ├── M1-capture-today.md
│   ├── M2-recurring-notifications.md
│   ├── M3-integration-sync.md
│   ├── M4-ai-assistant.md
│   ├── M5-habits-review.md
│   ├── M6-alarms-watch-polish.md
│   ├── M7-beta-monetization.md
│   └── M8-launch.md
└── (Xcode project will live alongside, created in M0-T01)
```

## When you're stuck

- **Acceptance criteria unclear?** Ask the user. Do not guess.
- **Implementation choice has trade-offs not covered by conventions?** Ask the user. Document the decision in `plans/conventions.md` after.
- **Task says "do X" but X seems wrong given what you know now?** Ask the user. Plans drift; correcting them is a feature, not a problem.
- **Apple API behaves differently than the plan assumed?** Note it in the task's **How to build it** section, ask the user, update the plan.

## What "done" looks like for a task

A task is `DONE` when **all of these** are true:

- All acceptance criteria in **What to build** are met and demonstrated.
- All items in **Verification** are checked off.
- Code is committed with a message referencing the task ID (e.g., `M1-T03: implement Today timeline view`).
- The status line in the milestone file says `DONE`.
- The progress table in `IMPLEMENTATION_PLAN.md` reflects the new state.

If you're unsure whether something is done, it isn't.
