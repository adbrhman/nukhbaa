-- ============================================================================
-- Migration 0215: the league plays its 19 rounds past the month's end
-- (script 279)
--
-- ADDITIVE ONLY. One check constraint of 0100 is replaced by a wider one
-- and one guard is added. No row of any table is written, changed or
-- removed.
--
-- Why: decided by the owner on 2026-11-14, from December 2026 on: a
-- month's head-to-head league plays all its 19 rounds, then the Elite Cup
-- and the crowning, even when that runs past the month's end. No round is
-- dropped at the month's end, and the month's champion (the calendar
-- month's points) is not touched. The next month's league does not start
-- before the last crowning, nor before its own month's first day.
--
-- ## What changes
--   * h2h_rounds_day_in_month (0100: a round's day lies in its month) is
--     replaced by h2h_rounds_day_in_cycle: November 2026 and every earlier
--     month keep that rule; from December 2026 a round's day is on or after
--     its month's first day.
--   * gamification.check_h2h_round_cycle(), a BEFORE INSERT guard on
--     h2h_rounds, from December 2026 refuses:
--       - a round after its month's end once the month is judged
--         (h2h_rounds_cycle_judged);
--       - a round of a month while an earlier public month of these rules,
--         not judged, has fewer than 19 rounds (h2h_rounds_cycle_open);
--       - a round on or after the day of a later month's round
--         (h2h_rounds_cycle_open): leagues never overlap.
--     It takes one advisory lock for all months, so two months are never
--     given rounds at the same time.
--
-- ## Rollback
-- NUKHBA_H2H_CYCLE_OVERRUN=off on Northflank: every day is again a round of
-- its own month and a month is judged at its end, as before script 279.
-- The guard then never refuses anything (a month judged at its end has no
-- round after it). Read the state with supabase/queries/h2h_cycle_check.sql.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

alter table gamification.h2h_rounds
  drop constraint if exists h2h_rounds_day_in_month;
alter table gamification.h2h_rounds
  drop constraint if exists h2h_rounds_day_in_cycle;
alter table gamification.h2h_rounds
  add constraint h2h_rounds_day_in_cycle check (
    case
      when month_start < date '2026-12-01'
        then date_trunc('month', day)::date = month_start
      else day >= month_start
    end
  );

create or replace function gamification.check_h2h_round_cycle()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_open date;
begin
  if new.month_start < date '2026-12-01' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('gamification.h2h_round_cycle'));

  if new.day >= (new.month_start + interval '1 month')::date
     and exists (select 1 from gamification.h2h_month_closures c
                  where c.month_start = new.month_start) then
    raise exception 'h2h round on %: the league of % is judged',
      new.day, new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_cycle_judged';
  end if;

  select m.month_start
    into v_open
    from gamification.h2h_months m
   where m.month_start >= date '2026-12-01'
     and m.month_start < new.month_start
     and not m.is_pilot
     and not exists (select 1 from gamification.h2h_month_closures c
                      where c.month_start = m.month_start)
     and (select count(*) from gamification.h2h_rounds r
           where r.month_start = m.month_start) < 19
   order by m.month_start
   limit 1;
  if v_open is not null then
    raise exception 'h2h round of %: the league of % still plays its 19 rounds',
      new.month_start, v_open
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_cycle_open';
  end if;

  if exists (select 1 from gamification.h2h_rounds r
              where r.month_start > new.month_start
                and r.day <= new.day) then
    raise exception 'h2h round on %: a later month already plays on or before it',
      new.day
      using errcode = 'check_violation',
            constraint = 'h2h_rounds_cycle_open';
  end if;
  return new;
end;
$$;

comment on function gamification.check_h2h_round_cycle() is
  'From December 2026 (script 279): a round after its month''s end only '
  'while the month is not judged; no round of a month while an earlier '
  'month still plays its 19 rounds; no round on or after a later month''s '
  'round. November 2026 and earlier are not looked at.';

drop trigger if exists h2h_rounds_cycle_check on gamification.h2h_rounds;
create trigger h2h_rounds_cycle_check
  before insert on gamification.h2h_rounds
  for each row
  execute function gamification.check_h2h_round_cycle();

insert into ops.applied_migrations (version)
values ('0215_h2h_cycle_overrun')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0215_h2h_cycle_overrun';                       -- 1 row
-- select conname from pg_constraint
--  where conname in ('h2h_rounds_day_in_month', 'h2h_rounds_day_in_cycle');
--                                             -- 1 row: h2h_rounds_day_in_cycle
