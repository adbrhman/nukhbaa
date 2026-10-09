-- ============================================================================
-- Migration 0100: the monthly head-to-head league
--
-- ADDITIVE ONLY. Seven new tables inside the existing `gamification` schema
-- (0053) and one feature-flag row. No existing table is changed, nothing is
-- deleted. The weekly league (0061) stays readable as it is.
--
-- ## The rules (decided 2026-10-09/10 with the players' group)
-- Every month the players who predicted on at least five days of the month
-- before are drawn into divisions: 20 in the first, 20 in the second, 20 in
-- the third, the rest in the fourth (groups of up to 20). A ROUND is a day
-- an admin approves (or the system approves by itself when the day holds 6
-- fixtures or more); its fixtures are every fixture of that day, frozen at
-- the day's first kickoff. Each member meets one other member of the group
-- per round, by a fixed round-robin on their slot: more prediction points
-- wins. At most 19 rounds a month. The rules themselves are
-- `H2hLeaguePolicy` in the domain layer; this migration only stores facts.
--
-- ## What this is NOT: a points store
-- No column here holds points or a result. A round is derived at read time
-- from `scoring.fixture_scores` over the round's frozen fixtures. `ledger.*`
-- stays the only source of points, as 0053 states.
--
-- ## Tables
--   h2h_months          a month whose seats were drawn (once), pilot or not
--   h2h_leagues         the groups of a month
--   h2h_league_members  the seats; a fixed slot of the group round-robin
--   h2h_rounds          the approved rounds of a month, numbered in order
--   h2h_round_locks     a round whose fixture list was frozen at kickoff
--   h2h_round_fixtures  that frozen list
--   h2h_month_closures  a month that was judged
-- A judged month is one `h2h_league_finished` event per member in
-- `gamification.events`, carrying the division the member plays next.
--
-- ## Append-only, with one exception
-- Every table refuses UPDATE and DELETE in a trigger, as 0053, 0059 and 0061
-- do. The exception: an admin may withdraw the LAST approved round of a
-- month while it is not locked yet, so a mistaken approval can be undone
-- before anyone played it. Numbering stays gap-free because only the last
-- one can go.
--
-- ## The pilot
-- Flag `h2h_pilot` (0054 machinery): the users assigned variant 'pilot' play
-- a hidden trial month before the league opens to everyone. A pilot month
-- carries `is_pilot = true`; its results never decide a division.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Months that were drawn
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_months (
  month_start  date primary key,
  is_pilot     boolean not null default false,
  seated_count integer not null,
  drawn_at     timestamptz not null default now(),
  constraint h2h_months_first_day
    check (extract(day from month_start) = 1),
  constraint h2h_months_seated_count_nonneg
    check (seated_count >= 0)
);

comment on table gamification.h2h_months is
  'One row per Riyadh month whose head-to-head seats were drawn (0100), '
  'written in the same transaction as its seats, so a month is drawn once. '
  'A pilot month (is_pilot) is a hidden trial whose results decide nothing.';

-- ---------------------------------------------------------------------------
-- The groups of one month
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_leagues (
  id          uuid primary key,
  month_start date     not null
    constraint h2h_leagues_month_fkey
      references gamification.h2h_months (month_start),
  -- 1 is the top division.
  division    smallint not null,
  -- 0-based position of this group among the groups of (month, division).
  group_index smallint not null,
  -- Seats of the round-robin. Even, so every round pairs every seat.
  capacity    smallint not null,
  created_at  timestamptz not null default now(),
  constraint h2h_leagues_division_range
    check (division between 1 and 4),
  constraint h2h_leagues_group_index_nonneg
    check (group_index >= 0),
  constraint h2h_leagues_capacity_even
    check (capacity > 0 and capacity % 2 = 0),
  constraint h2h_leagues_month_division_index_uniq
    unique (month_start, division, group_index)
);

comment on table gamification.h2h_leagues is
  'One row per group of one division of one month of the head-to-head '
  'league (0100). Opened by the monthly draw. Holds no points.';

-- ---------------------------------------------------------------------------
-- Who holds which seat
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_league_members (
  league_id   uuid not null
    constraint h2h_league_members_league_id_fkey
      references gamification.h2h_leagues (id),
  -- Denormalised from the group so that "one seat per player per month" is
  -- a database fact rather than an application promise.
  month_start date not null,
  user_id     uuid not null
    constraint h2h_league_members_user_id_fkey
      references identity.users (id),
  slot        smallint not null,
  joined_at   timestamptz not null default now(),
  constraint h2h_league_members_pkey primary key (league_id, user_id),
  constraint h2h_league_members_month_user_uniq unique (month_start, user_id),
  constraint h2h_league_members_league_slot_uniq unique (league_id, slot),
  constraint h2h_league_members_slot_nonneg check (slot >= 0)
);

