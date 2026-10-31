-- The read-only preview of the elite draw (NK182):
-- supabase/queries/h2h_elite_draw_preview.sql, run as it is (its comments
-- stripped, its month moved to October 2099 so the seeded predictions come
-- before their kickoffs) over a seeded month: 101 eligible players, two
-- with too few days and one suspended. It must order like
-- PostgresH2hDrawSource.activeOrderSql (fewest missed, then points) and
-- deal like H2hLeaguePolicy.eliteDraw (a snake into groups 1..4, then
-- twenty a group, a last single player joining group 5). The expected
-- places were dealt by a copy of eliteDraw. Rolled back.
\set ON_ERROR_STOP on
\set preview `sed -e 's/--.*$//' -e "s/date '2026-10-01'/date '2099-10-01'/" supabase/queries/h2h_elite_draw_preview.sql | tr '\n' ' ' | sed -e 's/; *$//'`
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

create function pg_temp.nk(kind text, i integer) returns uuid
language sql immutable as $$
  select (case kind
            when 'user'        then '00000000-0190-4000-8190-'
            when 'participant' then 'c1900000-0000-4000-8000-'
            else                    'c1900000-0000-4000-8001-'
          end || lpad(i::text, 12, '0'))::uuid
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1900000-0000-4000-8000-000000000001', 'Monthly NK182', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1900000-0000-4000-8000-000000000010', 'c1900000-0000-4000-8000-000000000001',
   'October 2099 NK182', '2099-09-30 21:00Z', '2099-10-31 21:00Z');

-- 30 fixtures, three a day (12:00, 15:00, 18:00 UTC) on October 1..10.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
select pg_temp.nk('fixture', n), 'H' || n, 'A' || n,
       timestamptz '2099-10-01 12:00Z'
         + ((n - 1) / 3) * interval '1 day'
         + ((n - 1) % 3) * interval '3 hours'
from generate_series(1, 30) n;
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c1900000-0000-4000-8000-000000000010', pg_temp.nk('fixture', n), n
from generate_series(1, 30) n;

-- Players 1..101 miss (i - 1) / 10 matches (0..10) and score (i * 7) % 11;
-- 102 and 103 predict on two days only; 104 is suspended.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.nk('user', i), 'e' || i || '@nk182.io', now()
from generate_series(1, 104) i;
insert into identity.users (id, email, display_name)
select pg_temp.nk('user', i), 'e' || i || '@nk182.io', 'E' || i
from generate_series(1, 104) i;
update identity.users set status = 'suspended' where id = pg_temp.nk('user', 104);
insert into competition.participants (id, season_id, user_id, joined_at)
select pg_temp.nk('participant', i), 'c1900000-0000-4000-8000-000000000010',
       pg_temp.nk('user', i), '2099-09-30'
from generate_series(1, 104) i;

insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), pg_temp.nk('fixture', n), pg_temp.nk('participant', i),
       1, 0, false, '2099-09-30 12:00Z'
from generate_series(1, 104) i
cross join lateral generate_series(
  1,
  case when i <= 101 then 30 - (i - 1) / 10
       when i <= 103 then 6
       else 30 end) n;

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
select pg_temp.nk('fixture', n), 1, 0,
       timestamptz '2099-10-01 14:00Z'
         + ((n - 1) / 3) * interval '1 day'
         + ((n - 1) % 3) * interval '3 hours'
from generate_series(1, 30) n;
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points)
select pg_temp.nk('fixture', 1), pg_temp.nk('participant', i), 1, 'correct_outcome',
       case when i <= 101 then (i * 7) % 11 when i <= 103 then 50 else 99 end
from generate_series(1, 104) i;

create temp table preview_out as :preview;

