-- ============================================================================
-- Migration 0101: the admin's controls over the head-to-head league
--
-- ADDITIVE ONLY. Three new tables inside the `gamification` schema. No table
-- of 0100 (or any other) is changed; no row is deleted; no point is stored.
--
-- ## Tables
--   h2h_settings        one row: the knobs the admin may turn
--   h2h_day_exclusions  days the system must not approve as rounds by itself
--   h2h_admin_actions   every admin action on the league, append-only
--
-- ## What the settings may change, and what they may not
-- They change only what happens from now on: whether the system approves
-- regular days by itself, how long before a day's first kickoff it may do
-- so (at most the 24 hours it always looked ahead), and how many active days
-- a player needs to be drawn next month. What a round IS (6 fixtures or
-- more, 5 for a fill day), the 19-round cap and the seats already drawn stay
-- the rules of 0100: changing them mid-month would change rounds already
-- played.
--
-- ## Exclusions
-- An excluded day is skipped by the automatic approval only; an admin may
-- still approve it, which lifts the exclusion. Lifting one deletes its row,
-- and every exclusion and lift is also written to h2h_admin_actions, so the
-- history is never lost.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The knobs: exactly one row
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_settings (
  id                      boolean primary key default true,
  -- Whether the system approves regular days (6 fixtures or more) by itself.
  auto_approve            boolean  not null default true,
  -- How long before a day's first kickoff the system may approve it.
  auto_approve_lead_hours smallint not null default 24,
  -- Days of predictions in a month that put a player into the next draw.
  min_active_days         smallint not null default 5,
  updated_by              uuid
    constraint h2h_settings_updated_by_fkey
      references identity.users (id),
  updated_at              timestamptz not null default now(),
  constraint h2h_settings_single_row check (id),
  constraint h2h_settings_lead_range
    check (auto_approve_lead_hours between 1 and 24),
  constraint h2h_settings_active_days_range
    check (min_active_days between 1 and 28)
);

comment on table gamification.h2h_settings is
  'The one row of admin settings of the head-to-head league (0101). Only '
  'what happens from now on: automatic approval on or off, its lead (at most '
  '24 hours), and the active days the next draw requires.';

insert into gamification.h2h_settings (id) values (true)
on conflict (id) do nothing;

create or replace function gamification.guard_h2h_settings_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'h2h_settings keeps its one row: DELETE is forbidden'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists h2h_settings_guard_delete on gamification.h2h_settings;
create trigger h2h_settings_guard_delete
  before delete on gamification.h2h_settings
  for each row
  execute function gamification.guard_h2h_settings_delete();

-- ---------------------------------------------------------------------------
-- Days the automatic approval skips
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_day_exclusions (
  -- A Riyadh day.
  day         date primary key,
  excluded_by uuid
    constraint h2h_day_exclusions_excluded_by_fkey
      references identity.users (id),
  excluded_at timestamptz not null default now()
);

comment on table gamification.h2h_day_exclusions is
  'Riyadh days the system must not approve as head-to-head rounds by itself '
  '(0101). An admin may still approve one, which removes its row.';

-- ---------------------------------------------------------------------------
-- Every admin action, append-only
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_admin_actions (
  id       uuid primary key,
  action   text not null,
  actor    uuid
    constraint h2h_admin_actions_actor_fkey
      references identity.users (id),
  detail   jsonb not null default '{}'::jsonb,
  acted_at timestamptz not null default now(),
  constraint h2h_admin_actions_action_known check (action in (
    'settings_saved', 'day_excluded', 'day_included', 'round_approved',
    'round_withdrawn', 'seat_added', 'jobs_run', 'pilot_started'
  ))
);

comment on table gamification.h2h_admin_actions is
  'The log of every admin action on the head-to-head league (0101): who did '
  'what and when. Append-only.';

create index if not exists h2h_admin_actions_acted_at_idx
  on gamification.h2h_admin_actions (acted_at desc);

drop trigger if exists h2h_admin_actions_reject_mutation
  on gamification.h2h_admin_actions;
create trigger h2h_admin_actions_reject_mutation
  before update or delete on gamification.h2h_admin_actions
  for each row
  execute function gamification.reject_h2h_mutation();

-- ---------------------------------------------------------------------------
-- RLS: server-only, like 0100.
-- ---------------------------------------------------------------------------
alter table gamification.h2h_settings       enable row level security;
alter table gamification.h2h_day_exclusions enable row level security;
alter table gamification.h2h_admin_actions  enable row level security;

revoke all on gamification.h2h_settings       from anon, authenticated;
revoke all on gamification.h2h_day_exclusions from anon, authenticated;
revoke all on gamification.h2h_admin_actions  from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0101_h2h_admin_controls')
on conflict (version) do nothing;

commit;
