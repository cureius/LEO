-- LEO • Supabase schema — v3
-- Google Calendar two-way sync: OAuth tokens + item<->event linking.
--
-- The link table is deliberately SEPARATE from items.data rather than an
-- addition to ExternalRef (the field the native Swift app already uses for
-- EventKit-mirrored items). Swift's ExternalRef.Source is a closed enum
-- with a single case (`case eventKit`) and no unrecognized-value fallback —
-- widening it to include a Google-only value risks that row failing to
-- decode on iPhone/Mac. Keeping the mapping here means a Google-linked item
-- looks like an ordinary LEO-native event to every other client; only the
-- web app's sync engine consults this table at all.

-- ─────────────────────────────────────────────────────────────────────────────
-- google_calendar_connections — one row per user, the OAuth tokens
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.google_calendar_connections (
    user_id       uuid primary key references auth.users(id) on delete cascade,
    access_token  text not null,
    refresh_token text not null,
    expires_at    timestamptz not null,
    calendar_id   text not null default 'primary',
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create trigger google_calendar_connections_set_updated_at
  before update on public.google_calendar_connections
  for each row execute function public.set_updated_at();

alter table public.google_calendar_connections enable row level security;
create policy "google_calendar_connections_owner_all" on public.google_calendar_connections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- google_calendar_links — item_id <-> Google event id, one row per synced event
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.google_calendar_links (
    item_id            uuid primary key references public.items(id) on delete cascade,
    user_id            uuid not null references auth.users(id) on delete cascade,
    google_event_id    text not null,
    google_updated_at  timestamptz,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now()
);

create index if not exists google_calendar_links_user_idx on public.google_calendar_links (user_id);
create unique index if not exists google_calendar_links_event_idx on public.google_calendar_links (user_id, google_event_id);

create trigger google_calendar_links_set_updated_at
  before update on public.google_calendar_links
  for each row execute function public.set_updated_at();

alter table public.google_calendar_links enable row level security;
create policy "google_calendar_links_owner_all" on public.google_calendar_links
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
