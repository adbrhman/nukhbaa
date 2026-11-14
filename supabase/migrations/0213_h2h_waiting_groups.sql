-- ============================================================================
-- Migration 0213: new players and the waiting group (script 277)
--
-- ADDITIVE ONLY. Three new append-only tables, one read-only view, their
-- guards and grants. No row of any existing table is written, changed or
-- removed, and no existing constraint or trigger is touched.
--
-- Why: decided by the owner on 2026-11-14, from December 2026 on:
--   * a new player joins the head-to-head league at his first real
--     prediction, not at registration, into the month's waiting group;
--   * a waiting group is not a competing group: it plays no round, and no
--     result or absence counts for its players, until its twentieth player
--     joins; it then starts from the first round of the month that has not
--     started, and the groups already playing are not touched;
--   * a group that starts with fewer than seven rounds left plays them and
--     keeps its results, but takes no part in the month's promotion and
--     relegation (decided in the application: H2hLeaguePolicy.
--     countsForMovement).
-- November 2026 and every earlier month are left exactly as they are: each
-- guard below refuses a row for a month before December 2026, and a group
-- without a row here is read as before (from round 1).
--
-- Tables
--   h2h_waiting_groups     a group of the extra division that waits for its
--                          twentieth player (opened by the draw or by the
--                          first new player). One open at a time a month.
--   h2h_group_starts       the round a waiting group starts from, written
--                          once, when it holds twenty players, and never a
--                          round that has started.
--   h2h_newcomer_seatings  why a seat was taken after the draw: a new
--                          player at his first prediction. One a month a
--                          player, tied to his seat row.
-- View
--   h2h_movements          every move of a player in a month, with its
--                          reason: the draw, a new player, a group start,
--                          a seat swap (0189) and the month's end (0100,
--                          NK275, NK277). Read-only, server-only.
--
-- Apply BEFORE pushing. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- The waiting groups
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_waiting_groups (
  league_id   uuid primary key
    constraint h2h_waiting_groups_league_fkey
      references gamification.h2h_leagues (id),
  month_start date not null,
  opened_at   timestamptz not null default now()
);

comment on table gamification.h2h_waiting_groups is
  'A group of the extra division that waits for its twentieth player '
  '(0213, December 2026 on): it plays no round before it starts '
  '(h2h_group_starts). Append-only, server-only.';

create or replace function gamification.check_h2h_waiting_group()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_league gamification.h2h_leagues%rowtype;
begin
  select * into v_league from gamification.h2h_leagues
   where id = new.league_id;
  if v_league.id is null then
    return new;  -- the foreign key reports the missing group
  end if;
  if v_league.month_start <> new.month_start then
    raise exception 'h2h waiting group: month % differs from its group''s %',
      new.month_start, v_league.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_groups_month_matches';
  end if;
  if new.month_start < date '2026-12-01' then
    raise exception 'h2h waiting group: none before December 2026 (%)',
      new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_groups_december_on';
  end if;
  if v_league.division <> 2 or v_league.capacity <> 20 then
    raise exception 'h2h waiting group: an extra group of twenty seats'
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_groups_extra_twenty';
  end if;
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_waiting_groups'),
    hashtext(new.month_start::text)
  );
  if exists (
    select 1 from gamification.h2h_waiting_groups w
     where w.month_start = new.month_start
       and not exists (
         select 1 from gamification.h2h_group_starts s
          where s.league_id = w.league_id
       )
  ) then
    raise exception 'h2h waiting group: % already has one waiting',
      new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_groups_one_open';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The start of a waiting group
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_group_starts (
  league_id  uuid primary key
    constraint h2h_group_starts_waiting_fkey
      references gamification.h2h_waiting_groups (league_id),
  from_round smallint not null,
  started_at timestamptz not null default now(),
  constraint h2h_group_starts_round_range check (from_round between 1 and 19)
);

comment on table gamification.h2h_group_starts is
  'The round a waiting group starts from (0213): written once, when it '
  'holds twenty players, never a round that has started. Append-only, '
  'server-only.';

-- The waiting-group trigger reads h2h_group_starts: created after it.
drop trigger if exists h2h_waiting_groups_check
  on gamification.h2h_waiting_groups;
create trigger h2h_waiting_groups_check
  before insert on gamification.h2h_waiting_groups
  for each row
  execute function gamification.check_h2h_waiting_group();

create or replace function gamification.check_h2h_group_start()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month   date;
  v_members integer;
  v_played  integer;
begin
  select w.month_start into v_month
    from gamification.h2h_waiting_groups w
   where w.league_id = new.league_id;
  if v_month is null then
    return new;  -- the foreign key reports the missing waiting group
  end if;
  select count(*) into v_members
    from gamification.h2h_league_members m
   where m.league_id = new.league_id;
  if v_members < 20 then
    raise exception 'h2h group start: % holds % players, not 20',
      new.league_id, v_members
      using errcode = 'check_violation',
            constraint = 'h2h_group_starts_twenty';
  end if;
  select coalesce(max(r.round_no), 0) into v_played
    from gamification.h2h_rounds r
    join gamification.h2h_round_locks k on k.round_id = r.id
   where r.month_start = v_month;
  if new.from_round <= v_played then
    raise exception 'h2h group start: round % has started (last %)',
      new.from_round, v_played
      using errcode = 'check_violation',
            constraint = 'h2h_group_starts_not_played';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_group_starts_check on gamification.h2h_group_starts;
