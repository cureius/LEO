-- Tracks which Google event a link belongs to a recurring series of, so the
-- web app can (a) prune far-future recurring occurrences it doesn't need to
-- pre-materialize yet, and (b) show a "repeats" indicator without touching
-- the items table's wire format shared with the native Swift app.
alter table public.google_calendar_links
  add column if not exists google_recurring_event_id text;
