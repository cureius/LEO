-- User-defined rules that auto-file items into a project based on simple
-- attendee/title/notes/location conditions (e.g. "attendee email contains
-- @mycompany.com" -> "Office" project). Web-only, no native counterpart —
-- explicit typed columns rather than the items/habits jsonb `data` payload
-- convention, since that convention exists specifically for tables shared
-- with the native Swift app's wire format.
create table if not exists public.automation_rules (
    id                    uuid primary key default gen_random_uuid(),
    user_id               uuid not null references auth.users(id) on delete cascade,
    name                  text not null,
    enabled               boolean not null default true,
    conditions            jsonb not null default '[]'::jsonb,  -- [{field, contains}, ...] AND'd together
    target_project_name   text not null,
    target_project_color  text not null,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    deleted_at            timestamptz
);

create index if not exists automation_rules_user_idx on public.automation_rules (user_id);

create trigger automation_rules_set_updated_at
  before update on public.automation_rules
  for each row execute function public.set_updated_at();

alter table public.automation_rules enable row level security;

create policy "automation_rules_owner_all" on public.automation_rules
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter publication supabase_realtime add table public.automation_rules;
