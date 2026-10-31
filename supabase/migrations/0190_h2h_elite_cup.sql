-- ============================================================================
-- Migration 0190: the Elite Cup of the head-to-head league (NK185)
--
-- ADDITIVE ONLY. Seven new append-only tables in `gamification`. Nothing is
-- changed or deleted; the league's rounds, tables and seats stay exactly as
-- they are, and the cup never writes to them.
--
-- ## The rules (decided by the owner on 2026-10-31, script 185)
-- Once the 19 rounds of a month of the elite draw are all judged, the
-- first, second and third places of the four elite groups (division 1)
-- play three SEPARATE cups ("paths"): place 1, then place 2, then place 3.
-- Each path is a semi-final drawn at random and a final. The six stages are
-- played one after the other, each on the next qualifying day (six fixtures
-- or more) after the stage before it is settled: day 20 to 25 when nothing
-- was late, later otherwise, into the next month if need be. A stage whose
-- day leaves no fixture to play is carried to the next qualifying day with
-- the same pairs (a new attempt). The monthly championship and the month's
-- close never wait for the cup.
--
-- A pair is judged on the stage's fixtures only: the side that predicted
-- beats the side that did not; with both present the higher points, then
-- more exact scorelines, then the better league month; with neither
-- present both lose. A semi-final both lost sends the other winner to the
-- title without a final; two such semi-finals leave the title vacant.
--
-- ## Tables
--   h2h_cup_entries        the qualifiers of a month: place, group and the
--                          league month the last tie-break reads
--   h2h_cup_stages         one row per stage played (or carried) on a day
--   h2h_cup_stage_fixtures the stage's fixtures, frozen at its first kickoff
--   h2h_cup_stage_locks    the moment they were frozen
--   h2h_cup_pairs          the pairs of a stage (the draw, or the finalists)
--   h2h_cup_results        each pair's decision and both sides' figures
--   h2h_cup_titles         each path's champion and runner-up (or vacant)
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The qualifiers
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_entries (
  month_start   date     not null
    constraint h2h_cup_entries_month_fkey
      references gamification.h2h_months (month_start),
  place         smallint not null,
  user_id       uuid     not null
    constraint h2h_cup_entries_user_fkey
      references identity.users (id),
  group_number  smallint not null,
  league_points integer  not null,
  points_for    integer  not null,
  exact_count   integer  not null,
  created_at    timestamptz not null default now(),
  constraint h2h_cup_entries_pkey primary key (month_start, user_id),
  constraint h2h_cup_entries_seat_uniq
    unique (month_start, place, group_number),
  constraint h2h_cup_entries_place_range check (place between 1 and 3),
  constraint h2h_cup_entries_group_range check (group_number between 1 and 4),
  constraint h2h_cup_entries_figures_nonneg
    check (league_points >= 0 and points_for >= 0 and exact_count >= 0)
);

comment on table gamification.h2h_cup_entries is
  'The Elite Cup''s qualifiers of a month (0190): the first three places of '
  'the four elite groups once the 19 rounds were judged. Append-only.';

-- ---------------------------------------------------------------------------
-- The stages
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_stages (
  id            uuid primary key,
  month_start   date     not null
    constraint h2h_cup_stages_month_fkey
      references gamification.h2h_months (month_start),
  place         smallint not null,
  stage         text     not null,
  -- 1 for the first day the stage was given; 2, 3, ... for a stage carried
  -- because its day left no fixture to play.
  attempt       smallint not null,
  -- The Riyadh day whose fixtures make the stage.
  day           date     not null,
  -- Fixtures the day held when the stage was given it. Audit only: the
  -- stage's fixtures are the list frozen at its first kickoff.
  fixture_count smallint not null,
  created_at    timestamptz not null default now(),
  constraint h2h_cup_stages_step_uniq
    unique (month_start, place, stage, attempt),
  constraint h2h_cup_stages_day_uniq unique (day),
  constraint h2h_cup_stages_place_range check (place between 1 and 3),
  constraint h2h_cup_stages_stage_known check (stage in ('semi', 'final')),
  constraint h2h_cup_stages_attempt_positive check (attempt >= 1),
  constraint h2h_cup_stages_fixture_count_nonneg check (fixture_count >= 0)
);

comment on table gamification.h2h_cup_stages is
  'One stage of the Elite Cup on one day (0190). Stages come one after the '
  'other: each on a later day than every stage and round of its month '
  'before it, and only once the month has its 19 rounds. Append-only.';

