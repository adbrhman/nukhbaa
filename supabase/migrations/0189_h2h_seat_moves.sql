-- ============================================================================
-- Migration 0189: relegation for absence in the head-to-head league
--
-- ADDITIVE ONLY. Three new append-only tables in `gamification`, two more
-- actions in the admin log of 0101 and one more push link ('h2h'). Nothing
-- is changed or deleted; the draw (h2h_league_members) stays exactly as it
-- was written.
--
-- ## The rules (decided by the owner on 2026-10-31, script 183)
-- A player of the four elite groups (division 1, the elite draw of script
-- 182) who did not predict in three CONSECUTIVE counted rounds leaves his
-- seat before the next round; the most deserving player of the extra groups
-- (division 2) takes it, and the relegated player takes the seat he left:
-- the two seats are SWAPPED. Each player keeps his own month (league points,
-- prediction points, exact scorelines) and plays on from the new seat. A
-- counted round is an approved, locked round whose last kickoff has passed,
-- that still holds a fixture and that an admin did not excuse. The streak
-- runs on across months. An admin may relegate a player by hand (cheating),
-- with a reason. A relegated player does not come back in the same month.
-- No relegation takes effect after round 19.
--
-- ## Tables
--   h2h_seat_moves         one row per swap: who left, who came, the two
--                          seats, the first round played in them, why, and
--                          the facts the substitute was chosen on
--   h2h_round_excusals     rounds an admin took out of the absence count
--                          (the app was down), with the reason
--   h2h_absence_warnings   the warning push after a second absence, once per
--                          round and player
--
-- ## How a seat is read after a move
-- A seat's holder for round n is the draw's member, replaced by every move
-- of that seat whose from_round <= n, in from_round order. The readers do
-- this in SQL (PostgresH2hSheetReader.membersSql, PostgresH2hLeagueStore.
-- seatSql); this migration only stores facts.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The swaps
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_seat_moves (
  id              uuid primary key,
  month_start     date     not null
    constraint h2h_seat_moves_month_fkey
      references gamification.h2h_months (month_start),
  -- The first round played in the new seats.
  from_round      smallint not null,
  -- 'absence': three consecutive counted rounds; 'admin': by hand.
  kind            text     not null,
  -- The player who leaves the elite seat.
  out_user        uuid     not null
    constraint h2h_seat_moves_out_user_fkey
      references identity.users (id),
  -- The player who takes it.
  in_user         uuid     not null
    constraint h2h_seat_moves_in_user_fkey
      references identity.users (id),
  -- The elite seat (division 1) the out_user leaves and the in_user takes.
  elite_league_id uuid     not null
    constraint h2h_seat_moves_elite_league_fkey
      references gamification.h2h_leagues (id),
  elite_slot      smallint not null,
  -- The extra seat (division 2) the in_user leaves and the out_user takes.
  extra_league_id uuid     not null
    constraint h2h_seat_moves_extra_league_fkey
      references gamification.h2h_leagues (id),
  extra_slot      smallint not null,
  -- The absent rounds behind an 'absence' move: [{"month":..,"round":..}].
  absent_rounds   jsonb    not null default '[]'::jsonb,
  -- What the substitute was chosen on: missed, points, exact, active days
  -- over the window, and the window itself.
  candidate       jsonb    not null default '{}'::jsonb,
  -- The admin's reason for an 'admin' move.
  reason          text,
  -- The admin who decided, or null when the system did.
  decided_by      uuid
    constraint h2h_seat_moves_decided_by_fkey
      references identity.users (id),
  created_at      timestamptz not null default now(),
  constraint h2h_seat_moves_kind_known
    check (kind in ('absence', 'admin')),
  constraint h2h_seat_moves_from_round_range
    check (from_round between 2 and 19),
  constraint h2h_seat_moves_two_players
    check (out_user <> in_user),
  constraint h2h_seat_moves_admin_reason
    check (kind <> 'admin' or (reason is not null
                               and length(btrim(reason)) > 0
                               and decided_by is not null)),
  -- A relegated player never comes back in the same month, and a player
  -- is promoted at most once in it.
  constraint h2h_seat_moves_out_once unique (month_start, out_user),
  constraint h2h_seat_moves_in_once  unique (month_start, in_user),
  -- One change per seat and round.
  constraint h2h_seat_moves_elite_seat_round
    unique (elite_league_id, elite_slot, from_round),
  constraint h2h_seat_moves_extra_seat_round
    unique (extra_league_id, extra_slot, from_round)
);

comment on table gamification.h2h_seat_moves is
  'A seat swap of the head-to-head league (0189): a player of an elite '
  'group (division 1) who missed three consecutive counted rounds, or whom '
  'an admin relegated, leaves his seat to the most deserving player of the '
  'extra groups (division 2), who leaves his own seat to him, from '
  'from_round on. Each keeps his own month. Append-only, server-only.';

create index if not exists h2h_seat_moves_month_idx
  on gamification.h2h_seat_moves (month_start, from_round);

