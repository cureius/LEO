-- LEO • Supabase schema — v2
-- Adds a `data` payload column to the remaining synced tables so the client can
-- store the full (lossless) encoded entity, matching how `items.data` works.
-- The typed columns remain for SQL querying; `data` is the sync source of truth.

alter table public.habits        add column if not exists data text;
alter table public.measurements  add column if not exists data text;
alter table public.body_profiles add column if not exists data text;
