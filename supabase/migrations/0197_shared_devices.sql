-- ============================================================================
-- Migration 0197: accounts played from one phone (script 200)
--
-- ADDITIVE ONLY. Two new tables. No row of any existing table is changed or
-- removed.
--
-- Decided by the owner on 2026-11-02: one phone may hold several accounts
-- (a shared family phone), but never two accounts predicting the same
-- match; and the admin sees every phone with more than one account, with
-- their number, and can suspend them.
--
-- The phone is the app's install id (`nukhba.install_id`, a random id kept
-- in the secure store since 0073), sent by the Android app from this
-- release on in the `x-nukhba-install` header. It is stored as md5 only:
-- a grouping key, never shown.
--
-- * identity.install_accounts: one row per (install, account) the server
--   has seen -- on opening the app (GET /me) and on every prediction.
--   last_seen moves on each sighting.
-- * prediction.install_claims: one row per (install, match): the first
--   account that predicted the match from that install. Another account
--   on the same install is refused that match
--   (`prediction.shared_device`); the same account amends freely.
-- * The admin list (`GET /admin/shared-devices`) reads these and
--   notification.device_token_owners (0177, one push token = one install),
--   so the phones seen before this release are listed too.
-- * A removed account takes its rows with it (on delete cascade).
-- * Backend-only, as 0177: RLS on, nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that writes them. Safe to re-run.
-- ============================================================================

begin;

create table if not exists identity.install_accounts (
  install_key text        not null,
  user_id     uuid        not null,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  constraint install_accounts_pkey primary key (install_key, user_id),
  constraint install_accounts_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete cascade
);

comment on table identity.install_accounts is
  'Every account seen on an install of the app (script 200). install_key '
  'is md5 of the install id, a grouping key only. Backend-only.';

create index if not exists install_accounts_user_id_idx
  on identity.install_accounts (user_id);

create table if not exists prediction.install_claims (
  install_key text        not null,
  fixture_id  uuid        not null,
  user_id     uuid        not null,
  claimed_at  timestamptz not null default now(),
  constraint install_claims_pkey primary key (install_key, fixture_id),
  constraint install_claims_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete cascade
);

comment on table prediction.install_claims is
  'The first account that predicted a match from an install (script 200). '
  'Another account on that install is refused the match. Backend-only.';

create index if not exists install_claims_user_id_idx
  on prediction.install_claims (user_id);

alter table identity.install_accounts enable row level security;
alter table prediction.install_claims enable row level security;

revoke select, insert, update, delete, truncate
  on identity.install_accounts from anon, authenticated;
revoke select, insert, update, delete, truncate
  on prediction.install_claims from anon, authenticated;

drop policy if exists install_accounts_no_client_read
  on identity.install_accounts;
create policy install_accounts_no_client_read
  on identity.install_accounts
  for select
  to anon, authenticated
  using (false);

drop policy if exists install_claims_no_client_read
  on prediction.install_claims;
create policy install_claims_no_client_read
  on prediction.install_claims
  for select
  to anon, authenticated
  using (false);

insert into ops.applied_migrations (version)
values ('0197_shared_devices')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0197_shared_devices';                       -- 1 row
-- select count(*) from identity.install_accounts;               -- grows
-- select count(*) from prediction.install_claims;               -- grows
