-- Family links: one private link per family, so everyone in a family sees (and can change)
-- the same reply. Run once in Supabase → SQL Editor, after rsvps-v2.sql. Safe to run more than once.

-- 1. The families you invite. Only owners can see or change this list.
create table if not exists public.families (
  code text primary key check (code ~ '^[A-Za-z0-9]{8,24}$'),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  created_at timestamptz not null default now()
);
alter table public.families enable row level security;
grant select, insert, update, delete on public.families to authenticated;

drop policy if exists "owners read families" on public.families;
create policy "owners read families" on public.families
  for select to authenticated using (public.is_owner());
drop policy if exists "owners add families" on public.families;
create policy "owners add families" on public.families
  for insert to authenticated with check (public.is_owner());
drop policy if exists "owners edit families" on public.families;
create policy "owners edit families" on public.families
  for update to authenticated using (public.is_owner()) with check (public.is_owner());
drop policy if exists "owners delete families" on public.families;
create policy "owners delete families" on public.families
  for delete to authenticated using (public.is_owner());

-- 2. Each reply remembers which family link it came from (empty for the plain link).
alter table public.rsvps add column if not exists family_code text
  references public.families (code) on delete set null;
create index if not exists rsvps_family_code_idx on public.rsvps (family_code);

-- 3. A family link can look up ONLY its own family's name and latest reply — nothing else.
create or replace function public.family_status(p_code text) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'label', f.label,
    'reply', (select to_jsonb(x) from (
                select r.name, r.attending, r.adults, r.kids, r.created_at
                from public.rsvps r where r.family_code = f.code
                order by r.created_at desc limit 1) x))
  from public.families f where f.code = p_code
$$;
grant execute on function public.family_status(text) to anon, authenticated;

-- 4. Email: say "Updated RSVP" when the family (or device) already replied, and name the family.
create or replace function public.notify_rsvp() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  api_key  text;
  to_email text;
  fam      text;
  who      text;
  subj     text;
  msg      text;
  prefix   text := 'RSVP: ';
begin
  select decrypted_secret into api_key  from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into to_email from vault.decrypted_secrets where name = 'rsvp_notify_email';
  if api_key is null or to_email is null then
    return new;
  end if;

  if new.family_code is not null then
    select label into fam from public.families where code = new.family_code;
  end if;
  who := new.name || coalesce(' (' || fam || ')', '');

  if exists (
    select 1 from public.rsvps r
    where r.id <> new.id
      and ((new.family_code is not null and r.family_code = new.family_code)
        or (new.device_id is not null and r.device_id = new.device_id))
  ) then
    prefix := 'Updated RSVP: ';
  end if;

  if new.attending then
    subj := prefix || who || ' is coming';
    msg  := who || ' is coming with ' || new.adults || ' adult(s) and ' || new.kids || ' kid(s).';
  else
    subj := prefix || who || ' can''t make it';
    msg  := who || ' can''t make it.';
  end if;

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body    := jsonb_build_object(
                 'from', 'Birthday RSVP <onboarding@resend.dev>',
                 'to', jsonb_build_array(to_email),
                 'subject', subj,
                 'text', msg || E'\n\nSee the full list: https://silakph.github.io/invite/?owner')
  );
  return new;
end
$$;

revoke all on function public.notify_rsvp() from public, anon, authenticated;
