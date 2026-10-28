-- End-to-end test of the head-to-head result deadline (script 163,
-- 2026-10-28): a fixture of a locked round whose result was not recorded by
-- the end of the Riyadh day AFTER the round's day is void for both sides,
-- so a match postponed without a new date (Al-Nassr - Al-Wasl, round 18 of
-- October 2026) no longer holds its round live for ever. The PREPARE
-- statements are the adapters' SQL constants (PostgresH2hSheetReader,
-- PostgresH2hRoundFixtureReader, PostgresH2hRoundStore), text for text,
-- with @name::type turned into $n::type, as in 0100_h2h_queries_test.sql.
-- The world lies in January 2020, long past every deadline; the November
-- 2099 world of 0100_h2h_queries_test.sql covers a round still waiting.
-- Rolled back at the end.
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

-- insertMonthSql
PREPARE league_insert_month(date, boolean, integer) AS

INSERT INTO gamification.h2h_months (month_start, is_pilot, seated_count)
VALUES ($1::date, $2::boolean, $3::integer)
ON CONFLICT (month_start) DO NOTHING
RETURNING 1 AS inserted;

-- insertGroupSql
PREPARE league_insert_group(uuid, date, smallint, smallint, smallint) AS

INSERT INTO gamification.h2h_leagues
  (id, month_start, division, group_index, capacity)
VALUES ($1::uuid, $2::date, $3::smallint,
        $4::smallint, $5::smallint);

-- insertSeatSql
PREPARE league_insert_seat(uuid, date, uuid, smallint) AS

INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES ($1::uuid, $2::date, $3::uuid, $4::smallint);

-- approveSql
PREPARE round_approve(uuid, date, smallint, date, smallint, uuid) AS

INSERT INTO gamification.h2h_rounds
  (id, month_start, round_no, day, fixture_count, approved_by)
VALUES ($1::uuid, $2::date, $3::smallint, $4::date,
        $5::smallint, $6::uuid);

-- freezeFixturesSql
PREPARE round_freeze_fixtures(uuid, date) AS

INSERT INTO gamification.h2h_round_fixtures (round_id, fixture_id)
SELECT DISTINCT $1::uuid, fs.fixture_id
FROM competition.fixture_schedules fs
WHERE fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND EXISTS (
    SELECT 1 FROM competition.season_fixtures sf
    WHERE sf.fixture_id = fs.fixture_id
  )
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $2::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_round_locks k
    WHERE k.round_id = $1::uuid
  )
ON CONFLICT (round_id, fixture_id) DO NOTHING;

-- lockSql
PREPARE round_lock(uuid) AS

INSERT INTO gamification.h2h_round_locks (round_id, fixture_count)
SELECT $1::uuid, count(*)::smallint
FROM gamification.h2h_round_fixtures
WHERE round_id = $1::uuid
ON CONFLICT (round_id) DO NOTHING;

-- scoresSql
PREPARE sheet_scores(uuid) AS

