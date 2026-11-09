-- ============================================================================
-- Migration 0202: deleting an account also erases its phone links (script 223)
--
-- ADDITIVE ONLY. One function replaced (same name, same argument, same
-- result, still security definer and closed to the clients). Nothing is
-- written, changed or removed by the migration itself.
--
-- Why: Google Play's account-deletion policy requires the data tied to the
-- account to be deleted, or the retention to be disclosed with its reason.
-- 0197 links each account to the install (a random id kept as md5) it was
-- seen on. After 0178 that row still tied a deleted account's internal id
-- to a phone. It is erased now.
--
-- Kept on purpose, and disclosed on the deletion and privacy pages:
-- prediction.install_claims (the first account that predicted a match from
-- an install). It holds no name and no e-mail, and the rule "never two
-- accounts predicting the same match on one phone" needs it to stay while
-- the match counts.
--
-- Everything else is 0178 unchanged. Safe to re-run.
-- ============================================================================

begin;

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
  'to the phones he used): suspended for good, e-mail, name, picture, push '
  'tokens, phone links and sign-in erased, points and predictions kept. '
  'True when deleted now.';

revoke all on function identity.delete_account(uuid)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0202_account_deletion_devices')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0202_account_deletion_devices';             -- 1 row
-- select has_function_privilege('authenticated',
--   'identity.delete_account(uuid)', 'execute');               -- false
-- select count(*) from identity.install_accounts ia
--   join identity.users u on u.id = ia.user_id
--  where u.deleted_at is not null;                  -- 0 for accounts deleted from now on
