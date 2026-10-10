-- End-to-end test of the statements PostgresH2hRoundFixtureReader runs
-- (0100): a round's fixtures and the two players' picks on them. The
-- PREPARE statements below are generated from the adapter's SQL constants,
-- text for text, with @name::type turned into $n::type. Rows of a result
-- kept in a fresh temp table are read back in the order the statement
-- returned them (ctid). Rolled back at the end.
--
-- What it pins down above all: the opponent's prediction for a fixture that
-- has not kicked off never leaves the database, at the kickoff instant it
-- does, and nobody else's ever does.
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
           AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = $3::date,
         false)               AS counted,
       res.home_goals         AS home_goals,
       res.away_goals         AS away_goals
FROM list l
JOIN competition.fixture_schedules fs ON fs.fixture_id = l.fixture_id
LEFT JOIN scoring.fixture_results res ON res.fixture_id = l.fixture_id
ORDER BY fs.kickoff_at, fs.fixture_id;

-- picksSql
PREPARE rf_picks(text, uuid, uuid, timestamptz) AS

SELECT p.user_id::text            AS user_id,
       fp.fixture_id::text        AS fixture_id,
       fp.home_goals              AS home_goals,
       fp.away_goals              AS away_goals,
       fp.is_double               AS is_double,
       sc.points                  AS points,
       COALESCE(sc.exact, false)  AS exact
FROM competition.participants p
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = sf.fixture_id AND fp.participant_id = p.id
LEFT JOIN LATERAL (
  SELECT (sum(s.points) FILTER (WHERE s.grade <> 'pending'))::integer AS points,
         bool_or(s.grade = 'exact_scoreline')                        AS exact
  FROM scoring.fixture_scores s
  WHERE s.fixture_id = fp.fixture_id
    AND s.participant_id = p.id
) sc ON true
WHERE sf.fixture_id = ANY(string_to_array($1::text, ',')::uuid[])
  AND (p.user_id = $2::uuid
       OR (p.user_id = $3::uuid
           AND fs.kickoff_at <= $4::timestamptz))
ORDER BY p.user_id, fp.fixture_id, fp.submitted_at, p.id;


-- ---------------------------------------------------------------------------
-- The world: two seasons of November 2099 (r1 plays both), three players.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1020000-0000-4000-8000-000000000001', 'Monthly RF', 'football_scoreline', 'public'),
  ('c1020000-0000-4000-8000-000000000002', 'Cup RF', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z'),
  ('c1020000-0000-4000-8000-000000000020', 'c1020000-0000-4000-8000-000000000002',
   'Cup 2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');

-- Riyadh 2099-11-03: f1 15:00Z, f2 18:00Z, f3 hidden, f4 a test fixture.
-- Riyadh 2099-11-05: f5 18:00Z; f8 hidden; f9 not linked to any season.
-- f6: 22:30Z on the 3rd is 01:30 on the 4th in Riyadh.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1020000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-11-03 15:00Z'),
  ('c1020000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-11-03 18:00Z'),
  ('c1020000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-11-03 19:00Z'),
  ('c1020000-0000-4000-8000-0000000000f5', 'I', 'J', '2099-11-05 18:00Z'),
  ('c1020000-0000-4000-8000-0000000000f6', 'K', 'L', '2099-11-03 22:30Z'),
  ('c1020000-0000-4000-8000-0000000000f8', 'O', 'P', '2099-11-05 12:00Z'),
  ('c1020000-0000-4000-8000-0000000000f9', 'Q', 'R', '2099-11-05 13:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c1020000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-11-03 20:00Z', true);
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f1', 0),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f2', 1),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f3', 2),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f4', 3),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f5', 4),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f6', 5),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f8', 6),
  ('c1020000-0000-4000-8000-000000000020', 'c1020000-0000-4000-8000-0000000000f1', 0);
update competition.fixture_schedules set hidden_at = now()
 where fixture_id in ('c1020000-0000-4000-8000-0000000000f3',
                      'c1020000-0000-4000-8000-0000000000f8');

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0102-4000-8102-000000000001', 'r1@t.io', now()),
  ('00000000-0102-4000-8102-000000000002', 'r2@t.io', now()),
  ('00000000-0102-4000-8102-000000000003', 'r3@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0102-4000-8102-000000000001', 'r1@t.io', 'R One'),
  ('00000000-0102-4000-8102-000000000002', 'r2@t.io', 'R Two'),
  ('00000000-0102-4000-8102-000000000003', 'r3@t.io', 'R Three');

insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1020000-0000-4000-8000-0000000000a1', 'c1020000-0000-4000-8000-000000000010', '00000000-0102-4000-8102-000000000001', '2099-11-01'),
  ('c1020000-0000-4000-8000-0000000000b1', 'c1020000-0000-4000-8000-000000000020', '00000000-0102-4000-8102-000000000001', '2099-11-01'),
  ('c1020000-0000-4000-8000-0000000000a2', 'c1020000-0000-4000-8000-000000000010', '00000000-0102-4000-8102-000000000002', '2099-11-01'),
  ('c1020000-0000-4000-8000-0000000000a3', 'c1020000-0000-4000-8000-000000000010', '00000000-0102-4000-8102-000000000003', '2099-11-01');

-- r1 (the reader): f1 in both seasons, f2, f5. r2 (the opponent): f1, f2
-- doubled, f5. r3 (neither): f1, f2.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c1020000-0000-4000-8000-00000000c011', 'c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a1', 2, 1, true,  '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c111', 'c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000b1', 0, 0, false, '2099-11-02 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c012', 'c1020000-0000-4000-8000-0000000000f2', 'c1020000-0000-4000-8000-0000000000a1', 1, 1, false, '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c015', 'c1020000-0000-4000-8000-0000000000f5', 'c1020000-0000-4000-8000-0000000000a1', 3, 0, false, '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c021', 'c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a2', 1, 0, false, '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c022', 'c1020000-0000-4000-8000-0000000000f2', 'c1020000-0000-4000-8000-0000000000a2', 2, 2, true,  '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c025', 'c1020000-0000-4000-8000-0000000000f5', 'c1020000-0000-4000-8000-0000000000a2', 1, 1, false, '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c031', 'c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a3', 0, 0, false, '2099-11-01 10:00Z'),
  ('c1020000-0000-4000-8000-00000000c032', 'c1020000-0000-4000-8000-0000000000f2', 'c1020000-0000-4000-8000-0000000000a3', 0, 1, false, '2099-11-01 10:00Z');

-- f1 ends 2-1 and is scored; f2 has only pending scores.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1020000-0000-4000-8000-0000000000f1', 2, 1, '2099-11-03 17:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 6),
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000b1', 1, 'correct_outcome', 1),
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a2', 1, 'correct_outcome', 1),
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a3', 1, 'incorrect', 0),
  ('c1020000-0000-4000-8000-0000000000f2', 'c1020000-0000-4000-8000-0000000000a1', 1, 'pending', 0);

-- Round 1 (the 3rd) is locked with f1 and f2, as the lock would freeze
-- them; then f2 moves to the 4th. Round 2 (the 5th) is not locked.
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count) values
  ('c1020000-0000-4000-8000-0000000000d1', '2099-11-01', 1, '2099-11-03', 2),
  ('c1020000-0000-4000-8000-0000000000d2', '2099-11-01', 2, '2099-11-05', 1);
insert into gamification.h2h_round_fixtures (round_id, fixture_id) values
  ('c1020000-0000-4000-8000-0000000000d1', 'c1020000-0000-4000-8000-0000000000f1'),
  ('c1020000-0000-4000-8000-0000000000d1', 'c1020000-0000-4000-8000-0000000000f2');
insert into gamification.h2h_round_locks (round_id, fixture_count) values
  ('c1020000-0000-4000-8000-0000000000d1', 2);
update competition.fixture_schedules set kickoff_at = '2099-11-04 18:00Z'
 where fixture_id = 'c1020000-0000-4000-8000-0000000000f2';

-- ---------------------------------------------------------------------------
-- The fixtures
-- ---------------------------------------------------------------------------
create temp table r1_fixtures as execute rf_fixtures(true, 'c1020000-0000-4000-8000-0000000000d1', '2099-11-03');
create temp table r2_fixtures as execute rf_fixtures(false, 'c1020000-0000-4000-8000-0000000000d2', '2099-11-05');
do $$
begin
  perform pg_temp.check(
    (select array_agg(fixture_id || ':' || counted order by ctid) from r1_fixtures)
      = array['c1020000-0000-4000-8000-0000000000f1:true',
              'c1020000-0000-4000-8000-0000000000f2:false'],
    'a locked round reads its frozen list; the moved fixture counts no more');
  perform pg_temp.check(
    (select home_team = 'A' and away_team = 'B' and home_goals = 2
        and away_goals = 1 and kickoff_at = '2099-11-03 15:00Z'::timestamptz
       from r1_fixtures
      where fixture_id = 'c1020000-0000-4000-8000-0000000000f1'),
    'a fixture carries its teams, kickoff and result');
  perform pg_temp.check(
    (select home_goals is null from r1_fixtures
      where fixture_id = 'c1020000-0000-4000-8000-0000000000f2'),
    'no result yet reads as null');
  perform pg_temp.check(
    (select array_agg(fixture_id || ':' || counted order by ctid) from r2_fixtures)
      = array['c1020000-0000-4000-8000-0000000000f5:true'],
    'an unlocked round reads its day: visible, real, season fixtures only');
