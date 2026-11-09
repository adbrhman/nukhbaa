-- ============================================================================
-- Migration 0203: deleting an account also erases its invitation data
-- (script 231)
--
-- Two functions are replaced (same names, same arguments, same results) and
-- the rows of ALREADY deleted accounts are erased once. Nothing of a live
-- account is written, changed or removed.
--
-- Why: the invitations were removed (0185, 0186) but their tables stayed
-- stored as they were (protocol section 5). gamification.referrals and
-- gamification.referral_install_marks hold a hashed IP and a hashed install
-- id beside an account id, and gamification.referral_codes holds the
-- account's code. Google Play's account-deletion policy asks for the data
-- tied to a deleted account to be deleted
-- (support.google.com/googleplay/android-developer/answer/13327111); the
-- owner chose to erase it (2026-11-09), not to disclose keeping it.
--
-- Kept: the points and predictions (anonymous record, disclosed on the
-- privacy page) and the duel rows, which hold participant ids only, like the
-- predictions do. The points ledger keeps its referral_* events: they hold a
-- user id and a number, no hash and no code.
--
-- How: the three tables are append-only (reject_referral_mutation). That guard
-- now lets a DELETE through only when the account of the row is deleted
-- (identity.users.deleted_at), so no live account's row can be touched.
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function gamification.reject_referral_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_gone boolean := false;
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'referrals' then
      select exists (
        select 1 from identity.users u
         where u.id in (old.invitee_id, old.referrer_id)
           and u.deleted_at is not null
      ) into v_gone;
    else
      select exists (
        select 1 from identity.users u
         where u.id = old.user_id and u.deleted_at is not null
      ) into v_gone;
    end if;
    if v_gone then
      return old;
    end if;
  end if;
  raise exception '% is append-only: % is forbidden', tg_table_name, tg_op
    using errcode = 'check_violation';
end;
$$;

-- 0202's function, plus the invitation rows of the account.
create or replace function identity.delete_account(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update identity.users u
     set status = 'suspended',
         deleted_at = now(),
         email = null,
         display_name = null,
         avatar_bytes = null,
         avatar_mime = null,
         avatar_updated_at = null
   where u.id = p_user_id
     and u.deleted_at is null
     and u.role = 'user';
  if not found then
    return false;
  end if;
  delete from notification.device_tokens where user_id = p_user_id;
  delete from notification.device_token_owners where user_id = p_user_id;
  delete from notification.notification_preferences where user_id = p_user_id;
  delete from identity.user_favorite_teams where user_id = p_user_id;
  delete from identity.install_accounts where user_id = p_user_id;
  delete from gamification.referral_install_marks where user_id = p_user_id;
  delete from gamification.referrals
   where invitee_id = p_user_id or referrer_id = p_user_id;
  delete from gamification.referral_codes where user_id = p_user_id;
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
  delete from auth.identities where user_id = p_user_id;
  update auth.users
     set email = null,
         phone = null,
         raw_user_meta_data = '{}'::jsonb,
         banned_until = timestamptz '2999-12-31 00:00:00+00',
         updated_at = now()
   where id = p_user_id;
  return true;
end;
$$;

comment on function identity.delete_account(uuid) is
  'A player deletes his own account (0178, audit M-05; 0202 adds the links '
  'to the phones he used; 0203 the invitation rows): suspended for good, '
  'e-mail, name, picture, push tokens, phone links, invitation rows and '
  'sign-in erased, points and predictions kept. True when deleted now.';

revoke all on function identity.delete_account(uuid)
  from public, anon, authenticated;

-- Once: the invitation rows of accounts deleted before this migration.
delete from gamification.referral_install_marks m
 using identity.users u
 where u.id = m.user_id and u.deleted_at is not null;

delete from gamification.referrals r
 where exists (
   select 1 from identity.users u
    where u.id in (r.invitee_id, r.referrer_id)
      and u.deleted_at is not null
 );

delete from gamification.referral_codes c
 using identity.users u
 where u.id = c.user_id and u.deleted_at is not null;

insert into ops.applied_migrations (version)
values ('0203_referral_data_erased_with_account')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
--  select version from ops.applied_migrations
--   where version = '0203_referral_data_erased_with_account';       -- 1 row
--  select count(*) from gamification.referrals r
--   join identity.users u on u.id in (r.invitee_id, r.referrer_id)
--  where u.deleted_at is not null;                                  -- 0
--  select count(*) from gamification.referral_install_marks m
--   join identity.users u on u.id = m.user_id
--  where u.deleted_at is not null;                                  -- 0
--  select has_function_privilege('authenticated',
--    'identity.delete_account(uuid)', 'execute');                   -- false
