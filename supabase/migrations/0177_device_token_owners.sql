-- ============================================================================
-- Migration 0177: every account a push token was registered for (script 102)
--
-- ADDITIVE ONLY. One new table, filled once from notification.device_tokens.
-- No row of any existing table is changed or removed.
--
-- Why: a push token belongs to one install of the app. When a player signs
-- out and signs in as someone else on the same phone, the app registers the
-- same token for the second account, and notification.device_tokens (0039)
-- rebinds it (or, after a sign-out removed it, adds it again), keeping no
-- trace of the first account. Two accounts played from one phone were found
-- on 2026-10-17 only through the referral install marks (0073), which a few
-- screens record.
--
-- * notification.device_token_owners: one row per (token, account) ever
--   registered. The token is kept as md5 only: it is a grouping key here,
--   never used to send. first_seen is when that account first registered it.
-- * Filled once from today's notification.device_tokens; from then on the
--   upsert of PostgresDeviceTokenRepository adds the row in the same
--   statement (ON CONFLICT DO NOTHING).
-- * A sign-out or a dead token leaves the rows; a removed account takes its
--   rows with it (on delete cascade).
-- * Backend-only, as 0039: RLS on, nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that writes it. Safe to re-run.
-- ============================================================================

begin;

create table if not exists notification.device_token_owners (
  token_key  text        not null,
  user_id    uuid        not null,
  platform   text        not null,
  first_seen timestamptz not null default now(),
  constraint device_token_owners_pkey primary key (token_key, user_id),
  constraint device_token_owners_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete cascade
);

comment on table notification.device_token_owners is
  'Every account a push token was registered for (script 102). token_key is '
  'md5 of the token, a grouping key only. Two accounts on one token_key were '
  'signed in on the same install of the app. Backend-only.';

create index if not exists device_token_owners_user_id_idx
  on notification.device_token_owners (user_id);

insert into notification.device_token_owners
  (token_key, user_id, platform, first_seen)
select md5(dt.token), dt.user_id, dt.platform, dt.updated_at
from notification.device_tokens dt
on conflict (token_key, user_id) do nothing;

alter table notification.device_token_owners enable row level security;

revoke select, insert, update, delete, truncate
  on notification.device_token_owners
  from anon, authenticated;

drop policy if exists device_token_owners_no_client_read
  on notification.device_token_owners;
create policy device_token_owners_no_client_read
  on notification.device_token_owners
  for select
  to anon, authenticated
  using (false);

insert into ops.applied_migrations (version)
values ('0177_device_token_owners')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0177_device_token_owners';                 -- 1 row
-- select count(*) from notification.device_token_owners;       -- >= tokens
