-- LEO • Supabase schema — v1
-- Multi-tenant from day one: every row is scoped to a user via `user_id`, and
-- Row Level Security guarantees a client can only ever read/write its own rows.
-- This is the SaaS foundation: adding more users requires no schema change, and
-- org/workspace tenancy can be layered on later (see NOTES at the bottom).
--
-- Design choices for reliable device sync:
--   • `updated_at` on every table (auto-maintained) → clients pull deltas with
--     `where updated_at > <last_sync>`.
--   • Soft deletes via `deleted_at` → deletions propagate to other devices
--     instead of silently vanishing (a row that's gone can't be synced).
--   • Items use a single table with a `kind` discriminator + JSONB payload,
--     mirroring LEO's heterogeneous `Item` protocol and its snapshot DTOs
--     (anchor/completion are already encoded blobs in the app).

-- ─────────────────────────────────────────────────────────────────────────────
-- Extensions
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared helper: keep updated_at fresh on every write
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles — one row per auth user (the tenant root)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
    id                uuid primary key references auth.users(id) on delete cascade,
    email             text,
    display_name      text,
    -- SaaS billing hooks (free today; ready for plans/limits later)
    subscription_tier text not null default 'free',   -- free | pro | team
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

-- Auto-create a profile whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- items — tasks, events, reminders, alarms, workouts, meals, habit instances
-- (mirrors LEO's `Item` protocol; type-specific fields live in `data`)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.items (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    kind        text not null,                 -- task | event | reminder | alarm | workout | meal | habitInstance
    title       text not null default '',
    notes       text,
    importance  smallint not null default 1,   -- 0 low … 3 urgent
    anchor      jsonb not null default '{"type":"untimed"}'::jsonb,
    completion  jsonb not null default '{"type":"open"}'::jsonb,
    tags        jsonb not null default '[]'::jsonb,
    data        jsonb not null default '{}'::jsonb,   -- per-kind extras (recipeID, plannedExercises, deadline, habitID, …)
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz                          -- soft delete for sync
);

create index if not exists items_user_updated_idx on public.items (user_id, updated_at desc);
create index if not exists items_user_kind_idx    on public.items (user_id, kind);

create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- habits — the recurring-habit definitions
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.habits (
    id                       uuid primary key default gen_random_uuid(),
    user_id                  uuid not null references auth.users(id) on delete cascade,
    name                     text not null,
    frequency                jsonb not null default '{}'::jsonb,
    time_hint                text,
    target_duration_seconds  double precision,
    forgiveness              jsonb,
    recurrence_rule          text not null default '',
    is_archived              boolean not null default false,
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now(),
    deleted_at               timestamptz
);

create index if not exists habits_user_updated_idx on public.habits (user_id, updated_at desc);

create trigger habits_set_updated_at
  before update on public.habits
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- body_profiles — one fitness profile per user
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.body_profiles (
    user_id          uuid primary key references auth.users(id) on delete cascade,
    height_cm        double precision,
    weight_kg        double precision,
    sex              text,
    birth_date       date,
    body_fat_pct     double precision,
    activity_level   text,
    goal_weight_kg   double precision,
    goal_physique    text,
    target_date      date,
    diet_type        text,
    allergies        jsonb not null default '[]'::jsonb,
    intolerances     jsonb not null default '[]'::jsonb,
    medical_flags    jsonb not null default '[]'::jsonb,
    unit_preference  text not null default 'metric',
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);

create trigger body_profiles_set_updated_at
  before update on public.body_profiles
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- measurements — body-weight / body-fat log
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.measurements (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    weight_kg    double precision,
    body_fat_pct double precision,
    source       text not null default 'manual',
    measured_at  timestamptz not null default now(),
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    deleted_at   timestamptz
);

create index if not exists measurements_user_updated_idx on public.measurements (user_id, updated_at desc);

create trigger measurements_set_updated_at
  before update on public.measurements
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security — the multi-tenant guarantee
-- Each table: a user may only touch rows where user_id = auth.uid()
-- (profiles & body_profiles key on the PK which IS the user id).
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles      enable row level security;
alter table public.items         enable row level security;
alter table public.habits        enable row level security;
alter table public.body_profiles enable row level security;
alter table public.measurements  enable row level security;

-- profiles
create policy "profiles_self_select" on public.profiles for select using (auth.uid() = id);
create policy "profiles_self_modify" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- generic owner policies for the user_id tables
create policy "items_owner_all"        on public.items        for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "habits_owner_all"       on public.habits       for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "measurements_owner_all" on public.measurements for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "body_profiles_owner_all" on public.body_profiles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime — broadcast row changes to subscribed clients (RLS still applies,
-- so a device only receives its own rows).
-- ─────────────────────────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.items;
alter publication supabase_realtime add table public.habits;
alter publication supabase_realtime add table public.body_profiles;
alter publication supabase_realtime add table public.measurements;

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTES — extending to org/workspace SaaS later (no rewrite required)
--   1. Add `public.workspaces(id, owner_id, name, …)` and
--      `public.workspace_members(workspace_id, user_id, role)`.
--   2. Add nullable `workspace_id uuid` to the data tables.
--   3. Swap the owner policies for: `using (auth.uid() = user_id OR workspace_id in
--      (select workspace_id from workspace_members where user_id = auth.uid()))`.
--   Personal data keeps working (workspace_id null); shared data flows by membership.
-- ─────────────────────────────────────────────────────────────────────────────