WITH members AS (
  SELECT m.user_id
  FROM gamification.h2h_league_members m
  JOIN identity.users u ON u.id = m.user_id AND u.status <> 'suspended'
  WHERE m.league_id = $1::uuid
),
rounds AS (
  SELECT r.id, r.round_no, r.day
  FROM gamification.h2h_leagues l
  JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE l.id = $1::uuid
),
valid AS (
  SELECT rd.round_no, rf.fixture_id
  FROM rounds rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
    AND (rr.created_at < ((rd.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((rd.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
)
SELECT mb.user_id::text                                     AS user_id,
       v.round_no                                           AS round_no,
       COALESCE(sum(s.points), 0)::integer                  AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer        AS exact_count,
       count(fp.id)::integer                                AS predicted_count
FROM members mb
JOIN competition.participants p ON p.user_id = mb.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN valid v ON v.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = v.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = v.fixture_id AND s.participant_id = p.id
GROUP BY mb.user_id, v.round_no
HAVING count(fp.id) > 0
ORDER BY v.round_no, mb.user_id;

-- roundStatusSql
PREPARE sheet_round_status(uuid) AS

WITH rounds AS (
  SELECT r.id, r.round_no, r.day
  FROM gamification.h2h_leagues l
  JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE l.id = $1::uuid
),
valid AS (
  SELECT rd.round_no, rf.fixture_id, fs.kickoff_at
  FROM rounds rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
    AND (rr.created_at < ((rd.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((rd.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
)
SELECT rd.round_no                      AS round_no,
       count(v.fixture_id)::integer     AS fixtures,
       count(v.fixture_id) FILTER (
         WHERE res.fixture_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM scoring.fixture_scores sp
             WHERE sp.fixture_id = v.fixture_id
               AND sp.grade = 'pending'
           ))::integer                  AS settled,
       max(v.kickoff_at)                AS last_kickoff
FROM rounds rd
LEFT JOIN valid v ON v.round_no = rd.round_no
LEFT JOIN scoring.fixture_results res ON res.fixture_id = v.fixture_id
GROUP BY rd.round_no
ORDER BY rd.round_no;

-- fixturesSql
PREPARE rf_fixtures(boolean, uuid, date) AS

WITH list AS (
  SELECT rf.fixture_id
  FROM gamification.h2h_round_fixtures rf
  WHERE $1::boolean
    AND rf.round_id = $2::uuid
  UNION
  SELECT fs.fixture_id
  FROM competition.fixture_schedules fs
  WHERE NOT $1::boolean
    AND fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND EXISTS (
      SELECT 1 FROM competition.season_fixtures sf
      WHERE sf.fixture_id = fs.fixture_id
    )
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $3::date
)
SELECT fs.fixture_id::text    AS fixture_id,
       fs.home_team           AS home_team,
       fs.away_team           AS away_team,
       fs.home_team_id::text  AS home_team_id,
       fs.away_team_id::text  AS away_team_id,
       fs.kickoff_at          AS kickoff_at,
       COALESCE(
         fs.hidden_at IS NULL
           AND NOT fs.is_test
           AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $3::date
           AND (res.created_at
                  < (($3::date + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
                OR now()
                  < (($3::date + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')),
         false)               AS counted,
       res.home_goals         AS home_goals,
       res.away_goals         AS away_goals
FROM list l
JOIN competition.fixture_schedules fs ON fs.fixture_id = l.fixture_id
LEFT JOIN scoring.fixture_results res ON res.fixture_id = l.fixture_id
ORDER BY fs.kickoff_at, fs.fixture_id;

-- ---------------------------------------------------------------------------
-- The world: a monthly season of January 2020 and two players.
-- Round 1, Riyadh 2020-01-14 (deadline 2020-01-16 00:00 Riyadh, 2020-01-15
-- 21:00Z): g1 scored the same night; g2 postponed, never scored; g3 scored
-- only on the 17th, after the deadline. Round 2, 2020-01-20: its only
-- fixture g4 postponed, never scored.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1630000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1630000-0000-4000-8000-000000000010', 'c1630000-0000-4000-8000-000000000001',
   '1/2020', '2019-12-31 21:00Z', '2020-01-31 21:00Z');
-- Scheduled in the future first, so the kickoff lock lets the predictions
-- in; moved to their January 2020 kickoffs below.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1630000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-01-14 15:00Z'),
  ('c1630000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-01-14 16:00Z'),
  ('c1630000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-01-14 18:00Z'),
  ('c1630000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-01-20 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1630000-0000-4000-8000-000000000010', 'c1630000-0000-4000-8000-0000000000f1', 0),
  ('c1630000-0000-4000-8000-000000000010', 'c1630000-0000-4000-8000-0000000000f2', 1),
  ('c1630000-0000-4000-8000-000000000010', 'c1630000-0000-4000-8000-0000000000f3', 2),
  ('c1630000-0000-4000-8000-000000000010', 'c1630000-0000-4000-8000-0000000000f4', 3);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0163-4000-8163-000000000001', 'd1@t.io', now()),
  ('00000000-0163-4000-8163-000000000002', 'd2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0163-4000-8163-000000000001', 'd1@t.io', 'D One'),
  ('00000000-0163-4000-8163-000000000002', 'd2@t.io', 'D Two');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1630000-0000-4000-8000-0000000000a1', 'c1630000-0000-4000-8000-000000000010', '00000000-0163-4000-8163-000000000001', '2020-01-01'),
  ('c1630000-0000-4000-8000-0000000000a2', 'c1630000-0000-4000-8000-000000000010', '00000000-0163-4000-8163-000000000002', '2020-01-01');

-- d1 calls g1 and g3 exactly; d2 misses g1 and calls g2.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c1630000-0000-4000-8000-00000000b011', 'c1630000-0000-4000-8000-0000000000f1', 'c1630000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('c1630000-0000-4000-8000-00000000b013', 'c1630000-0000-4000-8000-0000000000f3', 'c1630000-0000-4000-8000-0000000000a1', 2, 1, false, now()),
  ('c1630000-0000-4000-8000-00000000b021', 'c1630000-0000-4000-8000-0000000000f1', 'c1630000-0000-4000-8000-0000000000a2', 0, 0, false, now()),
  ('c1630000-0000-4000-8000-00000000b022', 'c1630000-0000-4000-8000-0000000000f2', 'c1630000-0000-4000-8000-0000000000a2', 1, 1, false, now()),
  ('c1630000-0000-4000-8000-00000000b024', 'c1630000-0000-4000-8000-0000000000f4', 'c1630000-0000-4000-8000-0000000000a2', 1, 1, false, now());

update competition.fixture_schedules
   set kickoff_at = kickoff_at - interval '79 years'
 where fixture_id::text like 'c1630000-%';

execute league_insert_month('2020-01-01', false, 2);
execute league_insert_group('c1630000-0000-4000-8000-0000000000e1', '2020-01-01', 1, 0, 2);
execute league_insert_seat('c1630000-0000-4000-8000-0000000000e1', '2020-01-01', '00000000-0163-4000-8163-000000000001', 0);
execute league_insert_seat('c1630000-0000-4000-8000-0000000000e1', '2020-01-01', '00000000-0163-4000-8163-000000000002', 1);
execute round_approve('c1630000-0000-4000-8000-0000000000d1', '2020-01-01', 1, '2020-01-14', 3, null);
execute round_approve('c1630000-0000-4000-8000-0000000000d2', '2020-01-01', 2, '2020-01-20', 1, null);
execute round_freeze_fixtures('c1630000-0000-4000-8000-0000000000d1', '2020-01-14');
execute round_lock('c1630000-0000-4000-8000-0000000000d1');
execute round_freeze_fixtures('c1630000-0000-4000-8000-0000000000d2', '2020-01-20');
execute round_lock('c1630000-0000-4000-8000-0000000000d2');

-- g1 is scored the same night; g3 two days after the deadline.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at, created_at) values
  ('c1630000-0000-4000-8000-0000000000f1', 1, 0, '2020-01-14 17:00Z', '2020-01-14 17:00Z'),
  ('c1630000-0000-4000-8000-0000000000f3', 2, 1, '2020-01-17 09:00Z', '2020-01-17 09:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1630000-0000-4000-8000-0000000000f1', 'c1630000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c1630000-0000-4000-8000-0000000000f1', 'c1630000-0000-4000-8000-0000000000a2', 1, 'incorrect', 0),
  ('c1630000-0000-4000-8000-0000000000f3', 'c1630000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3);

create temp table status_out as execute sheet_round_status('c1630000-0000-4000-8000-0000000000e1');
create temp table scores_out as execute sheet_scores('c1630000-0000-4000-8000-0000000000e1');
create temp table fixtures_out as execute rf_fixtures(true, 'c1630000-0000-4000-8000-0000000000d1', '2020-01-14');
do $$
begin
  perform pg_temp.check(
    (select array_agg(round_no || ':' || fixtures || ':' || settled
                      order by round_no) from status_out)
      = array['1:1:1', '2:0:0'],
    'past the deadline: round 1 is settled on its one scored fixture, '
    'round 2 with no fixture scored is void');
  perform pg_temp.check(
    (select last_kickoff from status_out where round_no = 1)
      = '2020-01-14 15:00Z'::timestamptz,
    'the round names its last kickoff among the fixtures that count (g1)');
  perform pg_temp.check(
    (select array_agg(user_id || ':' || round_no || ':' || points || ':'
                      || predicted_count order by user_id) from scores_out)
      = array['00000000-0163-4000-8163-000000000001:1:3:1',
              '00000000-0163-4000-8163-000000000002:1:0:1'],
    'the postponed g2 and the late g3 count for nobody: d1 keeps 3, not 6');
  perform pg_temp.check(
    (select array_agg(fixture_id || ':' || counted order by fixture_id)
       from fixtures_out)
      = array['c1630000-0000-4000-8000-0000000000f1:true',
              'c1630000-0000-4000-8000-0000000000f2:false',
              'c1630000-0000-4000-8000-0000000000f3:false'],
    'the round screen marks the postponed and the late fixture void');
  perform pg_temp.check(
    (select home_goals = 2 from fixtures_out
      where fixture_id = 'c1630000-0000-4000-8000-0000000000f3'),
    'the late result still shows; it only does not count');
end $$;

-- A correction of g1 after the deadline keeps it counted: created_at stays.
update scoring.fixture_results set home_goals = 2, recorded_at = '2020-01-20 09:00Z'
 where fixture_id = 'c1630000-0000-4000-8000-0000000000f1';
create temp table status_corrected as execute sheet_round_status('c1630000-0000-4000-8000-0000000000e1');
do $$
begin
  perform pg_temp.check(
    (select fixtures = 1 and settled = 1 from status_corrected where round_no = 1),
    'a result corrected after the deadline keeps counting');
end $$;

rollback;
