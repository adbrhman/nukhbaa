-- End-to-end test for migration 0109: a claim from an account whose
-- mailbox is another account's (Gmail dots, a '+' tag, letter case) is
-- refused as duplicate_account and records nothing; a distinct mailbox is
-- still accepted. Rolled back at the end.
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

create function pg_temp.mk_user(n int, mail text, created timestamptz) returns uuid
language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8109-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, mail, created);
  insert into identity.users (id, email, display_name, created_at)
  values (v, mail, 'Mail ' || n, created);
  return v;
end $$;

update gamification.feature_flags set enabled = true where flag_key = 'referrals';

do $$
declare
  inviter uuid := pg_temp.mk_user(1, 'ahmad.ali@gmail.com', '2026-09-01 10:00+03');
  other uuid := pg_temp.mk_user(2, 'sara@yahoo.com', '2026-09-02 10:00+03');
  alias_dots uuid := pg_temp.mk_user(3, 'AhmadAli+2@googlemail.com', '2026-10-01 10:00+03');
  alias_tag uuid := pg_temp.mk_user(4, 'Sara+nukhba@Yahoo.com', '2026-10-01 10:00+03');
  friend uuid := pg_temp.mk_user(5, 'ahmad.ali2@gmail.com', '2026-10-01 10:00+03');
  code text := gamification.ensure_referral_code(inviter);
begin
  perform pg_temp.check(
    gamification.normalized_email('N.Ame+1@GoogleMail.com') = 'name@gmail.com'
    and gamification.normalized_email('Ali+x@Yahoo.com') = 'ali@yahoo.com'
    and gamification.normalized_email('a.b@outlook.com') = 'a.b@outlook.com'
    and gamification.normalized_email(null) is null,
    'addresses fold as mail providers deliver them');

  perform pg_temp.check(
    gamification.claim_referral(alias_dots, code, '5.5.5.5', 'install-3', '2026-10-01 11:00+03')
      = 'duplicate_account',
    'the inviter''s own Gmail without the dot and with a + tag is refused');

  perform pg_temp.check(
    gamification.claim_referral(alias_tag, code, '5.5.5.5', 'install-4', '2026-10-01 11:00+03')
      = 'duplicate_account',
    'a + tag on another account''s mailbox is refused');

  perform pg_temp.check(
    not exists (select 1 from gamification.referrals r
                 where r.invitee_id in (alias_dots, alias_tag)),
    'a refused claim records nothing');

  perform pg_temp.check(
    gamification.claim_referral(friend, code, '5.5.5.5', 'install-5', '2026-10-01 11:00+03')
      = 'claimed',
    'a mailbox of its own is accepted');

  perform pg_temp.check(
    gamification.claim_referral(alias_dots, 'NOTACODE', null, null, '2026-10-01 11:00+03')
      = 'invalid_code',
    'the earlier checks still come first');
end $$;

rollback;
