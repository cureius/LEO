# Contributing to LEO

Thanks for considering a contribution.

## Before you start

- For anything beyond a small fix, open an issue first to discuss the approach — it saves everyone rework.
- Check [`plans/conventions.md`](plans/conventions.md) for code style and architectural conventions used across the codebase.

## Development setup

See the "Getting started" section in [`README.md`](README.md) for running the iOS/macOS app and the web app locally.

## Pull requests

- Keep PRs focused — one logical change per PR.
- Include tests for new behavior where practical (`LEOTests`, `LEOMacTests`, or `apps/web/src/**/*.test.ts`).
- Describe *why* the change is needed, not just what changed.
- Make sure the relevant test suite passes before opening the PR:
  - iOS/macOS: run tests via Xcode (`Cmd+U`) or `xcodebuild test`.
  - Web: `cd apps/web && pnpm test`.

## Reporting bugs

Open an issue with steps to reproduce, expected vs. actual behavior, and your platform/OS version.

## Code of conduct

Be respectful and constructive. Disagreements about approach are fine; personal attacks are not.
