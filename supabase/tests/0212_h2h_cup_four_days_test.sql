-- Migration 0212 (the Elite Cup in four days, script 276): paths 2 and 3
-- share their days, everything else 0190 refused is still refused. The
-- stage insert and the stages read are PostgresH2hCupStore.stageSql and
-- stagesSql, text for text, with @name::type turned into $n::type. Rolled
-- back at the end.
\set ON_ERROR_STOP on
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
    perform pg_temp.check(name is null or v_name = name, label || ' (' || coalesce(v_name, sqlerrm) || ')');
    return;
  end;
  raise exception 'FAILED: % (not refused)', label;
end $$;

-- stageSql
PREPARE cup_stage(uuid, date, smallint, text, smallint, date, smallint) AS
INSERT INTO gamification.h2h_cup_stages
  (id, month_start, place, stage, attempt, day, fixture_count)
VALUES ($1::uuid, $2::date, $3::smallint, $4, $5::smallint,
        $6::date, $7::smallint);

-- stagesSql
PREPARE cup_stages(date) AS
SELECT s.id::text AS id, s.place, s.stage, s.attempt,
       to_char(s.day, 'YYYY-MM-DD') AS day,
       COALESCE(k.fixture_count, s.fixture_count)::integer AS fixture_count,
       k.locked_at
FROM gamification.h2h_cup_stages s
LEFT JOIN gamification.h2h_cup_stage_locks k ON k.stage_id = s.id
WHERE s.month_start = $1::date
ORDER BY s.day, s.place, s.attempt;

-- ---------------------------------------------------------------------------
-- The world: November and December 2098, each with its 19 rounds.
-- November's rounds on the 1st..19th, December's on the 1st..19th.
-- ---------------------------------------------------------------------------
insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2098-11-01', false, 80), ('2098-12-01', false, 80);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2120000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2098-11-01', n, ('2098-11-01'::date + (n - 1)), 6
from generate_series(1, 19) n;
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2120000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       '2098-12-01', n, ('2098-12-01'::date + (n - 1)), 6
from generate_series(1, 19) n;

select pg_temp.check(
  not exists (select 1 from pg_constraint where conname = 'h2h_cup_stages_day_uniq'),
  'one stage a day is gone');
select pg_temp.check(
  (select gamification.h2h_cup_day(1::smallint, 'semi')) = 1
  and (select gamification.h2h_cup_day(1::smallint, 'final')) = 2
  and (select gamification.h2h_cup_day(2::smallint, 'semi')) = 3
  and (select gamification.h2h_cup_day(3::smallint, 'semi')) = 3
  and (select gamification.h2h_cup_day(2::smallint, 'final')) = 4
  and (select gamification.h2h_cup_day(3::smallint, 'final')) = 4,
  'the four cup days');

-- ---------------------------------------------------------------------------
-- November's cup in four days: 20th, 21st, 22nd (two), 23rd (two).
-- ---------------------------------------------------------------------------
execute cup_stage('c2120000-0000-4000-8000-0000000005a1', '2098-11-01', 1, 'semi', 1, '2098-11-20', 8);
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 1, 'final', 1, '2098-11-20', 8)$q$,
  'h2h_cup_stages_in_order', 'path 1''s final is not on its semi-finals'' day');
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 2, 'semi', 1, '2098-11-20', 8)$q$,
  'h2h_cup_stages_in_order', 'path 2 does not share path 1''s day');
execute cup_stage('c2120000-0000-4000-8000-0000000005a2', '2098-11-01', 1, 'final', 1, '2098-11-21', 8);

