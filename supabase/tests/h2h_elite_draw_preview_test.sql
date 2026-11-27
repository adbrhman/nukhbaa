-- The read-only preview of the elite draw (NK182, NK352D):
-- supabase/queries/h2h_elite_draw_preview.sql, run as it is (its comments
-- stripped, its month moved to November 2099 so the seeded predictions come
-- before their kickoffs) over a seeded month: 221 eligible players, two
-- with too few days, one suspended and one hidden. It must order like
-- PostgresH2hDrawSource.activeOrderSql (fewest missed, then points, then
-- right outcomes) and deal like H2hLeaguePolicy.eliteDraw. A 2099 month is
-- drawn by the December rules: ten even groups of twenty, then extra groups
-- from group 11, the last one a waiting group of one. The same file run again
-- with its December date moved to 2100 is drawn by the November rules: four
-- elite groups, then twenty a group, a last single player joining the group
-- before him. The expected places were dealt by a port of eliteDraw.
-- Rolled back.
\set ON_ERROR_STOP on
\set preview `sed -e 's/--.*$//' -e "s/date '2026-11-01'/date '2099-11-01'/" supabase/queries/h2h_elite_draw_preview.sql | tr '\n' ' ' | sed -e 's/; *$//'`
\set preview_nov `sed -e 's/--.*$//' -e "s/date '2026-11-01'/date '2099-11-01'/" -e "s/date '2026-12-01'/date '2100-01-01'/" supabase/queries/h2h_elite_draw_preview.sql | tr '\n' ' ' | sed -e 's/; *$//'`
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
  ('c1900000-0000-4000-8000-000000000001', 'Monthly NK352D', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1900000-0000-4000-8000-000000000010', 'c1900000-0000-4000-8000-000000000001',
   'November 2099 NK352D', '2099-10-31 21:00Z', '2099-11-30 21:00Z');

-- 30 fixtures, three a day (12:00, 15:00, 18:00 UTC) on November 1..10.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
select pg_temp.nk('fixture', n), 'H' || n, 'A' || n,
       timestamptz '2099-11-01 12:00Z'
         + ((n - 1) / 3) * interval '1 day'
         + ((n - 1) % 3) * interval '3 hours'
from generate_series(1, 30) n;
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c1900000-0000-4000-8000-000000000010', pg_temp.nk('fixture', n), n
from generate_series(1, 30) n;

-- Players 1..221 miss (i - 1) / 20 matches (0..11) and score (i * 7) % 11;
-- 222 and 223 predict on two days only; 224 is suspended; 225 is hidden.
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.nk('user', i), 'e' || i || '@nk352d.io', now()
from generate_series(1, 225) i;
insert into identity.users (id, email, display_name)
select pg_temp.nk('user', i), 'e' || i || '@nk352d.io', 'E' || i
from generate_series(1, 225) i;
update identity.users set status = 'suspended' where id = pg_temp.nk('user', 224);
update identity.users set hidden_at = now() where id = pg_temp.nk('user', 225);
insert into competition.participants (id, season_id, user_id, joined_at)
select pg_temp.nk('participant', i), 'c1900000-0000-4000-8000-000000000010',
       pg_temp.nk('user', i), '2099-10-30'
from generate_series(1, 225) i;

insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), pg_temp.nk('fixture', n), pg_temp.nk('participant', i),
       1, 0, false, '2099-10-30 12:00Z'
from generate_series(1, 225) i
cross join lateral generate_series(
  1,
  case when i <= 221 then 30 - (i - 1) / 20
       when i <= 223 then 6
       else 30 end) n;

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
select pg_temp.nk('fixture', n), 1, 0,
       timestamptz '2099-11-01 14:00Z'
         + ((n - 1) / 3) * interval '1 day'
         + ((n - 1) % 3) * interval '3 hours'
from generate_series(1, 30) n;
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points)
select pg_temp.nk('fixture', 1), pg_temp.nk('participant', i), 1, 'correct_outcome',
       case when i <= 221 then (i * 7) % 11 when i <= 223 then 50 else 99 end
from generate_series(1, 225) i;
-- Players 1 and 12 both miss none and score 7; player 12 also has a second
-- right outcome (worth no points), so he is placed before player 1.
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points)
values (pg_temp.nk('fixture', 2), pg_temp.nk('participant', 12), 1, 'correct_outcome', 0);

create temp table preview_out as :preview;
create temp table preview_nov_out as :preview_nov;

