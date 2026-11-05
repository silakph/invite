-- RSVP replies. Run once in Supabase → SQL Editor (after setup.sql).
-- Guests can only ADD a reply. Only owners (see public.owners) can read or delete them.

create table if not exists public.rsvps (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  attending boolean not null,
  adults int not null default 0 check (adults between 0 and 10),
  kids int not null default 0 check (kids between 0 and 10)
);
alter table public.rsvps enable row level security;

grant insert on public.rsvps to anon, authenticated;
grant select, delete on public.rsvps to authenticated;

drop policy if exists "guests add a reply" on public.rsvps;
create policy "guests add a reply" on public.rsvps
  for insert to anon, authenticated with check (true);

drop policy if exists "owners read replies" on public.rsvps;
create policy "owners read replies" on public.rsvps
  for select to authenticated using (public.is_owner());

drop policy if exists "owners delete replies" on public.rsvps;
create policy "owners delete replies" on public.rsvps
  for delete to authenticated using (public.is_owner());
