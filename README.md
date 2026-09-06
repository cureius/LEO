# LEO

**The calendar that thinks. The to-do list that talks back.**

LEO is an AI-first personal operating system for your time. It unifies tasks, calendar events, reminders, alarms, recurring commitments, deadlines, and habits into **one timeline** — paired with an assistant that can actually *plan* with you, not just parse what you type.

Most productivity apps understand one slice of your life: Reminders does checkboxes, Fantastical does calendar, TickTick does tasks. LEO's thesis is simple — everything you owe your future self belongs on the same surface, and an AI that understands all of it is more useful than five apps that each understand one slice.

## Why

- **One timeline, one truth.** Today shows time-blocked events, due-today tasks, today's habits, and alarms — no tabs to switch between domains.
- **The AI plans, it doesn't just parse.** "gym MWF 7am for an hour" and "draft the report by Friday" both just work. "Plan my week" understands your actual constraints.
- **Local-first, private by default.** Data lives on-device / in your own Supabase project. Cloud AI is opt-in and never sees raw content unless you invoke it.
- **Honors the OS.** Built on EventKit, App Intents, WidgetKit, Shortcuts — not a parallel universe bolted onto your phone.

## Platforms

| Target | Stack | Location |
|---|---|---|
| iOS / macOS (native) | Swift, SwiftUI, SwiftData, EventKit | `LEO/` |
| Web / desktop | React, Vite, TypeScript, Tauri | `apps/web/` |
| Backend | Supabase (Postgres, migrations) | `supabase/` |

## Getting started

### iOS / macOS

1. Open `LEO.xcodeproj` in Xcode.
2. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` and fill in your own Supabase anon key.
3. Build and run the `LEO` (iOS) or `LEOMac` (macOS) scheme.

### Web (native Mac app via Tauri)

```bash
cd apps/web
pnpm install
pnpm tauri dev
```

Requires the Rust toolchain (`rustup`) for the native shell. To run it as a plain browser app instead:

```bash
cd apps/web
pnpm dev
```

### Backend

Database schema and migrations live in `supabase/migrations/`. Point the app at your own Supabase project — see `supabase/README.md` for setup.

## Project docs

- [`PRD.md`](PRD.md) — product requirements and positioning
- [`ROADMAP.md`](ROADMAP.md) — milestone plan
- [`AGENTS.md`](AGENTS.md) — conventions for AI coding agents working in this repo
- [`plans/`](plans) — per-milestone implementation plans

## Contributing

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) to get started.

## License

MIT — see [`LICENSE`](LICENSE).
