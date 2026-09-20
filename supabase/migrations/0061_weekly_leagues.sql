-- ============================================================================
-- Migration 0061: the weekly league -- groups, membership, week closure (P2-1)
--
-- ADDITIVE ONLY. Three tables inside the existing `gamification` schema
-- (0053). No existing table is touched, no column is added elsewhere, nothing
-- is deleted.
--
-- ## What this is
-- The weekly league splits the players into small groups for one Riyadh week
-- (Monday 00:00 through Sunday 23:59). At the end of the week the top of each
-- group is promoted a tier, the bottom is relegated, the rest hold. A small
-- group gives every player a reachable first place, and relegation gives them
-- something to lose -- which is what brings a player back on a Tuesday.
--
-- ## What this is NOT: a points store
-- Not one column here holds points. A week's standing is derived at read time
-- from `scoring.fixture_scores` plus `ledger.fixture_point_entries` of kind
-- `streak_bonus`, restricted to the fixtures that kicked off inside the week
-- -- the same sum `PostgresFixtureTotalsReader` already computes for the
-- month, over a different fixture list. `ledger.*` stays the only source of
-- points, exactly as 0053 states.
--
-- Promotion and relegation pay NOTHING into the ledger. The monthly board
-- carries the real prize; paying the weekly winner into it would let the
-- leader win twice and widen the gap the weekly league exists to close. The
-- reward is the tier, the placing and the badge. This is reversible later by
-- a new `ledger.entry_kind` if the product decides otherwise.
--
-- ## Where a finished week lives
-- Not here. Closing a week writes one append-only `weekly_league_finished`
-- event per member into `gamification.events`, carrying `{tier, rank, points,
-- outcome}` in its payload. That freezes the standing against a later result
-- correction, needs no fourth table, and makes next week's tier a read of the
-- player's newest such event.
--
-- ## Membership is lazy, not drawn at midnight
-- A player is placed in a group the first time they are seen in the week, not
-- by a Monday job. A player who installs the app on Wednesday plays on
-- Wednesday. `weekly_league_members_week_user_uniq` is what makes that
-- placement idempotent under concurrent requests: the loser of the race reads
-- the row the winner wrote.
--
-- ## The tier ladder
-- 1 bronze, 2 silver, 3 gold, 4 platinum, 5 elite. The ladder is stored as a
-- number and named in the domain layer, like `GamificationEventType` (0053):
-- how many players are promoted, how many are relegated and how large a group
-- may be are policy, and policy that changes must not need a migration.
-- `capacity` is recorded per group so that a group formed under today's
-- capacity is not re-judged under tomorrow's.
--
-- ## Append-only
-- All three tables revoke UPDATE and DELETE and reject them in a trigger, as
-- `gamification.events` (0053) and `settled_days` (0059) do. A group is never
-- rebalanced after it is formed: moving a player between groups mid-week
-- would rewrite a race that is already being run.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The groups of one week
-- ---------------------------------------------------------------------------
create table if not exists gamification.weekly_leagues (
  id          uuid primary key,
  -- The Monday that opens the Riyadh week this group belongs to.
  week_start  date     not null,
  tier        smallint not null,
  -- 0-based position of this group among the groups of (week_start, tier).
  group_index smallint not null,
  -- How many members this group accepts. Frozen at formation: a capacity
  -- changed next month does not re-open a group that filled under the old one.
  capacity    smallint not null,
  created_at  timestamptz not null default now(),
  constraint weekly_leagues_tier_range
    check (tier between 1 and 5),
  constraint weekly_leagues_group_index_nonneg
    check (group_index >= 0),
  constraint weekly_leagues_capacity_positive
    check (capacity > 0),
  constraint weekly_leagues_week_tier_index_uniq
    unique (week_start, tier, group_index)
);

comment on table gamification.weekly_leagues is
  'One row per group of one tier of one Riyadh week (P2-1). Groups are '
  'opened on demand as players arrive and are never rebalanced afterwards. '
  'Holds no points: a week standing is derived from scoring.fixture_scores '
  'and ledger streak bonuses over the week fixtures.';

comment on column gamification.weekly_leagues.week_start is
  'The Monday 00:00 Asia/Riyadh that opens the week, as a date. The same '
  'day boundary gamification.settled_days and the reminder sweep use.';

comment on column gamification.weekly_leagues.tier is
  '1 bronze .. 5 elite. Named in the domain layer, not here: the number of '
  'tiers is policy and policy must not need a migration to change.';

comment on column gamification.weekly_leagues.capacity is
  'Members this group accepts, frozen at formation. A new group of the same '
  'tier and week opens only when every existing one is full.';

