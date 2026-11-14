-- The read-only month's turnover check (script 273):
-- supabase/queries/month_turnover_check.sql, run as it is (its comments
-- stripped, its month moved to November 2099 and its clock to 20 November
-- 2099 15:00 Riyadh) over a seeded month: twelve rounds approved (eleven
-- locked, the third void), an excluded day, six fixtures known on the 21st,
-- three on the 22nd, one today, a match four hours old and one two days old without a
-- result. It must count what the jobs will see. Rolled back.
\set ON_ERROR_STOP on
\set check_sql `sed -e 's/--.*$//' -e "s/date '2026-11-01'/date '2099-11-01'/" -e "s/now() as now_at/timestamptz '2099-11-20 12:00Z' as now_at/" supabase/queries/month_turnover_check.sql | tr '\n' ' ' | sed -e 's/; *$//'`
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

create function pg_temp.fx(i integer) returns uuid
language sql immutable as $$
  select ('c2730000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c2730000-0000-4000-8001-000000000001', 'Monthly 273', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2730000-0000-4000-8001-000000000010', 'c2730000-0000-4000-8001-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');

-- Six fixtures on 21 November (Riyadh), three on the 22nd, and three past
-- ones: 18 November without a result, 19 November with one, 20 November
-- 08:00Z (four hours before the clock) without one.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
select pg_temp.fx(n), 'H' || n, 'A' || n,
       timestamptz '2099-11-21 12:00Z' + (n - 1) * interval '30 minutes'
from generate_series(1, 6) n;
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
select pg_temp.fx(n), 'H' || n, 'A' || n,
       timestamptz '2099-11-22 12:00Z' + (n - 7) * interval '30 minutes'
from generate_series(7, 9) n;
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  (pg_temp.fx(10), 'Old', 'Late', '2099-11-18 12:00Z'),
  (pg_temp.fx(11), 'Done', 'Here', '2099-11-19 12:00Z'),
  (pg_temp.fx(12), 'Fresh', 'Wait', '2099-11-20 08:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c2730000-0000-4000-8001-000000000010', pg_temp.fx(n), n
from generate_series(1, 12) n;
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
values (pg_temp.fx(11), 1, 0, '2099-11-19 14:00Z');

-- The league: drawn, twelve rounds on days 1..12, eleven locked, the third
-- void; the 25th excluded.
insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-11-01', false, 84);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2730000-0000-4000-8002-' || lpad(n::text, 12, '0'))::uuid,
       '2099-11-01', n, date '2099-11-01' + (n - 1), 7
from generate_series(1, 12) n;
insert into gamification.h2h_round_locks (round_id, fixture_count)
select ('c2730000-0000-4000-8002-' || lpad(n::text, 12, '0'))::uuid,
       case when n = 3 then 0 else 7 end
from generate_series(1, 11) n;
insert into gamification.h2h_day_exclusions (day) values ('2099-11-25');

create temp table out as :check_sql;

create function pg_temp.v(name text) returns text
language sql as $$ select value from out where check_name = name $$;
create function pg_temp.s(name text) returns text
language sql as $$ select status from out where check_name = name $$;

do $$
begin
  perform pg_temp.check(
    (select count(*) from out) = 23, 'twenty-three lines, the crown''s six included');
  perform pg_temp.check(
    pg_temp.v('الشهر مسحوب') = '84 لاعباً' and pg_temp.s('الشهر مسحوب') = 'سليم',
    'the month is drawn');
  perform pg_temp.check(
    pg_temp.v('الجولات المعتمدة من 19') = '12 (مقفلة 11، ملغاة 1)',
    'twelve rounds, eleven locked, one void');
  perform pg_temp.check(
    pg_temp.v('آخر جولة') = '12 يوم 11-12', 'the last round is the 12th');
  -- From today (the 20th) to the 30th, less the excluded 25th: ten days
  -- for seven rounds.
  perform pg_temp.check(
    pg_temp.v('الأيام الباقية للجولات الباقية') = '10 يوماً لـ 7 جولة'
      and pg_temp.s('الأيام الباقية للجولات الباقية') = 'سليم',
    'ten days left for seven rounds');
  perform pg_temp.check(
    pg_temp.v('مباريات الأيام الباقية المعروفة الآن') like '11-20:1 11-21:6 11-22:3 11-23:0 %'
      and pg_temp.v('مباريات الأيام الباقية المعروفة الآن') like '%(6 فأكثر: 1 يوماً)',
    'the known fixtures a day, one day of six');
  perform pg_temp.check(
    pg_temp.v('مباريات الأيام الباقية المعروفة الآن') not like '%11-25%',
    'the excluded day is not counted');
  perform pg_temp.check(
    pg_temp.v('أيام مستبعدة في الشهر') = '1: 11-25', 'the excluded day is listed');
  -- Seven rounds and six cup steps need thirteen days of ten.
  perform pg_temp.check(
    pg_temp.v('أيام لازمة للدوري والكأس') = '13 يوماً من 10 باقية',
    'thirteen days needed of ten');
  perform pg_temp.check(
    pg_temp.v('الكأس تمتد إلى الشهر التالي') like 'نعم%',
    'the cup runs into December');
  perform pg_temp.check(
    pg_temp.v('الشهر التالي مسحوب') = 'لا' and pg_temp.s('الشهر التالي مسحوب') = 'معلومة',
    'December not drawn, and not due before the 1st');
  perform pg_temp.check(
    pg_temp.v('المسابقة الشهرية') = '11/2099', 'the monthly contest is found');
  perform pg_temp.check(pg_temp.v('متوَّج') = 'لا', 'not crowned');
  -- 0199's own reading: the match four hours old and the nine to come
  -- are waited for, the two-day-old one is left out.
  perform pg_temp.check(
    pg_temp.v('مباريات ينتظرها التتويج') like '10 (Fresh × Wait، H1 × A1، %',
    'the four-hour-old match and the nine to come are waited for');
  perform pg_temp.check(
    pg_temp.v('مباريات تُستبعد (بلا نتيجة بعد 6 ساعات)') = '1 (Old × Late)',
    'one match left out');
  perform pg_temp.check(
    pg_temp.v('مباريات بدأت قبل ساعتين أو أكثر بلا نتيجة') = '2 (Old × Late، Fresh × Wait)'
      and pg_temp.s('مباريات بدأت قبل ساعتين أو أكثر بلا نتيجة') = 'تنبيه',
    'two results for the admin to enter');
  perform pg_temp.check(
    pg_temp.v('جائزة محددة مسبقاً') = 'لا', 'no prize set ahead');
end $$;

-- Nothing was written by the check: the seeded rows only.
do $$
begin
  perform pg_temp.check(
    (select count(*) from gamification.h2h_rounds where month_start = '2099-11-01') = 12
      and (select count(*) from gamification.h2h_cup_entries) = 0
      and (select count(*) from competition.month_champions
            where season_id = 'c2730000-0000-4000-8001-000000000010') = 0,
    'the check writes nothing');
end $$;

rollback;