-- The backstop for what a constraint cannot say: the two seats belong to
-- the move's month, the elite seat to division 1 and the extra seat to
-- division 2, both inside their groups, and the round is not locked yet.
create or replace function gamification.check_h2h_seat_move()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_elite gamification.h2h_leagues%rowtype;
  v_extra gamification.h2h_leagues%rowtype;
begin
  select * into v_elite from gamification.h2h_leagues
   where id = new.elite_league_id;
  select * into v_extra from gamification.h2h_leagues
   where id = new.extra_league_id;
  if v_elite.id is null or v_extra.id is null then
    return new;  -- the foreign keys report the missing group
  end if;
  if v_elite.month_start <> new.month_start
     or v_extra.month_start <> new.month_start then
    raise exception 'h2h seat move: both groups must belong to month %',
      new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_month_matches';
  end if;
  if v_elite.division <> 1 or v_extra.division <> 2 then
    raise exception 'h2h seat move: an elite seat (1) for an extra seat (2)'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_divisions';
  end if;
  if new.elite_slot < 0 or new.elite_slot >= v_elite.capacity
     or new.extra_slot < 0 or new.extra_slot >= v_extra.capacity then
    raise exception 'h2h seat move: a slot outside its group'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_slot_in_capacity';
  end if;
  if exists (
    select 1 from gamification.h2h_seat_moves m
     where m.month_start = new.month_start
       and m.out_user = new.in_user
  ) then
    raise exception 'h2h seat move: a relegated player does not come back '
      'in the same month'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_no_return';
  end if;
  if exists (
    select 1
      from gamification.h2h_rounds r
      join gamification.h2h_round_locks k on k.round_id = r.id
     where r.month_start = new.month_start
       and r.round_no = new.from_round
  ) then
    raise exception 'h2h seat move: round % already started', new.from_round
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_round_not_started';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_seat_moves_check on gamification.h2h_seat_moves;
create trigger h2h_seat_moves_check
  before insert on gamification.h2h_seat_moves
  for each row
  execute function gamification.check_h2h_seat_move();

-- ---------------------------------------------------------------------------
-- Rounds taken out of the absence count
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_round_excusals (
  round_id    uuid primary key
    constraint h2h_round_excusals_round_fkey
      references gamification.h2h_rounds (id),
  reason      text not null,
  excused_by  uuid not null
    constraint h2h_round_excusals_excused_by_fkey
      references identity.users (id),
  created_at  timestamptz not null default now(),
  constraint h2h_round_excusals_reason_present
    check (length(btrim(reason)) > 0)
);

comment on table gamification.h2h_round_excusals is
  'A round an admin took out of the absence count of the head-to-head '
  'league (0189), e.g. the app was down: it is neither an absence nor a '
  'presence. Append-only, server-only.';

-- ---------------------------------------------------------------------------
-- The warning after a second absence
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_absence_warnings (
  round_id   uuid not null
    constraint h2h_absence_warnings_round_fkey
      references gamification.h2h_rounds (id),
  user_id    uuid not null
    constraint h2h_absence_warnings_user_fkey
      references identity.users (id),
  created_at timestamptz not null default now(),
  constraint h2h_absence_warnings_pkey primary key (round_id, user_id)
);

comment on table gamification.h2h_absence_warnings is
  'The push that warned an elite player after his second consecutive '
  'absence (0189): one per round and player, so it is sent once. '
  'Append-only, server-only.';

-- ---------------------------------------------------------------------------
-- Append-only, server-only
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'h2h_seat_moves', 'h2h_round_excusals', 'h2h_absence_warnings'
  ] loop
    execute format(
      'drop trigger if exists %I on gamification.%I',
      t || '_reject_mutation', t);
    execute format(
      'create trigger %I before update or delete on gamification.%I '
      'for each row execute function gamification.reject_h2h_mutation()',
      t || '_reject_mutation', t);
    execute format(
      'alter table gamification.%I enable row level security', t);
    execute format(
      'revoke all on gamification.%I from anon, authenticated', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- The admin log (0101, widened by 0102) learns the two new actions.
-- ---------------------------------------------------------------------------
alter table gamification.h2h_admin_actions
  drop constraint if exists h2h_admin_actions_action_known;

alter table gamification.h2h_admin_actions
  add constraint h2h_admin_actions_action_known check (action in (
    'settings_saved', 'day_excluded', 'day_included', 'round_approved',
    'round_withdrawn', 'seat_added', 'jobs_run', 'pilot_started',
    'groups_added', 'seat_moved', 'round_excused'
  ));

-- ---------------------------------------------------------------------------
-- A push about the league opens its tab: one more push link (0187 is the
-- last to list them).
-- ---------------------------------------------------------------------------
alter table notification.push_opens
  drop constraint if exists push_opens_link_check;
alter table notification.push_opens
  add constraint push_opens_link_check
    check (link in ('fixtures', 'league', 'inbox', 'duel',
                    'support', 'support_inbox', 'h2h'));

insert into ops.applied_migrations (version)
values ('0189_h2h_seat_moves')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0189_h2h_seat_moves';                          -- 1 row
-- select count(*) from gamification.h2h_seat_moves;                -- 0 at first
