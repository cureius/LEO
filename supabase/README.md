# LEO ↔ Supabase: live sync + cloud backup (multi-tenant / SaaS-ready)

This folder contains everything to back LEO with Supabase for **real-time sync
across devices**, **cloud backup**, and a **multi-user SaaS** foundation.

> Status: the **database design is complete and deployable today**. The Swift
> integration is delivered as a **staged scaffold** (`LEO/Sync/`) guarded by
> `#if canImport(Supabase)` so it does **not** affect the current build until you
> add the package + credentials. Realtime sync must be verified against your own
> Supabase project — it can't be tested without one.

## Architecture at a glance

```
 iPhone  ─┐                                   ┌─ Postgres (RLS: user_id = auth.uid())
 Mac     ─┤  supabase-swift SDK  ⇄  Supabase ─┤  Realtime (row change broadcast)
 (future ─┘   • Auth (email/pwd)               └─ Auth (multi-user)
  web/Android)• Realtime subscribe
              • REST upsert/select (delta sync)

 Local source of truth stays SwiftData (offline-first).
 A SyncService reconciles local ⇄ remote:
   • push: local rows changed since lastSync → upsert to Supabase
   • pull: remote rows where updated_at > lastSync → apply locally
   • realtime: subscribe to my rows → apply pushes instantly
 Conflict rule: last-writer-wins by `updated_at` (simple, predictable).
 Deletes: soft (`deleted_at`) so they propagate instead of vanishing.
```

## 1. Create the Supabase project
1. Create a project at supabase.com (free tier is fine to start).
2. **Project Settings → API**: copy the **Project URL** and the **anon public key**.
3. **SQL Editor**: paste & run `migrations/0001_init.sql`. This creates the tables,
   Row Level Security policies, the auto-profile trigger, and adds the tables to
   the realtime publication.
4. **Authentication → Providers**: enable **Email** (magic link or password).

## 2. Add the SDK to the app
The package is already declared in `project.yml`. Regenerate the Xcode project:
```bash
brew install xcodegen      # if not installed
cd <repo root> && xcodegen generate
```
This adds `supabase-swift` (https://github.com/supabase/supabase-swift) to both the
`LEO` and `LEO-Mac` targets and includes the new `LEO/Sync/` sources.

## 3. Provide credentials (never hard-code real keys)
Add to each target's Info plist (or an xcconfig):
```
SUPABASE_URL      = https://<your-project>.supabase.co
SUPABASE_ANON_KEY = <anon public key>
```
`SupabaseConfig` reads these at runtime. The anon key is safe to ship — RLS is what
protects data, not key secrecy.

## 4. Capabilities
Realtime + REST only need outbound networking:
- iOS: no extra entitlement (uses URLSession).
- macOS (sandboxed): `com.apple.security.network.client` — already present in the
  Mac entitlements.

## 5. Turn it on
In **Settings → Cloud Sync** (the new page): sign in / create account → the app
runs an initial two-way sync, then keeps a realtime subscription open. "Back up to
cloud now" forces a full push; "Restore from cloud" pulls everything.

## Multi-user / SaaS notes
- **Tenant key is `user_id`** on every row; RLS (`auth.uid() = user_id`) means a
  device physically cannot read another user's data. Onboarding a new user is just
  a new auth signup — no schema change.
- **Billing hook**: `profiles.subscription_tier` (`free|pro|team`) is ready to gate
  features/limits.
- **Org/workspace tenancy** (shared team data) can be added later without a rewrite
  — see the NOTES block at the bottom of `0001_init.sql`.

## Why this over CloudKit
CloudKit is Apple-only and needs the paid Apple Developer Program. Supabase gives
you realtime, a real SQL backend you control, auth, and a path to web/Android — the
right base for a SaaS. Trade-off: SwiftData is offline-first, so we own a small sync
layer (the `SyncService`) rather than getting it for free.