-- December rules (a 2099 month): ten even groups, group 11 of twenty, and the
-- last single player alone in the waiting group 12.
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id || ':' || "group" order by place)
       from preview_out where eligible and place <= 24)
      = array['00000000-0190-4000-8190-000000000003:1',
         '00000000-0190-4000-8190-000000000014:2',
         '00000000-0190-4000-8190-000000000006:3',
         '00000000-0190-4000-8190-000000000017:4',
         '00000000-0190-4000-8190-000000000009:5',
         '00000000-0190-4000-8190-000000000020:6',
         '00000000-0190-4000-8190-000000000012:7',
         '00000000-0190-4000-8190-000000000001:8',
         '00000000-0190-4000-8190-000000000004:9',
         '00000000-0190-4000-8190-000000000015:10',
         '00000000-0190-4000-8190-000000000007:10',
         '00000000-0190-4000-8190-000000000018:9',
         '00000000-0190-4000-8190-000000000010:8',
         '00000000-0190-4000-8190-000000000002:7',
         '00000000-0190-4000-8190-000000000013:6',
         '00000000-0190-4000-8190-000000000005:5',
         '00000000-0190-4000-8190-000000000016:4',
         '00000000-0190-4000-8190-000000000008:3',
         '00000000-0190-4000-8190-000000000019:2',
         '00000000-0190-4000-8190-000000000011:1',
         '00000000-0190-4000-8190-000000000025:1',
         '00000000-0190-4000-8190-000000000036:2',
         '00000000-0190-4000-8190-000000000028:3',
         '00000000-0190-4000-8190-000000000039:4'],
    'December: every eligible player in the order and group of eliteDraw (first 24 places)');
  perform pg_temp.check(
    (select array_agg(n order by g) from (
       select "group" as g, count(*) as n from preview_out
        where eligible group by 1) s) = array[20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 1]::bigint[],
    'December: ten elite groups of 20, group 11 of 20, the 221st alone in group 12');
  perform pg_temp.check(
    (select array_agg(place::int order by place) from preview_out
      where "group" = 2) = array[2, 19, 22, 39, 42, 59, 62, 79, 82, 99, 102, 119, 122, 139, 142, 159, 162, 179, 182, 199],
    'December: group 2 by the snake over ten groups');
  perform pg_temp.check(
    (select place from preview_out where user_id = pg_temp.nk('user', 12)) = 7
    and (select place from preview_out where user_id = pg_temp.nk('user', 1)) = 8,
    'December: equal points, the more right outcomes first (player 12 before 1)');
  perform pg_temp.check(
    (select bool_and(not eligible and "group" is null and place is null
                     and days = 2)
       from preview_out
      where user_id in (pg_temp.nk('user', 222), pg_temp.nk('user', 223))),
    'too few days: listed, not drawn');
  perform pg_temp.check(
    not exists (select 1 from preview_out
                 where user_id in (pg_temp.nk('user', 224), pg_temp.nk('user', 225))),
    'the suspended and the hidden are left out');
  perform pg_temp.check(
    (select fixtures = 30 and predicted = 28 and missed = 2 and days = 10
            and outcomes = 1 and exact = 0
       from preview_out where user_id = pg_temp.nk('user', 51)),
    'the facts: fixtures, predicted, missed, days, outcomes and exact');
  perform pg_temp.check(
    (select outcomes = 2 from preview_out where user_id = pg_temp.nk('user', 12)),
    'the facts: right outcomes counted over every fixture of the month');
  perform pg_temp.check(
    (select bool_and(group_size = 20) from preview_out
      where eligible and "group" <= 11),
    'each full group row carries its group size');
end $$;

-- November rules (the December date moved to 2100): four elite groups of 20,
-- six extra groups of twenty, the single 221st player joining the last one.
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id || ':' || "group" order by place)
       from preview_nov_out where eligible and place <= 24)
      = array['00000000-0190-4000-8190-000000000003:1',
         '00000000-0190-4000-8190-000000000014:2',
         '00000000-0190-4000-8190-000000000006:3',
         '00000000-0190-4000-8190-000000000017:4',
         '00000000-0190-4000-8190-000000000009:4',
         '00000000-0190-4000-8190-000000000020:3',
         '00000000-0190-4000-8190-000000000012:2',
         '00000000-0190-4000-8190-000000000001:1',
         '00000000-0190-4000-8190-000000000004:1',
         '00000000-0190-4000-8190-000000000015:2',
         '00000000-0190-4000-8190-000000000007:3',
         '00000000-0190-4000-8190-000000000018:4',
         '00000000-0190-4000-8190-000000000010:4',
         '00000000-0190-4000-8190-000000000002:3',
         '00000000-0190-4000-8190-000000000013:2',
         '00000000-0190-4000-8190-000000000005:1',
         '00000000-0190-4000-8190-000000000016:1',
         '00000000-0190-4000-8190-000000000008:2',
         '00000000-0190-4000-8190-000000000019:3',
         '00000000-0190-4000-8190-000000000011:4',
         '00000000-0190-4000-8190-000000000025:4',
         '00000000-0190-4000-8190-000000000036:3',
         '00000000-0190-4000-8190-000000000028:2',
         '00000000-0190-4000-8190-000000000039:1'],
    'November: the snake over four groups (first 24 places)');
  perform pg_temp.check(
    (select array_agg(n order by g) from (
       select "group" as g, count(*) as n from preview_nov_out
        where eligible group by 1) s) = array[20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 21]::bigint[],
    'November: four elite groups of 20, six extra groups, the last single joins group 11 (21)');
  perform pg_temp.check(
    (select array_agg(place::int order by place) from preview_nov_out
      where "group" = 2) = array[2, 7, 10, 15, 18, 23, 26, 31, 34, 39, 42, 47, 50, 55, 58, 63, 66, 71, 74, 79],
    'November: group 2 by the snake over four groups');
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
         count(*) FILTER (WHERE s.grade = 'correct_outcome')  AS outcomes,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')  AS exact
  FROM competition.participants p
  JOIN identity.users u ON u.id = p.user_id AND u.status <> 'suspended' AND u.hidden_at IS NULL
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
ORDER BY missed ASC, points DESC, outcomes DESC, exact DESC, user_id;

create temp table active_out as execute nk_active_order('2099-11-01', 5);
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from active_out)
      = (select array_agg(user_id::text order by place)
           from preview_out where eligible),
    'the preview orders exactly like the draw itself');
  perform pg_temp.check(
    (select array_agg(user_id::text order by place)
       from preview_nov_out where eligible)
      = (select array_agg(user_id::text order by place)
           from preview_out where eligible),
    'both rule sets order the same players the same way');
end $$;

rollback;
