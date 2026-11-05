-- RSVP upgrade: remember which device sent each reply, so a changed reply replaces the old one
-- in the owner list instead of being counted twice. Run once in Supabase → SQL Editor,
-- after rsvps.sql and rsvp-email.sql. Safe to run more than once.

alter table public.rsvps add column if not exists device_id text
  check (device_id is null or char_length(device_id) <= 40);
create index if not exists rsvps_device_id_idx on public.rsvps (device_id);

-- Same email as before, but the subject says "Updated RSVP" when a family changes their reply.
create or replace function public.notify_rsvp() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  api_key  text;
  to_email text;
  subj     text;
  msg      text;
  prefix   text := 'RSVP: ';
begin
  select decrypted_secret into api_key  from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into to_email from vault.decrypted_secrets where name = 'rsvp_notify_email';
  if api_key is null or to_email is null then
    return new;
  end if;

  if new.device_id is not null and exists (
    select 1 from public.rsvps r where r.device_id = new.device_id and r.id <> new.id
  ) then
    prefix := 'Updated RSVP: ';
  end if;

  if new.attending then
    subj := prefix || new.name || ' is coming';
    msg  := new.name || ' is coming with ' || new.adults || ' adult(s) and ' || new.kids || ' kid(s).';
  else
    subj := prefix || new.name || ' can''t make it';
    msg  := new.name || ' can''t make it.';
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
