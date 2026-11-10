-- ============================================================================
-- Migration 0206: the oldest Google Play build the service still supports
-- (script 253, Play release audit F3, 2026-11-10)
--
-- ADDITIVE ONLY. One nullable column on `ops.app_update_policy` (0113) and
-- its check. No row is inserted, changed or removed.
--
-- `min_build_number` is set by the admin's «ارفع الحد الأدنى» to the newest
-- APK release, which is a CI run number Google Play never sees: the Play
-- bundle is built by another run, reviewed for days, and may never carry
-- that number. Shared, it would lock every Play player behind an update the
-- store cannot give. The Play build (`NUKHBA_CHANNEL=play`) now compares
-- itself with `min_play_build_number` only, typed by the admin once a
-- versionCode is live in Play; the APK keeps `min_build_number`, unchanged.
-- Null, the default, asks no Play player to update.
--
-- Server-only like the rest of the table (0113): RLS on, no policy,
-- nothing granted to anon or authenticated.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

alter table ops.app_update_policy
  add column if not exists min_play_build_number integer;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'app_update_policy_play_min_positive'
       and conrelid = 'ops.app_update_policy'::regclass
  ) then
    alter table ops.app_update_policy
      add constraint app_update_policy_play_min_positive
      check (min_play_build_number is null or min_play_build_number > 0);
  end if;
end $$;

comment on column ops.app_update_policy.min_play_build_number is
  'The oldest Google Play versionCode the service still supports (0206). '
  'Null asks no Play player to update. Typed by an admin once that '
  'version is live in Play; the APK minimum is min_build_number.';

insert into ops.applied_migrations (version) values ('0206_play_min_build')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0206_play_min_build';                     -- one row
-- select min_build_number, min_play_build_number
--   from ops.app_update_policy;                               -- one row