comment on table gamification.h2h_league_members is
  'A seat of a head-to-head group (0100), written once by the draw. The slot '
  'fixes the member place in the round-robin for the whole month.';

-- The backstop for what a unique constraint cannot say: the slot lies inside
-- the group, and the seat is filed under the group's own month.
create or replace function gamification.check_h2h_league_member()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month    date;
  v_capacity smallint;
begin
  select l.month_start, l.capacity
    into v_month, v_capacity
    from gamification.h2h_leagues l
   where l.id = new.league_id;
  if v_month is null then
    return new;  -- the foreign key reports the missing group
  end if;
  if new.slot >= v_capacity then
    raise exception 'h2h seat slot % is outside a group of %',
      new.slot, v_capacity
      using errcode = 'check_violation',
            constraint = 'h2h_league_members_slot_in_capacity';
  end if;
  if new.month_start <> v_month then
    raise exception 'h2h seat month % differs from its group month %',
      new.month_start, v_month
      using errcode = 'check_violation',
            constraint = 'h2h_league_members_month_matches_group';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_league_members_check
  on gamification.h2h_league_members;
create trigger h2h_league_members_check
  before insert on gamification.h2h_league_members
  for each row
  execute function gamification.check_h2h_league_member();

-- ---------------------------------------------------------------------------
-- The approved rounds of a month
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_rounds (
  id            uuid primary key,
  -- Not a foreign key to h2h_months: a round may be approved before its
  -- month is drawn (the draw runs on the month's first night).
  month_start   date     not null,
  round_no      smallint not null,
  -- The Riyadh day whose fixtures make the round.
  day           date     not null,
  -- Fixtures the day held when it was approved. Audit only: the round's
  -- fixtures are the list frozen at its first kickoff.
  fixture_count smallint not null,
  -- The admin who approved the round, or null when the system did.
  approved_by   uuid
    constraint h2h_rounds_approved_by_fkey
      references identity.users (id),
  approved_at   timestamptz not null default now(),
  constraint h2h_rounds_month_first_day
    check (extract(day from month_start) = 1),
  constraint h2h_rounds_day_in_month
    check (date_trunc('month', day)::date = month_start),
  constraint h2h_rounds_round_no_range
    check (round_no between 1 and 19),
  constraint h2h_rounds_fixture_count_nonneg
    check (fixture_count >= 0),
  constraint h2h_rounds_month_round_uniq unique (month_start, round_no),
  constraint h2h_rounds_day_uniq unique (day)
);

comment on table gamification.h2h_rounds is
  'One row per approved round of the head-to-head league (0100). Rounds of '
  'a month are numbered 1, 2, ... in the order of their days; a new round '
  'must come after the last one. Only the last round may be withdrawn, and '
  'only while it is not locked.';

-- Rounds are approved in order: the next number, on a later day.
create or replace function gamification.check_h2h_round()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_last_no  smallint;
  v_last_day date;
begin
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_rounds'),
    hashtext(new.month_start::text)
  );
  select r.round_no, r.day
    into v_last_no, v_last_day
    from gamification.h2h_rounds r
   where r.month_start = new.month_start
   order by r.round_no desc
   limit 1;
  if new.round_no <> coalesce(v_last_no, 0) + 1 then
    raise exception 'h2h round % is not the next round (last is %)',
      new.round_no, coalesce(v_last_no, 0)
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_in_order';
  end if;
  if v_last_day is not null and new.day <= v_last_day then
    raise exception 'h2h round day % is not after the last round day %',
      new.day, v_last_day
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_in_order';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_rounds_check on gamification.h2h_rounds;
create trigger h2h_rounds_check
  before insert on gamification.h2h_rounds
  for each row
  execute function gamification.check_h2h_round();

-- ---------------------------------------------------------------------------
-- The frozen fixture list of a round
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_round_locks (
  round_id      uuid primary key
    constraint h2h_round_locks_round_id_fkey
      references gamification.h2h_rounds (id),
  fixture_count smallint not null,
  locked_at     timestamptz not null default now(),
  constraint h2h_round_locks_fixture_count_nonneg
    check (fixture_count >= 0)
);

comment on table gamification.h2h_round_locks is
  'A round whose fixture list was frozen at its first kickoff (0100), '
  'written in the same transaction as h2h_round_fixtures.';

create table if not exists gamification.h2h_round_fixtures (
  round_id   uuid not null
    constraint h2h_round_fixtures_round_id_fkey
      references gamification.h2h_rounds (id),
  fixture_id uuid not null
    constraint h2h_round_fixtures_fixture_id_fkey
      references competition.fixture_schedules (fixture_id),
  constraint h2h_round_fixtures_pkey primary key (round_id, fixture_id)
);

