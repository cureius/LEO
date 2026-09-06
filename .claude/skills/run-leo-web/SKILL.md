---
name: run-leo-web
description: Launch the LEO web app (apps/web) as a native Mac app via Tauri, or run it in a plain browser dev server. Use when asked to "run the app", "launch LEO", "run in localhost", or similar for this repo.
---

# Running LEO web

The web app lives in `apps/web` (Vite + React). It is wrapped as a native
Mac app using Tauri (`apps/web/src-tauri`).

## Quick launch (native Mac window, recommended)

```bash
cd apps/web && pnpm tauri dev
```

This starts the Vite dev server on `http://localhost:5173` and opens a
native macOS window (WKWebView) pointed at it, with hot reload. First run
compiles the Rust shell (~1 min); subsequent runs are fast.

Requires the Rust toolchain (`cargo`, `rustc`) on PATH — install via
`https://sh.rustup.rs` if missing, then `source "$HOME/.cargo/env"`.

## Production build (installable .app)

```bash
cd apps/web && pnpm tauri build
```

Produces a standalone `LEO.app` (and `.dmg`) under
`apps/web/src-tauri/target/release/bundle/macos/`. No dev server or
terminal needed to run it afterward — just open/double-click the app.

## Plain browser dev server (no native shell)

```bash
cd apps/web && pnpm dev
```

Serves at `http://localhost:5173` — open manually in a browser.

## Notes

- Bundle identifier: `com.souraj.leo` (set in `apps/web/src-tauri/tauri.conf.json`).
- If `pnpm tauri dev` reports port 5173 already in use, check for and kill
  a stray `vite` process (`lsof -i :5173`) before retrying — the Tauri
  window is hardcoded to `devUrl: http://localhost:5173` and won't find
  the app if Vite falls back to another port.