execute cup_stage('c2120000-0000-4000-8000-0000000005a3', '2098-11-01', 2, 'semi', 1, '2098-11-22', 8);
execute cup_stage('c2120000-0000-4000-8000-0000000005a4', '2098-11-01', 3, 'semi', 1, '2098-11-22', 8);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stages where day = '2098-11-22') = 2,
  'paths 2 and 3 play their semi-finals on the same day');
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 3, 'semi', 2, '2098-11-22', 8)$q$,
  'h2h_cup_stages_day_place_uniq', 'one stage a day for each path');
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 2, 'final', 1, '2098-11-22', 8)$q$,
  'h2h_cup_stages_in_order', 'a final is not on the semi-finals'' day');

execute cup_stage('c2120000-0000-4000-8000-0000000005a5', '2098-11-01', 2, 'final', 1, '2098-11-23', 8);
execute cup_stage('c2120000-0000-4000-8000-0000000005a6', '2098-11-01', 3, 'final', 1, '2098-11-23', 8);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stages where day = '2098-11-23') = 2,
  'and their two finals on the next day');
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 3, 'semi', 2, '2098-11-24', 8)$q$,
  'h2h_cup_stages_in_order', 'no semi-final after a final');
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005a9', '2098-11-01', 1, 'final', 2, '2098-11-24', 8)$q$,
  'h2h_cup_stages_in_order', 'no earlier cup day after a later one');

create temp table stages_out as execute cup_stages('2098-11-01');
select pg_temp.check(
  (select string_agg(place || stage || '@' || day, ',' order by day, place, attempt) from stages_out)
  = '1semi@2098-11-20,1final@2098-11-21,2semi@2098-11-22,3semi@2098-11-22,2final@2098-11-23,3final@2098-11-23',
  'the stages read back in day and path order');

-- ---------------------------------------------------------------------------
-- A carried cup day: both paths move on, each to a later day.
-- ---------------------------------------------------------------------------
execute cup_stage('c2120000-0000-4000-8000-0000000005b1', '2098-12-01', 1, 'semi', 1, '2098-12-20', 8);
execute cup_stage('c2120000-0000-4000-8000-0000000005b2', '2098-12-01', 1, 'final', 1, '2098-12-21', 8);
execute cup_stage('c2120000-0000-4000-8000-0000000005b3', '2098-12-01', 2, 'semi', 1, '2098-12-24', 0);
execute cup_stage('c2120000-0000-4000-8000-0000000005b4', '2098-12-01', 3, 'semi', 1, '2098-12-24', 0);
execute cup_stage('c2120000-0000-4000-8000-0000000005b5', '2098-12-01', 2, 'semi', 2, '2098-12-26', 8);
execute cup_stage('c2120000-0000-4000-8000-0000000005b6', '2098-12-01', 3, 'semi', 2, '2098-12-26', 8);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stages where month_start = '2098-12-01') = 6,
  'a cup day carried for both paths');

-- ---------------------------------------------------------------------------
-- A day holds one month's cup only.
-- ---------------------------------------------------------------------------
insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2098-10-01', false, 80);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2120000-0000-4000-8000-0000000003' || lpad(n::text, 2, '0'))::uuid,
       '2098-10-01', n, ('2098-10-01'::date + (n - 1)), 6
from generate_series(1, 19) n;
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005c1', '2098-10-01', 2, 'final', 3, '2098-11-23', 8)$q$,
  'h2h_cup_stages_day_taken', 'another month''s cup day is refused');
-- Even for a path that day does not hold.
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005c1', '2098-10-01', 1, 'final', 3, '2098-11-23', 8)$q$,
  'h2h_cup_stages_day_taken', 'another month''s day is taken for every path');

-- Still before nothing: the 19 rounds and the last round's day.
select pg_temp.refused($q$execute cup_stage('c2120000-0000-4000-8000-0000000005c2', '2098-12-01', 3, 'final', 1, '2098-12-19', 8)$q$,
  'h2h_cup_stages_after_league', 'no stage on the last round''s day');

select pg_temp.check(
  (select count(*) from ops.applied_migrations where version = '0212_h2h_cup_four_days') = 1,
  'the migration records itself');

rollback;
