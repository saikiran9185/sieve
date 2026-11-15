-- Sieve Cloud: first schema (15 Nov 2026).
--
-- The browser keeps its library in IndexedDB (web/db.js): 13 stores such as sources,
-- evidence, tags, projects, columns, cells, frames ... The cloud mirrors those records
-- as they are, one row per record, so nothing is translated and nothing is lost.
-- The local copy stays the working copy; this is sync and backup on top of it.
-- PDF bytes do not live here: they go to the private `pdfs` storage bucket.

create table public.records (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  store      text        not null check (store ~ '^[A-Za-z]{1,32}$'),   -- IndexedDB store name
  key        text        not null check (length(key) between 1 and 200), -- record key in that store
  data       jsonb       not null default '{}'::jsonb,                   -- the record, as stored locally
  updated_at timestamptz not null default now(),                         -- set by the server, see trigger
  deleted_at timestamptz,                                                -- soft delete so deletes sync too
  primary key (user_id, store, key)
);

comment on table public.records is
  'One row per Sieve record, mirrored from the browser/Mac library. Owner-only (RLS).';

-- Pulls ask "what changed since I last looked", per account.
create index records_user_updated_idx on public.records (user_id, updated_at);

-- The server's clock decides updated_at, never the device's, so a laptop with a wrong
-- clock cannot hide its edits from (or bury edits from) another device.
create or replace function public.records_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger records_touch
before insert or update on public.records
for each row execute function public.records_touch();

-- Row-level security: an account sees and changes only its own rows. The publishable key
-- in web/supabase-config.js is public, so this is what actually keeps reviews private.
alter table public.records enable row level security;

create policy "records: owner can read"
  on public.records for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "records: owner can insert"
  on public.records for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "records: owner can update"
  on public.records for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "records: owner can delete"
  on public.records for delete to authenticated
  using ((select auth.uid()) = user_id);

-- PDFs: private bucket, one folder per account, each file named by its SHA-256 so the
-- same paper is never stored twice. Path: {user_id}/{sha256}.pdf
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pdfs', 'pdfs', false, 52428800, array['application/pdf']);  -- 50 MB per file

create policy "pdfs: owner can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'pdfs' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "pdfs: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'pdfs' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "pdfs: owner can replace"
  on storage.objects for update to authenticated
  using (bucket_id = 'pdfs' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'pdfs' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "pdfs: owner can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'pdfs' and (storage.foldername(name))[1] = (select auth.uid())::text);
