---
name: supabase-migrate
description: "Use whenever a change to LEO's Supabase database is needed — a new migration file, applying an existing migration in supabase/migrations/, inspecting live schema/data, or debugging a sync issue that might be a schema mismatch. Connects directly via psql instead of asking the user to paste SQL into the Supabase SQL Editor."
---

# Supabase direct DB access (LEO project)

Direct Postgres connection to LEO's Supabase project — set up so migrations and schema inspection can happen without round-tripping through the user pasting SQL into the dashboard's SQL Editor.

## Connection

The connection string lives in `apps/web/.env.local` as `SUPABASE_DB_URL` (gitignored, never commit it). Load it per-command:

```bash
source apps/web/.env.local
psql "$SUPABASE_DB_URL" -c "select 1;"
```

If a command ever fails with `password authentication failed`, the password in `.env.local` is stale — ask the user to reset it via **Project Settings → Database → Reset database password** in the Supabase dashboard and give you the new value. Do not guess passwords or retry blindly (Supabase may rate-limit repeated auth failures).

If a command fails with `could not translate host name` or the direct host hangs/times out (`No route to host`): the direct `db.<ref>.supabase.co` hostname is IPv6-only for this project (confirmed via `dig` — it has an AAAA record but no A record), and this network has no outbound IPv6 route. `SUPABASE_DB_URL` is already set to the **session pooler** connection instead (`postgres.<project-ref>@aws-1-ap-northeast-2.pooler.supabase.com:5432`, port 5432, IPv4) — use that, don't fall back to the direct host. If the pooler ever needs rediscovering (e.g. project moved regions), the region/prefix (`aws-0` vs `aws-1`) isn't guessable — ask the user to paste it from the dashboard's **Connect → Session pooler** panel rather than brute-forcing region combinations.

## Applying a new migration

1. Write the migration file to `supabase/migrations/000N_description.sql`, following the numbering and style of existing files there (see `0001_init.sql` for the RLS/trigger conventions this project uses — every table gets `user_id`-scoped RLS via the `owner_all` policy pattern, `deleted_at` for soft deletes, `set_updated_at()` trigger for `updated_at`).
2. Apply it directly:
   ```bash
   source apps/web/.env.local
   psql "$SUPABASE_DB_URL" -f supabase/migrations/000N_description.sql
   ```
3. Verify with `\d table_name` (describe) rather than assuming it worked — `psql -f` does not always fail loudly on every kind of partial failure.

## Inspecting live state

```bash
source apps/web/.env.local
psql "$SUPABASE_DB_URL" -c "\dt public.*"                    # list tables
psql "$SUPABASE_DB_URL" -c "\d table_name"                   # describe a table (columns, indexes, constraints, RLS policies, triggers)
psql "$SUPABASE_DB_URL" -c "select * from table_name limit 5;"
```

## Safety — this is real, live user data

This connection can run anything, including `DROP TABLE`, `DELETE`, `TRUNCATE` with no undo. Direct schema/DDL changes (`CREATE TABLE`, `ALTER TABLE`, adding columns/indexes/policies) are fine to run without asking each time — that's the whole point of this skill. But treat any destructive DATA operation (deleting/updating existing rows, dropping a table or column that has data) the same as any other hard-to-reverse action: confirm with the user first, same as `git push --force` or `rm -rf` would need. Ad-hoc `SELECT` queries for debugging/inspection need no confirmation.

## Context: this project's migration history

- `0001_init.sql` — profiles, items, habits, body_profiles, measurements + RLS
- `0002_sync_payload.sql` — adds `data` payload column to habits/measurements/body_profiles
- `0003_google_calendar.sql` — google_calendar_connections + google_calendar_links (Google Calendar two-way sync)
- `0004_google_calendar_multi_account.sql` — reworks connections to support multiple Google accounts per user; links gain `connection_id`

`items.data`/`habits.data` payloads use a wire format shared with the native Swift app (`SnapshotDTO.swift`) — dates are Cocoa reference-date floats, not ISO strings, and enums (like `ExternalRef.Source`) are closed/strict on the Swift side with no unknown-value fallback. Adding a new field that Swift also needs to read requires updating the Swift decoder too, which is out of scope for this skill (web-only) — flag it to the user rather than assuming a web-only schema change is safe for the native app's sync.
