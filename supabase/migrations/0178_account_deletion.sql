-- ============================================================================
-- Migration 0178: a player deletes his own account (audit M-05, script 113)
--
-- Google Play requires an app with accounts to let a player delete his own.
-- The owner's decision (M-05, 2026-10-16): deleting anonymises the account
-- and keeps its points and predictions in the record. The account cannot be
-- removed outright: identity.users cascades from auth.users, and the ledger,
-- the participants, the month champions and the duels keep their rows behind
-- on delete restrict keys.
--
-- * identity.users.deleted_at: when the player deleted the account.
-- * identity.delete_account(p_user_id): suspends the account for good (every
--   board and list already leaves suspended accounts out, 0108 and others),
--   erases its e-mail, name and picture (the name falls back to the automatic
--   "Player", 0016/0084), its push tokens and preferences, and its sign-in in
--   auth: sessions, refresh tokens and Google/e-mail identities are deleted,
--   the auth e-mail and phone cleared and the user banned. The same e-mail
--   can then sign up again as a new player. Only a plain player's account
--   ('user'); true when deleted now, false when there was nothing to do.
-- * A trigger keeps a deleted account deleted: no write (an admin
--   reinstatement included) may lift its suspension, clear deleted_at or give
--   it an e-mail again.
-- * Backend-only: nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that calls it. Safe to re-run.
-- ============================================================================

begin;

alter table identity.users
  add column if not exists deleted_at timestamptz;

comment on column identity.users.deleted_at is
  'When the player deleted the account (0178). A deleted account stays '
  'suspended, without e-mail, name or picture; its points and predictions '
  'stay in the record.';

create or replace function identity.guard_deleted_account()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is not null
     and (new.deleted_at is distinct from old.deleted_at
          or new.status <> 'suspended'
          or new.email is not null) then
    raise exception 'account % was deleted', old.id
      using errcode = 'check_violation',
            constraint = 'users_deleted_account_kept';
  end if;
  return new;
end;
$$;

comment on function identity.guard_deleted_account() is
  'Keeps a deleted account deleted (0178): suspended, deleted_at kept, no '
  'e-mail.';

drop trigger if exists users_guard_deleted_account on identity.users;
create trigger users_guard_deleted_account
  before update on identity.users
  for each row execute function identity.guard_deleted_account();

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
  'A player deletes his own account (0178, audit M-05): suspended for good, '
  'e-mail, name, picture, push tokens and sign-in erased, points and '
  'predictions kept. True when deleted now.';

revoke all on function identity.delete_account(uuid)
  from public, anon, authenticated;
revoke all on function identity.guard_deleted_account()
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0178_account_deletion')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0178_account_deletion';                    -- 1 row
-- select count(*) from identity.users where deleted_at is not null;  -- 0
-- select has_function_privilege('authenticated',
--   'identity.delete_account(uuid)', 'execute');               -- false
