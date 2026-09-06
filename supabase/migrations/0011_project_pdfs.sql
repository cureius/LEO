-- LEO • Supabase schema — v11
-- Per-project PDF library: upload PDFs to a project (still just a tag name —
-- see 0009_project_notes.sql's doc comment), read them in-app, and highlight
-- passages. Same ad-hoc-table treatment as project_notes: keyed by
-- (user_id, project_name), fetched directly by the web app, not part of the
-- core sync engine.
--
-- project_pdfs holds file metadata; the bytes live in Storage bucket
-- 'project-pdfs' at '{user_id}/{project_pdfs.id}.pdf'. pdf_highlights is a
-- child of project_pdfs (one PDF, many highlighted passages) — rects are
-- stored as fractions (0..1, top-left origin) of the page so they're
-- independent of render scale.

create table public.project_pdfs (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    project_name text not null,
    file_name    text not null,
    storage_path text not null,
    size_bytes   bigint not null,
    page_count   int,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

create index project_pdfs_user_project_idx on public.project_pdfs (user_id, project_name);

create trigger project_pdfs_set_updated_at
  before update on public.project_pdfs
  for each row execute function public.set_updated_at();

alter table public.project_pdfs enable row level security;

create policy "project_pdfs_owner_all" on public.project_pdfs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table public.pdf_highlights (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    pdf_id      uuid not null references public.project_pdfs(id) on delete cascade,
    page_number int not null,
    rects       jsonb not null,
    color       text not null,
    quote       text not null,
    note        text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create index pdf_highlights_pdf_id_idx on public.pdf_highlights (pdf_id);

create trigger pdf_highlights_set_updated_at
  before update on public.pdf_highlights
  for each row execute function public.set_updated_at();

alter table public.pdf_highlights enable row level security;

create policy "pdf_highlights_owner_all" on public.pdf_highlights
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Storage: private bucket, one folder per user (folder name = auth.uid())
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('project-pdfs', 'project-pdfs', false)
on conflict (id) do nothing;

create policy "project_pdfs_storage_owner_all" on storage.objects
  for all
  using (bucket_id = 'project-pdfs' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'project-pdfs' and (storage.foldername(name))[1] = auth.uid()::text);