-- The backstop of the order: a cup only after the 19 rounds, and a stage
-- only on a day after every earlier stage and round of its month.
create or replace function gamification.check_h2h_cup_stage()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_rounds   integer;
  v_last_day date;
begin
  select count(*), max(r.day) into v_rounds, v_last_day
  from gamification.h2h_rounds r
  where r.month_start = new.month_start;
  if v_rounds < 19 then
    raise exception 'the league of % has % rounds, not 19',
      new.month_start, v_rounds
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_after_league';
  end if;
  if new.day <= v_last_day then
    raise exception 'stage day % is not after the last round %',
      new.day, v_last_day
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_after_league';
  end if;
  if exists (
    select 1 from gamification.h2h_cup_stages s
    where s.month_start = new.month_start and s.day >= new.day
  ) then
    raise exception 'stage day % is not after the cup''s last stage', new.day
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_in_order';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_cup_stages_check on gamification.h2h_cup_stages;
create trigger h2h_cup_stages_check
  before insert on gamification.h2h_cup_stages
  for each row
  execute function gamification.check_h2h_cup_stage();

-- ---------------------------------------------------------------------------
-- A stage's fixtures, frozen at its first kickoff
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_stage_locks (
  stage_id      uuid primary key
    constraint h2h_cup_stage_locks_stage_fkey
      references gamification.h2h_cup_stages (id),
  fixture_count smallint not null,
  locked_at     timestamptz not null default now(),
  constraint h2h_cup_stage_locks_fixture_count_nonneg
    check (fixture_count >= 0)
);

comment on table gamification.h2h_cup_stage_locks is
  'An Elite Cup stage whose fixture list was frozen (0190), written in the '
  'same transaction as h2h_cup_stage_fixtures. Append-only.';

create table if not exists gamification.h2h_cup_stage_fixtures (
  stage_id   uuid not null
    constraint h2h_cup_stage_fixtures_stage_fkey
      references gamification.h2h_cup_stages (id),
  fixture_id uuid not null
    constraint h2h_cup_stage_fixtures_fixture_fkey
      references competition.fixture_schedules (fixture_id),
  constraint h2h_cup_stage_fixtures_pkey primary key (stage_id, fixture_id)
);

comment on table gamification.h2h_cup_stage_fixtures is
  'The fixtures of a locked Elite Cup stage (0190). A fixture later moved '
  'off the stage''s day, hidden, or without a result by the end of the next '
  'day is void for both sides. Append-only.';

create index if not exists h2h_cup_stage_fixtures_fixture_idx
  on gamification.h2h_cup_stage_fixtures (fixture_id);

-- ---------------------------------------------------------------------------
-- The pairs and their decisions
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_pairs (
  stage_id  uuid     not null
    constraint h2h_cup_pairs_stage_fkey
      references gamification.h2h_cup_stages (id),
  slot      smallint not null,
  home_user uuid     not null
    constraint h2h_cup_pairs_home_fkey
      references identity.users (id),
  away_user uuid     not null
    constraint h2h_cup_pairs_away_fkey
      references identity.users (id),
  constraint h2h_cup_pairs_pkey primary key (stage_id, slot),
  constraint h2h_cup_pairs_slot_range check (slot between 1 and 2),
  constraint h2h_cup_pairs_two_players check (home_user <> away_user)
);

comment on table gamification.h2h_cup_pairs is
  'The pairs of an Elite Cup stage (0190): the random draw of a semi-final, '
  'or the final''s two winners. A carried stage repeats its pairs. '
  'Append-only.';

create table if not exists gamification.h2h_cup_results (
  stage_id       uuid     not null,
  slot           smallint not null,
  -- The winner, or null when neither side predicted.
  winner_user    uuid
    constraint h2h_cup_results_winner_fkey
      references identity.users (id),
  outcome        text     not null,
  home_points    integer  not null,
  away_points    integer  not null,
  home_exact     integer  not null,
  away_exact     integer  not null,
  home_predicted integer  not null,
  away_predicted integer  not null,
  decided_at     timestamptz not null default now(),
  constraint h2h_cup_results_pkey primary key (stage_id, slot),
  constraint h2h_cup_results_pair_fkey foreign key (stage_id, slot)
    references gamification.h2h_cup_pairs (stage_id, slot),
  constraint h2h_cup_results_outcome_known check (outcome in (
    'points', 'exact', 'league', 'walkover', 'both_absent'
  )),
  constraint h2h_cup_results_winner_present check (
    (outcome = 'both_absent') = (winner_user is null)
  )
);

