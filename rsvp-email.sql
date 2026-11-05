-- Email the owner every time an RSVP is saved. Run in Supabase → SQL Editor, AFTER rsvps.sql.
--
-- Before running this, store two secrets in the Vault yourself (SQL Editor, one line each,
-- with your real values in place of the placeholders — never commit them or share them):
--   select vault.create_secret('YOUR_RESEND_API_KEY', 'resend_api_key');
--   select vault.create_secret('YOUR_EMAIL_ADDRESS',  'rsvp_notify_email');
--
-- Sending uses Resend's shared test sender (onboarding@resend.dev), which can only deliver
-- to the email address your Resend account was created with. Use that address above.

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_rsvp() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  api_key  text;
  to_email text;
  subj     text;
  msg      text;
begin
  select decrypted_secret into api_key  from vault.decrypted_secrets where name = 'resend_api_key';
  select decrypted_secret into to_email from vault.decrypted_secrets where name = 'rsvp_notify_email';
  if api_key is null or to_email is null then
    return new;  -- not set up yet: save the RSVP, skip the email
  end if;

  if new.attending then
    subj := 'RSVP: ' || new.name || ' is coming';
    msg  := new.name || ' is coming with ' || new.adults || ' adult(s) and ' || new.kids || ' kid(s).';
  else
    subj := 'RSVP: ' || new.name || ' can''t make it';
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

drop trigger if exists rsvp_email on public.rsvps;
create trigger rsvp_email
  after insert on public.rsvps
  for each row execute function public.notify_rsvp();