comment on table gamification.h2h_round_fixtures is
  'The fixtures of a locked round (0100). A fixture later moved off the '
  'round day, hidden or never scored is void for both sides.';

create index if not exists h2h_round_fixtures_fixture_idx
  on gamification.h2h_round_fixtures (fixture_id);

-- ---------------------------------------------------------------------------
-- Months that were judged
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_month_closures (
  month_start  date primary key
    constraint h2h_month_closures_month_fkey
      references gamification.h2h_months (month_start),
  member_count integer not null,
  closed_at    timestamptz not null default now(),
  constraint h2h_month_closures_member_count_nonneg
    check (member_count >= 0)
);

comment on table gamification.h2h_month_closures is
  'One row per month whose head-to-head groups were judged (0100): the '
  'watermark that stops the job from judging a month twice.';

-- ---------------------------------------------------------------------------
-- Append-only backstop, mirroring 0061, with the one exception above.
-- ---------------------------------------------------------------------------
create or replace function gamification.reject_h2h_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception
      '% is append-only: UPDATE is forbidden', tg_table_name
      using errcode = 'check_violation';
  elsif tg_op = 'DELETE' then
    raise exception
      '% is append-only: DELETE is forbidden', tg_table_name
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

comment on function gamification.reject_h2h_mutation() is
  'Append-only backstop for the head-to-head tables (0100): rejects any '
  'UPDATE or DELETE for every role, including the service role.';

create or replace function gamification.guard_h2h_round_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'h2h_rounds is append-only: UPDATE is forbidden'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from gamification.h2h_round_locks k where k.round_id = old.id
  ) then
    raise exception 'h2h round % is locked and cannot be withdrawn', old.round_no
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_withdraw_unlocked';
  end if;
  if exists (
    select 1 from gamification.h2h_rounds r
     where r.month_start = old.month_start and r.round_no > old.round_no
  ) then
    raise exception 'only the last h2h round of a month can be withdrawn'
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_withdraw_last';
  end if;
  return old;
end;
$$;

comment on function gamification.guard_h2h_round_mutation() is
  'h2h_rounds refuses UPDATE; DELETE only of the last round of a month and '
  'only while it is not locked (0100).';

drop trigger if exists h2h_rounds_guard_mutation on gamification.h2h_rounds;
create trigger h2h_rounds_guard_mutation
  before update or delete on gamification.h2h_rounds
  for each row
  execute function gamification.guard_h2h_round_mutation();

do $$
declare
  t text;
begin
  foreach t in array array[
    'h2h_months', 'h2h_leagues', 'h2h_league_members', 'h2h_round_locks',
    'h2h_round_fixtures', 'h2h_month_closures'
  ] loop
    execute format(
      'drop trigger if exists %I on gamification.%I',
      t || '_reject_mutation', t);
    execute format(
      'create trigger %I before update or delete on gamification.%I '
      'for each row execute function gamification.reject_h2h_mutation()',
      t || '_reject_mutation', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- RLS: server-only, like 0061. The client receives a standing from the API
-- and never reads the tables.
-- ---------------------------------------------------------------------------
alter table gamification.h2h_months          enable row level security;
alter table gamification.h2h_leagues         enable row level security;
alter table gamification.h2h_league_members  enable row level security;
alter table gamification.h2h_rounds          enable row level security;
alter table gamification.h2h_round_locks     enable row level security;
alter table gamification.h2h_round_fixtures  enable row level security;
alter table gamification.h2h_month_closures  enable row level security;

revoke all on gamification.h2h_months         from anon, authenticated;
revoke all on gamification.h2h_leagues        from anon, authenticated;
revoke all on gamification.h2h_league_members from anon, authenticated;
revoke all on gamification.h2h_rounds         from anon, authenticated;
revoke all on gamification.h2h_round_locks    from anon, authenticated;
revoke all on gamification.h2h_round_fixtures from anon, authenticated;
revoke all on gamification.h2h_month_closures from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The pilot flag (0054). Users assigned variant 'pilot' play the hidden
-- trial month. Assign one with:
--   insert into gamification.experiment_assignments (user_id, flag_key, variant)
--   select id, 'h2h_pilot', 'pilot' from identity.users where display_name = '...'
--   on conflict do nothing;
-- ---------------------------------------------------------------------------
insert into gamification.feature_flags (flag_key, description, enabled)
values (
  'h2h_pilot',
  'Head-to-head league pilot (0100): users with variant pilot play a hidden '
  'trial month before the league opens to everyone.',
  true
)
on conflict (flag_key) do nothing;

insert into ops.applied_migrations (version)
values ('0100_h2h_leagues')
on conflict (version) do nothing;

commit;
