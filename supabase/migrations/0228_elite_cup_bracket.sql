-- ============================================================================
-- Migration 0228: the Elite Cup as ONE knockout bracket of sixteen
--
-- ADDITIVE ONLY. Two check constraints are widened, one function is added
-- and the stage trigger's function is replaced. No row of any table is
-- written, changed or removed, and no table, column, index or trigger is
-- added or dropped.
--
-- Owner decision 2026-11-28 (script 356), replacing the three-path cup that
-- 0227 was widened for: from the draw of December 2026 the first and the
-- second place of each of the EIGHT cup groups qualify -- sixteen players in
-- one bracket, played on four cup days, one round a day:
--
--   day 1  round16   8 pairs    (slots 1..8)
--   day 2  quarter   4 pairs    (slots 1..4)
--   day 3  semi      2 pairs    (slots 1..2)
--   day 4  final     1 pair     (slot 1)       -> the cup's one champion
--
-- The whole bracket is stored as path 1 (place = 1): one stage a day.
--
--   h2h_cup_stages_stage_known  stage  quarter, semi, final
--                                      -> round16, quarter, semi, final
--   h2h_cup_pairs_slot_range    slot   1..4  -> 1..8
--
-- Each new check admits everything 0227 admitted, so every stored row still
-- satisfies it. The place range (1..3), the group range (1..8), the order
-- of the 19 rounds and the append-only triggers are untouched.
--
-- The cup day. 0212's gamification.h2h_cup_day(place, stage) numbers the
-- stages of the OLD three-path cup (path 1 semi = day 1, path 1 final = day
-- 2, ...) and would count a bracket's quarter-final as day 2 and its
-- semi-final as day 1, so the stage trigger would refuse the semi-final.
-- This migration adds gamification.h2h_cup_bracket_day(stage) (round16 = 1,
-- quarter = 2, semi = 3, final = 4) and the trigger uses it for a month that
-- holds a round16 or a quarter stage; every other month (November 2026 and
-- every cup already stored) keeps 0212's numbering, unchanged. The three
-- other rules of the trigger are unchanged: a stage only after the month's
-- 19 rounds and after the last round's day, a day holds the stages of one
-- month only, and a stage never comes before an earlier cup day's stage.
--
-- Nothing in the server writes a round of sixteen yet: this migration only
-- makes the database accept it. Apply it in the SQL Editor BEFORE the server
-- that writes the bracket is deployed (migration-drift fails the push when
-- the live database lacks it).
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table gamification.h2h_cup_stages
  drop constraint if exists h2h_cup_stages_stage_known;
alter table gamification.h2h_cup_stages
  add constraint h2h_cup_stages_stage_known
  check (stage in ('round16', 'quarter', 'semi', 'final'));

alter table gamification.h2h_cup_pairs
  drop constraint if exists h2h_cup_pairs_slot_range;
alter table gamification.h2h_cup_pairs
  add constraint h2h_cup_pairs_slot_range
  check (slot between 1 and 8);

-- The cup day (1 to 4) of a bracket round; null for any other text.
create or replace function gamification.h2h_cup_bracket_day(p_stage text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select (case p_stage
            when 'round16' then 1
            when 'quarter' then 2
            when 'semi'    then 3
            when 'final'   then 4
          end)::smallint;
$$;

comment on function gamification.h2h_cup_bracket_day(text) is
  'The Elite Cup day of a bracket round (0228): 1 round of sixteen, 2 '
  'quarter-finals, 3 semi-finals, 4 final.';

create or replace function gamification.check_h2h_cup_stage()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_rounds   integer;
  v_last_day date;
  v_bracket  boolean;
  v_cup_day  smallint;
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
    where s.day = new.day and s.month_start <> new.month_start
  ) then
    raise exception 'day % holds another month''s cup', new.day
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_day_taken';
  end if;
  -- A bracket month is one that holds (or is given) a round of sixteen or a
  -- quarter-final; the old three-path months never have either.
  v_bracket := new.stage in ('round16', 'quarter')
    or exists (
      select 1 from gamification.h2h_cup_stages s
      where s.month_start = new.month_start
        and s.stage in ('round16', 'quarter')
    );
  v_cup_day := case when v_bracket
                    then gamification.h2h_cup_bracket_day(new.stage)
                    else gamification.h2h_cup_day(new.place, new.stage)
               end;
  if exists (
    select 1 from gamification.h2h_cup_stages s
    where s.month_start = new.month_start
      and (s.day > new.day
           or (case when v_bracket
                    then gamification.h2h_cup_bracket_day(s.stage)
                    else gamification.h2h_cup_day(s.place, s.stage)
               end) > v_cup_day
           or (s.day = new.day
               and (case when v_bracket
                         then gamification.h2h_cup_bracket_day(s.stage)
                         else gamification.h2h_cup_day(s.place, s.stage)
                    end) <> v_cup_day))
  ) then
    raise exception 'stage day % is not after the cup''s last stage', new.day
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_in_order';
  end if;
  return new;
end;
$$;

comment on table gamification.h2h_cup_stages is
  'One stage of the Elite Cup on one day (0190, 0212, 0228). The cup''s four '
  'days come one after the other, after the month''s 19 rounds: a bracket '
  'month plays round16, quarter, semi and final on path 1; an older month '
  'plays three paths that share days 3 and 4. Append-only.';

insert into ops.applied_migrations (version)
values ('0228_elite_cup_bracket')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0228_elite_cup_bracket';                         -- 1 row
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conname in ('h2h_cup_stages_stage_known',
--                    'h2h_cup_pairs_slot_range');                    -- 2 rows
--   stage in (round16, quarter, semi, final), slot 1..8
-- select gamification.h2h_cup_bracket_day('semi');                   -- 3
