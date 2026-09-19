-- ============================================================================
-- Migration 0054: feature flags, experiment assignments, first KPI view
-- (P0-7 and P0-8 — what closes phase 0 of the gamification plan)
--
-- ADDITIVE ONLY. Two tables and one view inside the `gamification` schema
-- (0053). No existing table is touched, nothing is deleted.
--
-- ## Why flags now rather than with the first feature
-- P1-8 and every later phase gate their rollout on an A/B split, and a split
-- decided after a feature ships is not a split: the assignment must exist
-- before the first user sees either variant. The tables are therefore created
-- here, empty. They are read by the server; nothing reads them until a flag
-- row exists, and inserting that row is what turns a feature on.
--
-- ## Backend-only, like device_tokens (0039) and reminder_sends (0040)
-- A client never sees a flag or its own variant: it receives behaviour, not
-- configuration. RLS is on and no policy is granted to anon or authenticated,
-- so only the service role reads and writes. This also keeps the split
-- honest — a client that cannot read its variant cannot select into one.
--
-- ## The KPI view is deliberately one, not three
-- The plan names three views. `challenge_completion_rate` and
-- `streak_participation` have no tables to read yet (phase 1 creates them);
-- a view over columns that do not exist is not a measurement, it is a
-- promise. They arrive with their tables. What can be measured today is
-- daily activity, and only from the switch-on date — there is no backfill
-- (decided 2026-09-19).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- P0-7: flags and their assignments
-- ---------------------------------------------------------------------------
create table if not exists gamification.feature_flags (
  flag_key    text primary key,
  description text not null,
  -- The master switch. A flag that is off means the feature is off for
  -- everyone, whatever any assignment row says.
  enabled     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint feature_flags_key_nonblank
    check (btrim(flag_key) <> ''),
  constraint feature_flags_description_nonblank
    check (btrim(description) <> '')
);

comment on table gamification.feature_flags is
  'One row per gated feature (P0-7). Backend-only: a client never reads a '
  'flag, it receives the behaviour the server decided. Deleting a row is '
  'not how a feature is retired -- set enabled = false, so the assignments '
  'that measured it survive.';

drop trigger if exists feature_flags_set_updated_at on gamification.feature_flags;
create trigger feature_flags_set_updated_at
  before update on gamification.feature_flags
  for each row
  execute function identity.set_updated_at();

create table if not exists gamification.experiment_assignments (
  user_id     uuid not null
    constraint experiment_assignments_user_id_fkey
      references identity.users (id) on delete cascade,
  flag_key    text not null
    constraint experiment_assignments_flag_key_fkey
      references gamification.feature_flags (flag_key) on delete cascade,
  variant     text not null,
  assigned_at timestamptz not null default now(),
  constraint experiment_assignments_pkey primary key (user_id, flag_key),
  constraint experiment_assignments_variant_nonblank
    check (btrim(variant) <> '')
);

comment on table gamification.experiment_assignments is
  'Which variant of a flagged feature a user is in (P0-7). The primary key '
  '(user_id, flag_key) is what makes assignment stable: a user assigned '
  'once keeps their variant for the whole experiment, so the measurement is '
  'of the feature and not of reassignment.';

comment on column gamification.experiment_assignments.variant is
  'Free text so an experiment may have more than two arms. The convention '
  'is ''control'' for the arm that sees today''s behaviour.';

-- The hot read is "this user's assignments", answered by the primary key.
-- The analysis read is "everyone on this flag", which needs its own index.
create index if not exists experiment_assignments_flag_idx
  on gamification.experiment_assignments (flag_key, variant);

-- ---------------------------------------------------------------------------
-- P0-8: the one KPI that has data today
-- ---------------------------------------------------------------------------
create or replace view gamification.daily_active_users as
select
  (occurred_at at time zone 'Asia/Riyadh')::date as activity_date,
  count(distinct user_id)                        as active_users,
  count(*)                                       as events
from gamification.events
group by 1;

comment on view gamification.daily_active_users is
  'Distinct users who produced at least one gamification event per day, in '
  'the Riyadh day the rest of the scheduler already uses (0040). Counts '
  'from the switch-on date only: there is no backfill of earlier '
  'predictions. As event types are added in later phases this widens by '
  'itself, so it measures activity rather than predictions alone.';

-- ---------------------------------------------------------------------------
-- RLS: service role only, for both tables. No client policy is granted.
-- ---------------------------------------------------------------------------
alter table gamification.feature_flags enable row level security;
alter table gamification.experiment_assignments enable row level security;

revoke select, insert, update, delete, truncate
  on gamification.feature_flags from anon, authenticated;
revoke select, insert, update, delete, truncate
  on gamification.experiment_assignments from anon, authenticated;

commit;

-- Verification:
-- select count(*) from gamification.feature_flags;            -- 0
-- select count(*) from gamification.experiment_assignments;   -- 0
-- select * from gamification.daily_active_users;              -- 0 rows
-- select relrowsecurity from pg_class
--  where oid = 'gamification.feature_flags'::regclass;        -- t
