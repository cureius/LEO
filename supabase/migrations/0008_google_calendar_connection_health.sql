-- LEO • Supabase schema — v8
-- google_calendar_connections had no way to tell a healthy connection from
-- one whose refresh token has been expired/revoked by Google (e.g. the
-- 7-day forced expiry Google applies to OAuth clients still in "Testing"
-- publishing status) — a dead connection just failed the same generic way
-- on every sync pass forever, with nothing in the schema or UI to flag it.

alter table public.google_calendar_connections
  add column if not exists needs_reauth boolean not null default false,
  add column if not exists last_sync_error text;
