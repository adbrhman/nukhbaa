-- End-to-end test for migration 0086: an invitation is refused from the
-- browser (no install id) and from the inviter's own phone, accepted from
-- another phone even on the same network, and a refusal writes nothing.
-- Rolled back at the end.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

create function pg_temp.mk_user(n int, created timestamptz) returns uuid
language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8086-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, 'p' || n || '@t.io', created);
  insert into identity.users (id, email, display_name, created_at)
  values (v, 'p' || n || '@t.io', 'Phone ' || n, created);
  return v;
end $$;

update gamification.feature_flags set enabled = true where flag_key = 'referrals';

do $$
declare
  inviter uuid := pg_temp.mk_user(1, '2026-09-01 10:00+03');
  web_user uuid := pg_temp.mk_user(2, '2026-10-01 10:00+03');
  same_phone uuid := pg_temp.mk_user(3, '2026-10-01 10:00+03');
  friend uuid := pg_temp.mk_user(4, '2026-10-01 10:00+03');
  code text := gamification.ensure_referral_code(inviter);
begin
  -- The inviter opened the invitation page in the app on phone A.
  perform gamification.mark_referral_install(inviter, 'phone-a-install-0001', '2026-10-01 09:00+03');

  perform pg_temp.check(
    gamification.claim_referral(web_user, code, '5.5.5.5', null, '2026-10-01 11:00+03') = 'app_required'
    and gamification.claim_referral(web_user, code, '5.5.5.5', '  ', '2026-10-01 11:00+03') = 'app_required',
    'a claim from the browser (no install id) is refused');

  perform pg_temp.check(
    gamification.claim_referral(same_phone, code, '5.5.5.5', 'phone-a-install-0001', '2026-10-01 11:00+03') = 'same_device',
    'a claim from the inviter''s own phone is refused');

  perform pg_temp.check(
    not exists (select 1 from gamification.referrals r where r.invitee_id in (web_user, same_phone)),
    'a refused claim records nothing');

  perform pg_temp.check(
    gamification.claim_referral(friend, code, '5.5.5.5', 'phone-b-install-0002', '2026-10-01 11:00+03') = 'claimed',
    'another phone on the same network is accepted');

  perform pg_temp.check(
    gamification.claim_referral(web_user, code, '5.5.5.5', 'phone-c-install-0003', '2026-10-01 12:00+03') = 'claimed',
    'after a browser refusal, the app on its own phone can still claim within 24 hours');

  perform pg_temp.check(
    gamification.claim_referral(same_phone, 'NOTACODE', null, null, '2026-10-01 11:00+03') = 'invalid_code',
    'the existing checks still come first');
end $$;

rollback;
