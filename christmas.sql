-- Christmas invite. Run once in Supabase → SQL Editor (same project as the birthday invite).
-- Safe to run more than once. Uses the existing owners table, is_owner() and photos bucket.

-- One row per event page, keyed by a short name. Anyone can read; only owners can change.
create table if not exists public.events (
  slug text primary key check (slug ~ '^[a-z0-9-]{1,40}$'),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.events enable row level security;
grant select on public.events to anon, authenticated;
grant insert, update on public.events to authenticated;

drop policy if exists "anyone reads events" on public.events;
create policy "anyone reads events" on public.events
  for select to anon, authenticated using (true);

drop policy if exists "owners add events" on public.events;
create policy "owners add events" on public.events
  for insert to authenticated with check (public.is_owner());

drop policy if exists "owners update events" on public.events;
create policy "owners update events" on public.events
  for update to authenticated using (public.is_owner()) with check (public.is_owner());

-- The Christmas party, with placeholders. Enter the real details in christmas/owner.html.
insert into public.events (slug, data) values ('christmas', '{
  "title":"The Family Clan Christmas Party","greeting":"Merry Christmas",
  "date":"2026-12-20","start":"18:00","end":"","timezone":"Asia/Manila",
  "venue":"Party Venue","address":"123 Example Street, Example City",
  "note":"Bring a dish to share and a wrapped gift for the exchange. Festive outfits encouraged.",
  "signoff":"with love,","host":"Host Name","photos":[],"driveFeed":""
}'::jsonb) on conflict (slug) do nothing;