do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id || ':' || "group" order by place)
       from preview_out where eligible)
      = array['00000000-0190-4000-8190-000000000003:1',
         '00000000-0190-4000-8190-000000000006:2',
         '00000000-0190-4000-8190-000000000009:3',
         '00000000-0190-4000-8190-000000000001:4',
         '00000000-0190-4000-8190-000000000004:4',
         '00000000-0190-4000-8190-000000000007:3',
         '00000000-0190-4000-8190-000000000010:2',
         '00000000-0190-4000-8190-000000000002:1',
         '00000000-0190-4000-8190-000000000005:1',
         '00000000-0190-4000-8190-000000000008:2',
         '00000000-0190-4000-8190-000000000014:3',
         '00000000-0190-4000-8190-000000000017:4',
         '00000000-0190-4000-8190-000000000020:4',
         '00000000-0190-4000-8190-000000000012:3',
         '00000000-0190-4000-8190-000000000015:2',
         '00000000-0190-4000-8190-000000000018:1',
         '00000000-0190-4000-8190-000000000013:1',
         '00000000-0190-4000-8190-000000000016:2',
         '00000000-0190-4000-8190-000000000019:3',
         '00000000-0190-4000-8190-000000000011:4',
         '00000000-0190-4000-8190-000000000025:4',
         '00000000-0190-4000-8190-000000000028:3',
         '00000000-0190-4000-8190-000000000023:2',
         '00000000-0190-4000-8190-000000000026:1',
         '00000000-0190-4000-8190-000000000029:1',
         '00000000-0190-4000-8190-000000000021:2',
         '00000000-0190-4000-8190-000000000024:3',
         '00000000-0190-4000-8190-000000000027:4',
         '00000000-0190-4000-8190-000000000030:4',
         '00000000-0190-4000-8190-000000000022:3',
         '00000000-0190-4000-8190-000000000036:2',
         '00000000-0190-4000-8190-000000000039:1',
         '00000000-0190-4000-8190-000000000031:1',
         '00000000-0190-4000-8190-000000000034:2',
         '00000000-0190-4000-8190-000000000037:3',
         '00000000-0190-4000-8190-000000000040:4',
         '00000000-0190-4000-8190-000000000032:4',
         '00000000-0190-4000-8190-000000000035:3',
         '00000000-0190-4000-8190-000000000038:2',
         '00000000-0190-4000-8190-000000000033:1',
         '00000000-0190-4000-8190-000000000047:1',
         '00000000-0190-4000-8190-000000000050:2',
         '00000000-0190-4000-8190-000000000042:3',
         '00000000-0190-4000-8190-000000000045:4',
         '00000000-0190-4000-8190-000000000048:4',
         '00000000-0190-4000-8190-000000000043:3',
         '00000000-0190-4000-8190-000000000046:2',
         '00000000-0190-4000-8190-000000000049:1',
         '00000000-0190-4000-8190-000000000041:1',
         '00000000-0190-4000-8190-000000000044:2',
         '00000000-0190-4000-8190-000000000058:3',
         '00000000-0190-4000-8190-000000000053:4',
         '00000000-0190-4000-8190-000000000056:4',
         '00000000-0190-4000-8190-000000000059:3',
         '00000000-0190-4000-8190-000000000051:2',
         '00000000-0190-4000-8190-000000000054:1',
         '00000000-0190-4000-8190-000000000057:1',
         '00000000-0190-4000-8190-000000000060:2',
         '00000000-0190-4000-8190-000000000052:3',
         '00000000-0190-4000-8190-000000000055:4',
         '00000000-0190-4000-8190-000000000069:4',
         '00000000-0190-4000-8190-000000000061:3',
         '00000000-0190-4000-8190-000000000064:2',
         '00000000-0190-4000-8190-000000000067:1',
         '00000000-0190-4000-8190-000000000070:1',
         '00000000-0190-4000-8190-000000000062:2',
         '00000000-0190-4000-8190-000000000065:3',
         '00000000-0190-4000-8190-000000000068:4',
         '00000000-0190-4000-8190-000000000063:4',
         '00000000-0190-4000-8190-000000000066:3',
         '00000000-0190-4000-8190-000000000080:2',
         '00000000-0190-4000-8190-000000000072:1',
         '00000000-0190-4000-8190-000000000075:1',
         '00000000-0190-4000-8190-000000000078:2',
         '00000000-0190-4000-8190-000000000073:3',
         '00000000-0190-4000-8190-000000000076:4',
         '00000000-0190-4000-8190-000000000079:4',
         '00000000-0190-4000-8190-000000000071:3',
         '00000000-0190-4000-8190-000000000074:2',
         '00000000-0190-4000-8190-000000000077:1',
         '00000000-0190-4000-8190-000000000083:5',
         '00000000-0190-4000-8190-000000000086:5',
         '00000000-0190-4000-8190-000000000089:5',
         '00000000-0190-4000-8190-000000000081:5',
         '00000000-0190-4000-8190-000000000084:5',
         '00000000-0190-4000-8190-000000000087:5',
         '00000000-0190-4000-8190-000000000090:5',
         '00000000-0190-4000-8190-000000000082:5',
         '00000000-0190-4000-8190-000000000085:5',
         '00000000-0190-4000-8190-000000000088:5',
         '00000000-0190-4000-8190-000000000091:5',
         '00000000-0190-4000-8190-000000000094:5',
         '00000000-0190-4000-8190-000000000097:5',
         '00000000-0190-4000-8190-000000000100:5',
         '00000000-0190-4000-8190-000000000092:5',
         '00000000-0190-4000-8190-000000000095:5',
         '00000000-0190-4000-8190-000000000098:5',
         '00000000-0190-4000-8190-000000000093:5',
         '00000000-0190-4000-8190-000000000096:5',
         '00000000-0190-4000-8190-000000000099:5',
         '00000000-0190-4000-8190-000000000101:5'],
    'every eligible player in the order and group of eliteDraw');
  perform pg_temp.check(
    (select array_agg(n order by g) from (
       select "group" as g, count(*) as n from preview_out
        where eligible group by 1) s) = array[20, 20, 20, 20, 21]::bigint[],
    'four elite groups of 20, the 101st joins group 5 (21)');
  perform pg_temp.check(
    (select array_agg(place::int order by place) from preview_out
      where "group" = 2) = array[2, 7, 10, 15, 18, 23, 26, 31, 34, 39, 42, 47, 50, 55, 58, 63, 66, 71, 74, 79],
    'group 2 by the snake: 2, 7, 10, 15, ...');
  perform pg_temp.check(
    (select bool_and(not eligible and "group" is null and place is null
                     and days = 2)
       from preview_out
      where user_id in (pg_temp.nk('user', 102), pg_temp.nk('user', 103))),
    'too few days: listed, not drawn');
  perform pg_temp.check(
    not exists (select 1 from preview_out
                 where user_id = pg_temp.nk('user', 104)),
    'the suspended are left out');
  perform pg_temp.check(
    (select fixtures = 30 and predicted = 25 and missed = 5 and days = 9
       from preview_out where user_id = pg_temp.nk('user', 51)),
    'the facts: fixtures, predicted, missed and days');
  perform pg_temp.check(
    (select bool_and(group_size = 20) from preview_out
      where eligible and "group" between 1 and 4),
    'each elite row carries its group size');
