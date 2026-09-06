-- LEO • Supabase schema — v10
-- Read-only, one-way Jira connection: a personal Atlassian API token (not
-- OAuth — see api/jira-search.ts's doc comment for why) plus the site/email
-- it belongs to. One row per user (unlike google_calendar_connections,
-- there's no multi-account requirement here), fetched ad hoc from the Jira
-- page — not part of the core sync engine, so left out of supabase_realtime,
-- same treatment as google_calendar_connections (0003) and project_notes
-- (0009).

create table if not exists public.jira_connections (
    user_id    uuid primary key references auth.users(id) on delete cascade,
    site_url   text not null,   -- e.g. "yourteam.atlassian.net" — no scheme, no trailing slash
    email      text not null,   -- the Atlassian account the API token belongs to
    api_token  text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger jira_connections_set_updated_at
  before update on public.jira_connections
  for each row execute function public.set_updated_at();

alter table public.jira_connections enable row level security;

create policy "jira_connections_owner_all" on public.jira_connections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