-- "the groups of this tier this week, smallest first" is the placement read;
-- the unique constraint above already indexes (week_start, tier).

-- ---------------------------------------------------------------------------
-- Who is in which group
-- ---------------------------------------------------------------------------
create table if not exists gamification.weekly_league_members (
  league_id  uuid not null
    constraint weekly_league_members_league_id_fkey
      references gamification.weekly_leagues (id) on delete cascade,
  -- Denormalised from the league so that "one group per player per week" is
  -- a database fact rather than an application promise.
  week_start date not null,
  user_id    uuid not null
    constraint weekly_league_members_user_id_fkey
      references identity.users (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  constraint weekly_league_members_pkey primary key (league_id, user_id),
  constraint weekly_league_members_week_user_uniq unique (week_start, user_id)
);

comment on table gamification.weekly_league_members is
  'Membership of a weekly group (P2-1). Written once, when the player is '
  'first seen in the week. The (week_start, user_id) unique constraint is '
  'what makes that placement idempotent under concurrent requests: the '
  'loser of the race reads the winner row instead of opening a second seat.';

comment on column gamification.weekly_league_members.user_id is
  'The platform user, not a participant: points are summed across every '
  'participant row the user holds in the seasons active that week, the same '
  'way GetMyDailyChallenge sums a day across the user active seasons.';

-- "members of this group" is served by the primary key. The closure job and
-- the read path both need "this player's group this week", served by the
-- (week_start, user_id) unique index.

-- ---------------------------------------------------------------------------
-- Which weeks have been judged
-- ---------------------------------------------------------------------------
create table if not exists gamification.weekly_league_closures (
  week_start date primary key,
  -- Members judged when the week was closed. Diagnostic only: the standings
  -- themselves are the weekly_league_finished events in gamification.events.
  member_count integer not null,
  closed_at  timestamptz not null default now(),
  constraint weekly_league_closures_member_count_nonneg
    check (member_count >= 0)
);

comment on table gamification.weekly_league_closures is
  'One row per Riyadh week whose groups have been judged (P2-1): the '
  'watermark that stops the weekly job from re-judging a week, mirroring '
  'gamification.settled_days. The standings it produced are '
  'weekly_league_finished events, not rows here.';

-- ---------------------------------------------------------------------------
-- Append-only backstop for all three, mirroring 0053 and 0059.
-- ---------------------------------------------------------------------------
create or replace function gamification.reject_weekly_league_mutation()
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

comment on function gamification.reject_weekly_league_mutation() is
  'Append-only backstop for the three weekly-league tables: rejects any '
  'UPDATE or DELETE for every role, including the service role that '
  'bypasses RLS. A group is never rebalanced after it is formed.';

drop trigger if exists weekly_leagues_reject_mutation
  on gamification.weekly_leagues;
create trigger weekly_leagues_reject_mutation
  before update or delete on gamification.weekly_leagues
  for each row
  execute function gamification.reject_weekly_league_mutation();

drop trigger if exists weekly_league_members_reject_mutation
  on gamification.weekly_league_members;
create trigger weekly_league_members_reject_mutation
  before update or delete on gamification.weekly_league_members
  for each row
  execute function gamification.reject_weekly_league_mutation();

drop trigger if exists weekly_league_closures_reject_mutation
  on gamification.weekly_league_closures;
create trigger weekly_league_closures_reject_mutation
  before update or delete on gamification.weekly_league_closures
  for each row
  execute function gamification.reject_weekly_league_mutation();

-- ---------------------------------------------------------------------------
-- RLS: server-only, like settled_days (0059) and device_tokens (0039). The
-- client receives a standing from the API, never reads the tables: a player
-- who could read every group could see their rivals seats before the week is
-- judged.
-- ---------------------------------------------------------------------------
alter table gamification.weekly_leagues          enable row level security;
alter table gamification.weekly_league_members   enable row level security;
alter table gamification.weekly_league_closures  enable row level security;

revoke all on gamification.weekly_leagues         from anon, authenticated;
revoke all on gamification.weekly_league_members  from anon, authenticated;
revoke all on gamification.weekly_league_closures from anon, authenticated;

commit;

-- Verification:
-- select count(*) from gamification.weekly_leagues;            -- 0
-- select count(*) from gamification.weekly_league_members;     -- 0
-- select count(*) from gamification.weekly_league_closures;    -- 0
-- insert into gamification.weekly_league_closures (week_start, member_count)
--   values ('2026-09-21', 0);
-- update gamification.weekly_league_closures set member_count = 1;  -- fails
-- delete from gamification.weekly_league_closures;                  -- fails
