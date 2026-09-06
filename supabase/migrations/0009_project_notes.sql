-- LEO • Supabase schema — v9
-- A "project" has no dedicated row anywhere (see domain/projects.ts's doc
-- comment — it's purely a tag name shared across items), so there was
-- nowhere to attach a project-level note. This is the smallest table that
-- fixes that: one markdown doc per (user, project name), matched by name the
-- same way items already match a project by tag name rather than by id.
-- Fetched ad hoc from the project detail page, not part of the core sync
-- engine — same treatment as google_calendar_connections (0003), so it's
-- left out of supabase_realtime.

create table if not exists public.project_notes (
    user_id      uuid not null references auth.users(id) on delete cascade,
    project_name text not null,
    notes        text not null default '',
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    primary key (user_id, project_name)
);

create trigger project_notes_set_updated_at
  before update on public.project_notes
  for each row execute function public.set_updated_at();

alter table public.project_notes enable row level security;

create policy "project_notes_owner_all" on public.project_notes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
