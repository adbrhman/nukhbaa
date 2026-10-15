-- ============================================================================
-- Migration 0113: the oldest Android build the service still supports
--
-- ADDITIVE ONLY. One new table, `ops.app_update_policy`, holding one row.
-- No existing table or row is touched.
--
-- Every green push used to publish an APK and the app only offered the
-- update as a quiet row on the account tab, so players stayed on whatever
-- build they had: 19 builds were in use at once, and fixes already shipped
-- (the one-read points of script 75, the background report timeouts)
-- kept arriving from old phones (batch 147, audit L-15).
--
-- Each release now carries a build number (the CI run number). The admin
-- may set `min_build_number`: an app older than it shows one screen, "update
-- to continue", with the in-app install. Null, the default, asks nobody.
-- It is raised by hand after a fix that matters, never on every release.
--
-- Server-only: RLS on, no policy, nothing granted to anon or authenticated
-- (as 0070 and 0087 did for the other ops tables). `/app/latest-build`
-- reads it for every caller, signed in or not; only an admin writes it.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists ops;

create table if not exists ops.app_update_policy (
  id               boolean primary key default true,
  -- The oldest build number that may still run; null asks nobody.
  min_build_number integer,
  updated_by       uuid
    constraint app_update_policy_updated_by_fkey
      references identity.users (id),
  updated_at       timestamptz not null default now(),
  constraint app_update_policy_single_row check (id),
  constraint app_update_policy_min_positive
    check (min_build_number is null or min_build_number > 0)
);

comment on table ops.app_update_policy is
  'One row: the oldest Android build number the service still supports '
  '(0113). Null asks nobody to update. Set by an admin from the panel.';

insert into ops.app_update_policy (id) values (true)
on conflict (id) do nothing;

alter table ops.app_update_policy enable row level security;
revoke all on ops.app_update_policy from anon, authenticated;

insert into ops.applied_migrations (version) values ('0113_app_update_policy')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0113_app_update_policy';                  -- one row
-- select min_build_number from ops.app_update_policy;          -- one row, null