create trigger h2h_group_starts_check
  before insert on gamification.h2h_group_starts
  for each row
  execute function gamification.check_h2h_group_start();

-- ---------------------------------------------------------------------------
-- Why a seat was taken after the draw
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_newcomer_seatings (
  month_start date not null,
  user_id     uuid not null,
  league_id   uuid not null,
  seated_at   timestamptz not null default now(),
  constraint h2h_newcomer_seatings_pkey primary key (month_start, user_id),
  constraint h2h_newcomer_seatings_seat_fkey foreign key (league_id, user_id)
    references gamification.h2h_league_members (league_id, user_id)
);

comment on table gamification.h2h_newcomer_seatings is
  'A seat taken by a new player at his first prediction (0213): in the '
  'month''s waiting group, before it starts. Append-only, server-only.';

create or replace function gamification.check_h2h_newcomer_seating()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month date;
begin
  select w.month_start into v_month
    from gamification.h2h_waiting_groups w
   where w.league_id = new.league_id;
  if v_month is null
     or exists (
       select 1 from gamification.h2h_group_starts s
        where s.league_id = new.league_id
     ) then
    raise exception 'h2h newcomer: % is not a waiting group that has not '
      'started', new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_newcomer_seatings_waiting_only';
  end if;
  if v_month <> new.month_start then
    raise exception 'h2h newcomer: month % differs from the group''s %',
      new.month_start, v_month
      using errcode = 'check_violation',
            constraint = 'h2h_newcomer_seatings_month_matches';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_newcomer_seatings_check
  on gamification.h2h_newcomer_seatings;
create trigger h2h_newcomer_seatings_check
  before insert on gamification.h2h_newcomer_seatings
  for each row
  execute function gamification.check_h2h_newcomer_seating();

-- ---------------------------------------------------------------------------
-- Every move of a player, with its reason (read-only)
-- ---------------------------------------------------------------------------
create or replace view gamification.h2h_movements
with (security_invoker = true)
as
select m.month_start,
       m.user_id,
       'seat'::text                                         as kind,
       case when n.user_id is null then 'draw' else 'newcomer' end
                                                            as reason,
       null::uuid                                           as from_league_id,
       m.league_id                                          as to_league_id,
       null::smallint                                       as from_round,
       coalesce(n.seated_at, m.joined_at)                   as at
from gamification.h2h_league_members m
left join gamification.h2h_newcomer_seatings n
  on n.month_start = m.month_start and n.user_id = m.user_id
union all
select w.month_start, null::uuid, 'group_start', null, null, s.league_id,
       s.from_round, s.started_at
from gamification.h2h_group_starts s
join gamification.h2h_waiting_groups w on w.league_id = s.league_id
union all
select mv.month_start, mv.out_user, 'seat_move_down', mv.kind,
       mv.elite_league_id, mv.extra_league_id, mv.from_round, mv.created_at
from gamification.h2h_seat_moves mv
union all
select mv.month_start, mv.in_user, 'seat_move_up', mv.kind,
       mv.extra_league_id, mv.elite_league_id, mv.from_round, mv.created_at
from gamification.h2h_seat_moves mv
union all
select (e.payload->>'month')::date, e.user_id, 'month_end',
       coalesce(e.payload->>'reason', e.payload->>'outcome'),
       e.ref_id, null, null, e.occurred_at
from gamification.events e
where e.event_type = 'h2h_league_finished';

comment on view gamification.h2h_movements is
  'Every move of a head-to-head player with its reason (0213): the draw, '
  'a new player, a group start, a seat swap, the month''s end. Read-only, '
  'server-only; read by supabase/queries/h2h_movements.sql.';

-- ---------------------------------------------------------------------------
-- Append-only, server-only
-- ---------------------------------------------------------------------------
drop trigger if exists h2h_waiting_groups_reject_mutation
  on gamification.h2h_waiting_groups;
create trigger h2h_waiting_groups_reject_mutation
  before update or delete on gamification.h2h_waiting_groups
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_group_starts_reject_mutation
  on gamification.h2h_group_starts;
create trigger h2h_group_starts_reject_mutation
  before update or delete on gamification.h2h_group_starts
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_newcomer_seatings_reject_mutation
  on gamification.h2h_newcomer_seatings;
create trigger h2h_newcomer_seatings_reject_mutation
  before update or delete on gamification.h2h_newcomer_seatings
  for each row execute function gamification.reject_h2h_mutation();

alter table gamification.h2h_waiting_groups enable row level security;
alter table gamification.h2h_group_starts enable row level security;
alter table gamification.h2h_newcomer_seatings enable row level security;

revoke all on gamification.h2h_waiting_groups from anon, authenticated;
revoke all on gamification.h2h_group_starts from anon, authenticated;
revoke all on gamification.h2h_newcomer_seatings from anon, authenticated;
revoke all on gamification.h2h_movements from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0213_h2h_waiting_groups')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0213_h2h_waiting_groups';                      -- 1 row
-- select relname, relrowsecurity from pg_class
--  where relnamespace = 'gamification'::regnamespace
--    and relname in ('h2h_waiting_groups', 'h2h_group_starts',
--                    'h2h_newcomer_seatings');                -- 3 rows, true
