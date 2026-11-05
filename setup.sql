-- Run once in Supabase → SQL Editor, AFTER creating your own user
-- (Authentication → Users → Add user → your email).

-- 1. Who may edit: whoever is in this table. Not readable through the API.
create table if not exists public.owners (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.owners enable row level security;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.owners where user_id = auth.uid()) $$;

-- Makes every user that exists right now an owner. Run it when you are the only user.
insert into public.owners (user_id) select id from auth.users on conflict do nothing;

-- 2. The invitation details: one row, anyone can read, only owners can change.
create table if not exists public.party (
  id int primary key default 1 check (id = 1),
  data jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.party enable row level security;
grant select on public.party to anon, authenticated;
grant update on public.party to authenticated;

drop policy if exists "anyone reads the invite" on public.party;
create policy "anyone reads the invite" on public.party
  for select to anon, authenticated using (true);

drop policy if exists "owners update the invite" on public.party;
create policy "owners update the invite" on public.party
  for update to authenticated using (public.is_owner()) with check (public.is_owner());

insert into public.party (id, data) values (1, '{
  "name":"Birthday Kid","age":7,"date":"2027-06-12","start":"16:30","end":"19:00",
  "timezone":"Asia/Manila","venue":"Party Venue","address":"123 Example Street, Example City",
  "note":"Come ready to build, play and eat cake. Bright colours encouraged!",
  "rsvpBy":"2027-05-31","rsvpPhone":"0900 000 0000","host":"Host Name","photo":"","photos":[]
}'::jsonb) on conflict (id) do nothing;

-- 3. Photos: public to view, only owners can upload or delete. 5 MB cap per photo.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "owners upload photos" on storage.objects;
create policy "owners upload photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'photos' and public.is_owner());

drop policy if exists "owners delete photos" on storage.objects;
create policy "owners delete photos" on storage.objects
  for delete to authenticated using (bucket_id = 'photos' and public.is_owner());