comment on table gamification.h2h_cup_results is
  'The decision of each pair of a settled Elite Cup stage (0190), with both '
  'sides'' points, exact scorelines and predictions on the stage''s '
  'fixtures. Append-only.';

-- ---------------------------------------------------------------------------
-- The titles
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_titles (
  month_start date     not null
    constraint h2h_cup_titles_month_fkey
      references gamification.h2h_months (month_start),
  place       smallint not null,
  -- The champion, or null when the title is vacant.
  champion    uuid
    constraint h2h_cup_titles_champion_fkey
      references identity.users (id),
  runner_up   uuid
    constraint h2h_cup_titles_runner_up_fkey
      references identity.users (id),
  -- 'final': won the final; 'walkover': the only finalist left;
  -- 'vacant': nobody reached or won the final.
  how         text     not null,
  decided_at  timestamptz not null default now(),
  constraint h2h_cup_titles_pkey primary key (month_start, place),
  constraint h2h_cup_titles_place_range check (place between 1 and 3),
  constraint h2h_cup_titles_how_known
    check (how in ('final', 'walkover', 'vacant')),
  constraint h2h_cup_titles_champion_present
    check ((how = 'vacant') = (champion is null))
);

comment on table gamification.h2h_cup_titles is
  'Each Elite Cup path''s champion and runner-up of a month (0190), or a '
  'vacant title. Append-only.';

-- ---------------------------------------------------------------------------
-- Append-only, server-only
-- ---------------------------------------------------------------------------
drop trigger if exists h2h_cup_entries_reject_mutation
  on gamification.h2h_cup_entries;
create trigger h2h_cup_entries_reject_mutation
  before update or delete on gamification.h2h_cup_entries
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_stages_reject_mutation
  on gamification.h2h_cup_stages;
create trigger h2h_cup_stages_reject_mutation
  before update or delete on gamification.h2h_cup_stages
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_stage_locks_reject_mutation
  on gamification.h2h_cup_stage_locks;
create trigger h2h_cup_stage_locks_reject_mutation
  before update or delete on gamification.h2h_cup_stage_locks
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_stage_fixtures_reject_mutation
  on gamification.h2h_cup_stage_fixtures;
create trigger h2h_cup_stage_fixtures_reject_mutation
  before update or delete on gamification.h2h_cup_stage_fixtures
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_pairs_reject_mutation
  on gamification.h2h_cup_pairs;
create trigger h2h_cup_pairs_reject_mutation
  before update or delete on gamification.h2h_cup_pairs
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_results_reject_mutation
  on gamification.h2h_cup_results;
create trigger h2h_cup_results_reject_mutation
  before update or delete on gamification.h2h_cup_results
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_cup_titles_reject_mutation
  on gamification.h2h_cup_titles;
create trigger h2h_cup_titles_reject_mutation
  before update or delete on gamification.h2h_cup_titles
  for each row execute function gamification.reject_h2h_mutation();

alter table gamification.h2h_cup_entries enable row level security;
alter table gamification.h2h_cup_stages enable row level security;
alter table gamification.h2h_cup_stage_locks enable row level security;
alter table gamification.h2h_cup_stage_fixtures enable row level security;
alter table gamification.h2h_cup_pairs enable row level security;
alter table gamification.h2h_cup_results enable row level security;
alter table gamification.h2h_cup_titles enable row level security;

revoke all on gamification.h2h_cup_entries from anon, authenticated;
revoke all on gamification.h2h_cup_stages from anon, authenticated;
revoke all on gamification.h2h_cup_stage_locks from anon, authenticated;
revoke all on gamification.h2h_cup_stage_fixtures from anon, authenticated;
revoke all on gamification.h2h_cup_pairs from anon, authenticated;
revoke all on gamification.h2h_cup_results from anon, authenticated;
revoke all on gamification.h2h_cup_titles from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0190_h2h_elite_cup')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0190_h2h_elite_cup';                           -- 1 row
-- select relname, relrowsecurity from pg_class
--  where relnamespace = 'gamification'::regnamespace
--    and relname like 'h2h_cup_%';                     -- 7 rows, all true
