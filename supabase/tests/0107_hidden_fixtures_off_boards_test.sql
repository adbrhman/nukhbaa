-- End-to-end test for migration 0107 and the board readers of batch 125
-- (audit M-23): a hidden fixture's points leave the standings view and the
-- monthly board (PostgresFixtureTotalsReader._totalsSql, fixture list
-- inlined as an argument), come back unchanged when it is shown again, and
-- a hidden fixture without a result does not hold the crown back
-- (PostgresMonthChampionRepository._monthSql). Keep both bodies identical
-- to the adapters' constants. Rolled back at the end.
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

-- PostgresFixtureTotalsReader._totalsSql
create function pg_temp.month_totals(p_fixtures uuid[])
returns table (participant_id text, total_points bigint, fixtures_scored bigint,
               exact_count bigint, decided_count bigint)
language sql as $q$
SELECT fs.participant_id::text AS participant_id,
       sum(fs.points)::bigint AS total_points,
       count(*)::bigint AS fixtures_scored,
       count(*) FILTER (WHERE fs.grade = 'exact_scoreline')::bigint
         AS exact_count,
       count(*) FILTER (
         WHERE fs.grade IN ('exact_scoreline', 'correct_outcome', 'incorrect')
       )::bigint AS decided_count
FROM scoring.fixture_scores fs
JOIN competition.participants p
  ON p.id = fs.participant_id
-- A suspended account is off every board (0085); reinstating it
-- brings its points back unchanged.
JOIN identity.users u
  ON u.id = p.user_id
 AND u.status <> 'suspended'
WHERE fs.fixture_id = ANY(p_fixtures)
  -- A hidden fixture is off every board while it stays hidden (0107,
  -- audit M-23); a test fixture never counts.
  AND NOT EXISTS (
    SELECT 1
    FROM competition.fixture_schedules sch
    WHERE sch.fixture_id = fs.fixture_id
      AND (sch.hidden_at IS NOT NULL OR sch.is_test)
  )
GROUP BY fs.participant_id
$q$;

-- PostgresMonthChampionRepository._monthSql
create function pg_temp.crown_month(p_season uuid)
returns table (season_id text, label text, start_at timestamptz,
               end_at timestamptz, unscored bigint)
language sql as $q$
SELECT s.id::text AS season_id,
       s.label,
       s.start_at,
       s.end_at,
       (SELECT count(*)
          FROM competition.season_fixtures sf
          LEFT JOIN scoring.fixture_results r ON r.fixture_id = sf.fixture_id
         WHERE sf.season_id = s.id
           AND r.fixture_id IS NULL
           -- A test fixture never counts (0098): it is never scored. Nor
           -- does a hidden one (0107): it is off the boards, so a result
           -- it lacks must not hold the crown back.
           AND NOT EXISTS (
             SELECT 1 FROM competition.fixture_schedules t
              WHERE t.fixture_id = sf.fixture_id
                AND (t.is_test OR t.hidden_at IS NOT NULL)
           ))::bigint AS unscored
FROM competition.seasons s
WHERE s.id = p_season
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0107-4000-8000-000000000001', 'h1@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0107-4000-8000-000000000001', 'h1@t.io', 'Hidden One');
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0107-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0107-4000-8000-0000000000e1', '00000000-0107-4000-8000-0000000000c1',
        '06/2099', '2099-06-01', '2099-07-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0107-4000-8000-0000000000a1', '00000000-0107-4000-8000-0000000000e1',
   '00000000-0107-4000-8000-000000000001', '2099-06-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('00000000-0107-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2099-06-10 18:00+03'),
  ('00000000-0107-4000-8000-0000000000f2', 'Ahli', 'Ittihad', '2099-06-11 18:00+03'),
  ('00000000-0107-4000-8000-0000000000f3', 'Fateh', 'Taawoun', '2099-06-12 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('00000000-0107-4000-8000-0000000000e1', '00000000-0107-4000-8000-0000000000f1', 0),
  ('00000000-0107-4000-8000-0000000000e1', '00000000-0107-4000-8000-0000000000f2', 1),
  ('00000000-0107-4000-8000-0000000000e1', '00000000-0107-4000-8000-0000000000f3', 2);
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
select f, 1, 0, now() from unnest(array['00000000-0107-4000-8000-0000000000f1',
                                 '00000000-0107-4000-8000-0000000000f2']::uuid[]) f;
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('00000000-0107-4000-8000-0000000000f1', '00000000-0107-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('00000000-0107-4000-8000-0000000000f2', '00000000-0107-4000-8000-0000000000a1', 1, 'exact_scoreline', 6);

do $$
declare
  season uuid := '00000000-0107-4000-8000-0000000000e1';
  p uuid := '00000000-0107-4000-8000-0000000000a1';
  fixtures uuid[] := array['00000000-0107-4000-8000-0000000000f1',
                           '00000000-0107-4000-8000-0000000000f2',
                           '00000000-0107-4000-8000-0000000000f3']::uuid[];
begin
  perform pg_temp.check(
    (select total_points from leaderboard.season_fixture_standings where participant_id = p) = 9
    and (select total_points from pg_temp.month_totals(fixtures)) = 9,
    'both fixtures count while visible');
  perform pg_temp.check(
    (select unscored from pg_temp.crown_month(season)) = 1,
    'a visible fixture without a result holds the crown back');

  update competition.fixture_schedules set hidden_at = now()
   where fixture_id in ('00000000-0107-4000-8000-0000000000f2',
                        '00000000-0107-4000-8000-0000000000f3');

  perform pg_temp.check(
    (select total_points from leaderboard.season_fixture_standings where participant_id = p) = 3
    and (select fixtures_scored from leaderboard.season_fixture_standings where participant_id = p) = 1,
    'a hidden fixture leaves the standings view');
  perform pg_temp.check(
    (select total_points from pg_temp.month_totals(fixtures)) = 3,
    'a hidden fixture leaves the monthly board');
  perform pg_temp.check(
    (select unscored from pg_temp.crown_month(season)) = 0,
    'a hidden fixture without a result does not hold the crown back');

  update competition.fixture_schedules set hidden_at = null
   where fixture_id = '00000000-0107-4000-8000-0000000000f2';

  perform pg_temp.check(
    (select total_points from leaderboard.season_fixture_standings where participant_id = p) = 9
    and (select total_points from pg_temp.month_totals(fixtures)) = 9,
    'shown again, its points come back unchanged');
end $$;

rollback;
