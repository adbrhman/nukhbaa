-- ============================================================================
-- Migration 0212: the Elite Cup in four days (script 276)
--
-- ADDITIVE ONLY. No row of any table is written, changed or removed. One
-- constraint is replaced by a narrower index, one function is added and
-- the stage trigger's function is replaced.
--
-- Why: decided by the owner on 2026-11-14. The cup of a month is played on
-- four match days instead of six:
--   day 1  the first places' semi-finals (path 1)
--   day 2  their final: the Elite Cup's champion
--   day 3  the second places' semi-finals (path 2) AND the third places'
--          semi-finals (path 3), two separate cups on the same day
--   day 4  the two finals together: the cup's second and third
-- The draw and the tie-break stay as they were (0190).
--
-- What 0190 refused and now allows: two stages on one day, when they are
-- the two paths of the same cup day (paths 2 and 3, both semi-finals or
-- both finals). Everything else it refused is still refused:
--   * h2h_cup_stages_day_uniq (one stage a day) is replaced by the unique
--     index h2h_cup_stages_day_place_uniq (one stage a day for each path);
--   * a day holds the stages of one month only
--     (h2h_cup_stages_day_taken), as day_uniq made sure before;
--   * a stage comes after the month's 19 rounds
--     (h2h_cup_stages_after_league, unchanged);
--   * a stage's day is after every stage of its month, or the same day
--     for a stage of the same cup day; and no stage of an earlier cup day
--     comes after one of a later cup day (h2h_cup_stages_in_order).
--
-- Apply BEFORE pushing. Safe to re-run.
-- ============================================================================

begin;

-- The cup day (1 to 4) a path and round are played on.
create or replace function gamification.h2h_cup_day(p_place smallint, p_stage text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select (case
            when p_place = 1 and p_stage = 'semi' then 1
            when p_place = 1 then 2
            when p_stage = 'semi' then 3
            else 4
          end)::smallint;
$$;

comment on function gamification.h2h_cup_day(smallint, text) is
  'The Elite Cup day of a stage (0212): 1 path 1 semi-finals, 2 path 1 '
  'final, 3 paths 2 and 3 semi-finals, 4 paths 2 and 3 finals.';

alter table gamification.h2h_cup_stages
  drop constraint if exists h2h_cup_stages_day_uniq;

create unique index if not exists h2h_cup_stages_day_place_uniq
  on gamification.h2h_cup_stages (day, place);

create or replace function gamification.check_h2h_cup_stage()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_rounds   integer;
  v_last_day date;
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
  v_cup_day := gamification.h2h_cup_day(new.place, new.stage);
  if exists (
    select 1 from gamification.h2h_cup_stages s
    where s.month_start = new.month_start
      and (s.day > new.day
           or gamification.h2h_cup_day(s.place, s.stage) > v_cup_day
           or (s.day = new.day
               and gamification.h2h_cup_day(s.place, s.stage) <> v_cup_day))
  ) then
    raise exception 'stage day % is not after the cup''s last stage', new.day
      using errcode = 'check_violation',
            constraint = 'h2h_cup_stages_in_order';
  end if;
  return new;
end;
$$;

comment on table gamification.h2h_cup_stages is
  'One stage of the Elite Cup on one day (0190, 0212). The cup''s four days '
  'come one after the other, after the month''s 19 rounds; paths 2 and 3 '
  'share their days. Append-only.';

insert into ops.applied_migrations (version)
values ('0212_h2h_cup_four_days')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0212_h2h_cup_four_days';                       -- 1 row
-- select conname from pg_constraint
--  where conname = 'h2h_cup_stages_day_uniq';                      -- 0 rows
-- select indexname from pg_indexes
--  where indexname = 'h2h_cup_stages_day_place_uniq';              -- 1 row
