# LEO Web

Browser client for LEO — a peer of the native iOS/macOS apps, talking directly
to the same Supabase project. Realtime sync, tasks/events/reminders/alarms,
habits with recurrence, a fitness log, and an AI chat assistant (BYOK).

See `/Users/raj/.claude/plans/sequential-purring-hippo.md` in this repo's
Claude Code plan history for the full design rationale — wire-format
decisions, the sync engine, and why each phase is scoped the way it is.

## Local development

```bash
pnpm install
cp .env.example .env.local   # fill in your Supabase project URL + anon key
pnpm dev
```

`pnpm dev` also runs a local stand-in for the AI chat proxy (see
`devProxyPlugin.ts`) so Ask LEO works in local dev too, not just once
deployed — no `vercel dev` needed.

## Testing

```bash
pnpm test        # one-shot
pnpm test:watch  # watch mode
```

110 tests, concentrated on `wire/` (the Swift-compatible codec — the
highest-risk layer, since a shape mismatch there silently corrupts data
across every client) and `ai/` (SSE parsing, tool contracts, diff apply).

## Deploying (do this yourself — needs your own accounts)

This was intentionally left for you to run: deploying creates a live public
URL and cloud infrastructure under your identity, and touches your
production Supabase project's auth config — not something to do without
you present.

1. **Vercel** — from `apps/web/`:
   ```bash
   npx vercel        # first deploy; follow the prompts, set the project root to apps/web if asked
   npx vercel --prod # promote to production
   ```
   Or connect the repo at vercel.com/new and set the project root to `apps/web`.

2. **Environment variables** — in the Vercel project settings, add:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`

   (Same values as your `.env.local` — the anon key is safe to expose publicly, it's RLS-protected.)

3. **Supabase Auth redirect URLs** — in your Supabase dashboard, under
   Authentication → URL Configuration → Redirect URLs, add:
   - `https://<your-vercel-domain>/reset-password`
   - `https://*.vercel.app/reset-password` (covers PR preview deployments)

   Without this, the "forgot password" email link will fail to complete the
   reset once deployed.

4. **Verify**: sign up, confirm an item created on iOS/Mac appears within a
   couple of seconds, and try Ask LEO with a real Anthropic API key — that
   last part specifically was **not** verified during development, since it
   needs a real credential this session didn't have access to. Everything
   up to (but not including) an actual successful Claude response was
   verified against the real Anthropic API's own error responses.
