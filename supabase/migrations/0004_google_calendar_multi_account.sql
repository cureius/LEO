-- LEO • Supabase schema — v4
-- Multiple Google Calendar accounts per user. 0003 made google_calendar_connections
-- keyed on user_id itself (primary key) — structurally one connection per LEO
-- user. This gives it a real surrogate id instead and lets google_calendar_links
-- point at WHICH connection an event came from, since with more than one
-- connected account, "the" connection is no longer well-defined.

-- ─────────────────────────────────────────────────────────────────────────────
-- google_calendar_connections — id becomes the primary key; user_id is now
-- just an indexed owner column, so a user can have many rows.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.google_calendar_connections drop constraint google_calendar_connections_pkey;

alter table public.google_calendar_connections
  add column if not exists id uuid not null default gen_random_uuid(),
  add column if not exists google_email text;

alter table public.google_calendar_connections add primary key (id);

create index if not exists google_calendar_connections_user_idx on public.google_calendar_connections (user_id);

-- Reconnecting the same Google account (e.g. after a token issue) should
-- update its existing row, not silently accumulate a duplicate connection
-- for the same account.
create unique index if not exists google_calendar_connections_user_email_idx
  on public.google_calendar_connections (user_id, google_email);

-- ─────────────────────────────────────────────────────────────────────────────
-- google_calendar_links — needs to know which connection an event belongs to
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.google_calendar_links
  add column if not exists connection_id uuid references public.google_calendar_connections(id) on delete cascade;

-- Backfill: anyone who already has links from before this migration only
-- ever had ONE connection (0003's schema made more than one impossible), so
-- that connection is unambiguously theirs.
update public.google_calendar_links l
set connection_id = c.id
from public.google_calendar_connections c
where l.connection_id is null and l.user_id = c.user_id;

alter table public.google_calendar_links alter column connection_id set not null;

-- Was (user_id, google_event_id) — two different Google accounts could in
-- principle produce colliding event ids, and more importantly the same
-- LEO user now legitimately has one links-row-set per connection, not per
-- account-agnostic user.
drop index if exists google_calendar_links_event_idx;
create unique index if not exists google_calendar_links_event_idx
  on public.google_calendar_links (connection_id, google_event_id);