end $$;

-- The draw's own statement (PostgresH2hDrawSource.activeOrderSql, text for
-- text, @name::type turned into $n::type) must give the preview's order.
PREPARE nk_active_order(date, integer) AS

WITH fx AS (
  SELECT DISTINCT sf.season_id, fs.fixture_id,
         (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date >= $1::date
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        < ($1::date + interval '1 month')::date
),
per AS (
  SELECT p.user_id,
         count(DISTINCT fx.d) FILTER (WHERE fp.id IS NOT NULL) AS active_days,
         count(DISTINCT fx.fixture_id)
           - count(DISTINCT fx.fixture_id) FILTER (WHERE fp.id IS NOT NULL)
                                                              AS missed,
         COALESCE(sum(s.points), 0)                           AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')  AS exact
  FROM competition.participants p
  JOIN identity.users u ON u.id = p.user_id AND u.status <> 'suspended'
  JOIN fx ON fx.season_id = p.season_id
  LEFT JOIN prediction.fixture_predictions fp
    ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
  LEFT JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  GROUP BY p.user_id
)
SELECT user_id::text AS user_id
FROM per
WHERE active_days >= $2::integer
ORDER BY missed ASC, points DESC, exact DESC, user_id;

create temp table active_out as execute nk_active_order('2099-10-01', 5);
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from active_out)
      = (select array_agg(user_id::text order by place)
           from preview_out where eligible),
    'the preview orders exactly like the draw itself');
end $$;

rollback;