end $$;

-- ---------------------------------------------------------------------------
-- The picks, and the secret
-- ---------------------------------------------------------------------------
-- 14:59:59 on the 3rd: nothing of r2 has kicked off.
create temp table p_before as execute rf_picks(
  'c1020000-0000-4000-8000-0000000000f1,c1020000-0000-4000-8000-0000000000f2',
  '00000000-0102-4000-8102-000000000001', '00000000-0102-4000-8102-000000000002',
  '2099-11-03 14:59:59Z');
-- 15:00 sharp: f1 has kicked off; f2 (moved to the 4th) has not.
create temp table p_at as execute rf_picks(
  'c1020000-0000-4000-8000-0000000000f1,c1020000-0000-4000-8000-0000000000f2',
  '00000000-0102-4000-8102-000000000001', '00000000-0102-4000-8102-000000000002',
  '2099-11-03 15:00Z');
-- The 4th at 18:00: both have kicked off.
create temp table p_after as execute rf_picks(
  'c1020000-0000-4000-8000-0000000000f1,c1020000-0000-4000-8000-0000000000f2',
  '00000000-0102-4000-8102-000000000001', '00000000-0102-4000-8102-000000000002',
  '2099-11-04 18:00Z');
-- No opponent: the group average.
create temp table p_alone as execute rf_picks(
  'c1020000-0000-4000-8000-0000000000f1,c1020000-0000-4000-8000-0000000000f2',
  '00000000-0102-4000-8102-000000000001', null, '2099-11-30 00:00Z');
-- Round 2, the day before: r2's f5 stays in the database.
create temp table p_open as execute rf_picks(
  'c1020000-0000-4000-8000-0000000000f5',
  '00000000-0102-4000-8102-000000000001', '00000000-0102-4000-8102-000000000002',
  '2099-11-04 12:00Z');
do $$
begin
  perform pg_temp.check(
    not exists (select 1 from p_before
                 where user_id = '00000000-0102-4000-8102-000000000002'),
    'before any kickoff the opponent has no row at all');
  perform pg_temp.check(
    (select count(*) from p_before
      where user_id = '00000000-0102-4000-8102-000000000001') = 3,
    'the reader always reads their own picks (f1 twice, f2)');
  perform pg_temp.check(
    (select array_agg(fixture_id order by ctid) from p_at
      where user_id = '00000000-0102-4000-8102-000000000002')
      = array['c1020000-0000-4000-8000-0000000000f1'],
    'at the kickoff instant the opponent''s pick on that fixture is read, and '
    'only on that one');
  perform pg_temp.check(
    (select array_agg(fixture_id || ':' || is_double order by ctid) from p_after
      where user_id = '00000000-0102-4000-8102-000000000002')
      = array['c1020000-0000-4000-8000-0000000000f1:false',
              'c1020000-0000-4000-8000-0000000000f2:true'],
    'once both kicked off, both of the opponent''s picks are read');
  perform pg_temp.check(
    not exists (select 1 from p_after
                 where user_id = '00000000-0102-4000-8102-000000000003')
      and not exists (select 1 from p_alone
                       where user_id <> '00000000-0102-4000-8102-000000000001'),
    'nobody else''s pick is ever read; with no opponent, only the reader''s');
  perform pg_temp.check(
    not exists (select 1 from p_open
                 where user_id = '00000000-0102-4000-8102-000000000002')
      and (select home_goals = 3 from p_open),
    'an open round shows the reader''s pick and none of the opponent''s');
  perform pg_temp.check(
    (select array_agg(home_goals || '-' || away_goals || ':' || points || ':'
                      || exact order by ctid) from p_after
      where user_id = '00000000-0102-4000-8102-000000000001'
        and fixture_id = 'c1020000-0000-4000-8000-0000000000f1')
      = array['2-1:6:true', '0-0:1:false'],
    'one row per participation, the first submitted first, with its points');
  perform pg_temp.check(
    (select points is null and not exact from p_after
      where user_id = '00000000-0102-4000-8102-000000000001'
        and fixture_id = 'c1020000-0000-4000-8000-0000000000f2'),
    'only pending scores read as no points yet');
end $$;

rollback;
