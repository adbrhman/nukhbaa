-- Migration 0215 (the league plays its 19 rounds past the month's end,
-- script 279): from December 2026 a month's rounds go on after its end
-- until the 19th; the next month waits for them; a judged month takes no
-- more; November 2026 and earlier keep a round inside its month. The round
-- insert is PostgresH2hRoundStore.approveSql, text for text, with
-- @name::type turned into $n::type, and the owner's file is read as it is.
-- Rolled back at the end.
\set ON_ERROR_STOP on
\set check_sql `sed -e 's/--.*$//' supabase/queries/h2h_cycle_check.sql | tr '\n' ' ' | sed -e 's/; *$//'`
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- A statement that must be refused with constraint [name].
create function pg_temp.refused(stmt text, name text, label text)
returns void language plpgsql as $$
declare
  v_name text;
begin
  begin
    execute stmt;
  exception when others then
    get stacked diagnostics v_name = constraint_name;
    perform pg_temp.check(v_name = name, label || ' (' || coalesce(v_name, sqlerrm) || ')');
    return;
  end;
  raise exception 'FAILED: % (not refused)', label;
end $$;

-- approveSql
PREPARE approve(uuid, date, smallint, date, smallint, uuid) AS
INSERT INTO gamification.h2h_rounds
  (id, month_start, round_no, day, fixture_count, approved_by)
VALUES ($1::uuid, $2::date, $3::smallint, $4::date,
        $5::smallint, $6::uuid);

select pg_temp.check(
  not exists (select 1 from pg_constraint where conname = 'h2h_rounds_day_in_month')
  and exists (select 1 from pg_constraint where conname = 'h2h_rounds_day_in_cycle')
  and exists (select 1 from pg_trigger where tgname = 'h2h_rounds_cycle_check'
                and not tgisinternal),
  'the wider day rule and the cycle guard are in');
select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0215_h2h_cycle_overrun'),
  'the migration recorded itself');

-- ---------------------------------------------------------------------------
-- December 2098 starts late: 17 rounds by its last day.
-- ---------------------------------------------------------------------------
insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2098-12-01', false, 80), ('2099-01-01', false, 80),
       ('2099-02-01', false, 80);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2150000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2098-12-01', n, ('2098-12-13'::date + (n - 1)), 6
from generate_series(1, 17) n;

execute approve('c2150000-0000-4000-8000-000000000118', '2098-12-01', 18, '2099-01-02', 7, null);
select pg_temp.check(
  (select month_start from gamification.h2h_rounds where day = '2099-01-02') = '2098-12-01',
  'round 18 on 2 January is December''s');

select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000201', '2099-01-01', 1, '2099-01-03', 8, null)$q$,
  'h2h_rounds_cycle_open', 'January takes no round while December has 18');

execute approve('c2150000-0000-4000-8000-000000000119', '2098-12-01', 19, '2099-01-03', 7, null);
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000120', '2098-12-01', 20, '2099-01-04', 7, null)$q$,
  'h2h_rounds_round_no_range', 'no twentieth round');
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000201', '2099-01-01', 1, '2099-01-03', 8, null)$q$,
  'h2h_rounds_day_uniq', 'January''s first round is not on December''s last');

-- The cup takes 4 to 7 January; January's league starts on the 8th.
execute approve('c2150000-0000-4000-8000-000000000201', '2099-01-01', 1, '2099-01-08', 9, null);
select pg_temp.check(
  (select count(*) from gamification.h2h_rounds where month_start = '2098-12-01') = 19
  and (select count(*) from gamification.h2h_rounds where month_start = '2099-01-01') = 1,
  'December kept its 19 rounds, January started after them');

-- ---------------------------------------------------------------------------
-- A later month waits while an earlier league plays; a judged month takes
-- no round after its end.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000301', '2099-02-01', 1, '2099-02-02', 6, null)$q$,
  'h2h_rounds_cycle_open', 'February waits while January plays');
insert into gamification.h2h_month_closures (month_start, member_count)
values ('2099-01-01', 80);
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000202', '2099-01-01', 2, '2099-02-05', 6, null)$q$,
  'h2h_rounds_cycle_judged', 'a judged January takes no round in February');
execute approve('c2150000-0000-4000-8000-000000000301', '2099-02-01', 1, '2099-02-02', 6, null);
select pg_temp.check(
  (select count(*) from gamification.h2h_rounds where month_start = '2099-02-01') = 1,
  'once January is judged, February plays');

-- A pilot month never holds the league back.
insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-04-01', true, 20);
insert into gamification.h2h_month_closures (month_start, member_count)
values ('2099-02-01', 80);
execute approve('c2150000-0000-4000-8000-000000000401', '2099-04-01', 1, '2099-04-02', 6, null);
execute approve('c2150000-0000-4000-8000-000000000501', '2099-05-01', 1, '2099-05-02', 6, null);
select pg_temp.check(
  (select count(*) from gamification.h2h_rounds where month_start = '2099-05-01') = 1,
  'a pilot''s unfinished rounds hold no month back');
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000402', '2099-04-01', 2, '2099-05-03', 6, null)$q$,
  'h2h_rounds_cycle_open', 'no round on or after a later month''s round');

-- ---------------------------------------------------------------------------
-- November 2026 keeps its rule: a round inside its month.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000302', '2099-03-01', 1, '2099-02-27', 6, null)$q$,
  'h2h_rounds_day_in_cycle', 'from December 2026 a round is never before its month');
select pg_temp.refused($q$execute approve('c2150000-0000-4000-8000-000000000601', '2026-10-01', 1, '2026-11-02', 6, null)$q$,
  'h2h_rounds_day_in_cycle', 'before December 2026 a round lies inside its month');

-- ---------------------------------------------------------------------------
-- The owner's file
-- ---------------------------------------------------------------------------
create temp table check_out as select * from (:check_sql) q;
select pg_temp.check(
  (select rounds || '|' || last_round || '|' || after_month_end || '|' || judged
          || '|' || cup_titles || '|' || next_month_first_round
     from check_out where month = '2098-12') = '19|2099-01-03|2|false|0|2099-01-08',
  'the owner''s check: December with 19 rounds, 2 after its end, January on the 8th');
select pg_temp.check(
  (select judged from check_out where month = '2099-01') is true,
  'the owner''s check: January judged');

rollback;
