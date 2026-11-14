-- Migration 0190 (the Elite Cup, NK185) and the statements its adapter
-- runs: PostgresH2hCupStore. The PREPARE statements are generated from the
-- adapter's SQL constants, text for text, with @name::type turned into
-- $n::type. Rolled back at the end.
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

-- A statement that must be refused with constraint [name] (any refusal
-- when [name] is null).
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

-- entriesSql
PREPARE cup_entries(date) AS
SELECT e.user_id::text AS user_id, e.place, e.group_number,
       e.league_points, e.points_for, e.exact_count
FROM gamification.h2h_cup_entries e
WHERE e.month_start = $1::date
ORDER BY e.place, e.group_number;

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

-- pairsSql
PREPARE cup_pairs(date) AS
SELECT p.stage_id::text AS stage_id, p.slot,
       p.home_user::text AS home_user, p.away_user::text AS away_user,
       r.outcome, r.winner_user::text AS winner_user,
       r.home_points, r.away_points, r.home_exact, r.away_exact,
       r.home_predicted, r.away_predicted
FROM gamification.h2h_cup_pairs p
JOIN gamification.h2h_cup_stages s ON s.id = p.stage_id
LEFT JOIN gamification.h2h_cup_results r
  ON r.stage_id = p.stage_id AND r.slot = p.slot
WHERE s.month_start = $1::date
ORDER BY p.stage_id, p.slot;

-- titlesSql
PREPARE cup_titles(date) AS
SELECT t.place, t.champion::text AS champion, t.runner_up::text AS runner_up,
       t.how
FROM gamification.h2h_cup_titles t
WHERE t.month_start = $1::date
ORDER BY t.place;

-- enterSql
PREPARE cup_enter(date, smallint, uuid, smallint, integer, integer, integer) AS
INSERT INTO gamification.h2h_cup_entries
  (month_start, place, user_id, group_number, league_points, points_for,
   exact_count)
VALUES ($1::date, $2::smallint, $3::uuid,
        $4::smallint, $5::integer,
        $6::integer, $7::integer)
ON CONFLICT DO NOTHING;

-- stageSql
PREPARE cup_stage(uuid, date, smallint, text, smallint, date, smallint) AS
INSERT INTO gamification.h2h_cup_stages
  (id, month_start, place, stage, attempt, day, fixture_count)
VALUES ($1::uuid, $2::date, $3::smallint, $4, $5::smallint,
        $6::date, $7::smallint);

-- pairSql
PREPARE cup_pair(uuid, smallint, uuid, uuid) AS
INSERT INTO gamification.h2h_cup_pairs (stage_id, slot, home_user, away_user)
VALUES ($1::uuid, $2::smallint, $3::uuid, $4::uuid);

-- freezeSql
PREPARE cup_freeze(uuid, date) AS
INSERT INTO gamification.h2h_cup_stage_fixtures (stage_id, fixture_id)
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
    SELECT 1 FROM gamification.h2h_cup_stage_locks k
    WHERE k.stage_id = $1::uuid
  )
ON CONFLICT (stage_id, fixture_id) DO NOTHING;

-- lockSql
PREPARE cup_lock(uuid) AS
INSERT INTO gamification.h2h_cup_stage_locks (stage_id, fixture_count)
SELECT $1::uuid, count(*)::smallint
FROM gamification.h2h_cup_stage_fixtures
WHERE stage_id = $1::uuid
ON CONFLICT (stage_id) DO NOTHING;

-- lockedCountSql
PREPARE cup_locked(uuid) AS
SELECT fixture_count
FROM gamification.h2h_cup_stage_locks
WHERE stage_id = $1::uuid;

-- countsSql
PREPARE cup_counts(uuid) AS
WITH st AS (
  SELECT s.id, s.day FROM gamification.h2h_cup_stages s
  WHERE s.id = $1::uuid
),
valid AS (
  SELECT f.fixture_id
  FROM st
  JOIN gamification.h2h_cup_stage_fixtures f ON f.stage_id = st.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = f.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = f.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = st.day
    AND (rr.created_at < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
)
SELECT count(v.fixture_id)::integer AS fixtures,
       count(v.fixture_id) FILTER (
         WHERE res.fixture_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM scoring.fixture_scores sp
             WHERE sp.fixture_id = v.fixture_id AND sp.grade = 'pending'
           ))::integer AS settled
FROM valid v
LEFT JOIN scoring.fixture_results res ON res.fixture_id = v.fixture_id;

-- sidesSql
PREPARE cup_sides(uuid) AS
WITH st AS (
  SELECT s.id, s.day FROM gamification.h2h_cup_stages s
  WHERE s.id = $1::uuid
),
valid AS (
  SELECT f.fixture_id
  FROM st
  JOIN gamification.h2h_cup_stage_fixtures f ON f.stage_id = st.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = f.fixture_id
  LEFT JOIN scoring.fixture_results rr ON rr.fixture_id = f.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = st.day
    AND (rr.created_at < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh')
         OR now() < ((st.day + 2)::timestamp AT TIME ZONE 'Asia/Riyadh'))
),
players AS (
  SELECT p.home_user AS user_id FROM gamification.h2h_cup_pairs p
  WHERE p.stage_id = $1::uuid
  UNION
  SELECT p.away_user FROM gamification.h2h_cup_pairs p
  WHERE p.stage_id = $1::uuid
)
SELECT pl.user_id::text                                    AS user_id,
       COALESCE(sum(s.points), 0)::integer                 AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer       AS exact_count,
       count(fp.id)::integer                               AS predicted_count
FROM players pl
JOIN competition.participants p ON p.user_id = pl.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN valid v ON v.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = v.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = v.fixture_id AND s.participant_id = p.id
GROUP BY pl.user_id;

-- resultSql
PREPARE cup_result(uuid, smallint, uuid, text, integer, integer, integer, integer, integer, integer) AS
INSERT INTO gamification.h2h_cup_results
  (stage_id, slot, winner_user, outcome, home_points, away_points,
   home_exact, away_exact, home_predicted, away_predicted)
VALUES ($1::uuid, $2::smallint, $3::uuid, $4,
        $5::integer, $6::integer, $7::integer,
        $8::integer, $9::integer,
        $10::integer)
ON CONFLICT DO NOTHING;

-- titleSql
PREPARE cup_title(date, smallint, uuid, uuid, text) AS
INSERT INTO gamification.h2h_cup_titles
  (month_start, place, champion, runner_up, how)
VALUES ($1::date, $2::smallint, $3::uuid, $4::uuid,
        $5)
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------------
-- The world: November 2099 drawn, 18 rounds on the 1st..18th. Four cup
-- players u1..u4. The 20th (Riyadh): f1 (15:00Z, a result), f2 (18:00Z, no
-- result yet), f3 (19:00Z, hidden after the freeze). The 21st: f4.
-- u1 predicted f1 and f2; u2 f1; u3 nothing; u4 only the hidden f3.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1900000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1900000-0000-4000-8000-000000000010', 'c1900000-0000-4000-8000-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1900000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-11-20 15:00Z'),
  ('c1900000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-11-20 18:00Z'),
  ('c1900000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-11-20 19:00Z'),
  ('c1900000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-11-21 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c1900000-0000-4000-8000-000000000010', f, n
from unnest(array['c1900000-0000-4000-8000-0000000000f1',
                  'c1900000-0000-4000-8000-0000000000f2',
                  'c1900000-0000-4000-8000-0000000000f3',
                  'c1900000-0000-4000-8000-0000000000f4']::uuid[])
     with ordinality as t(f, n);

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0190-4000-8190-00000000000' || i)::uuid, 'c' || i || '@t.io', now()
from generate_series(1, 4) i;
insert into identity.users (id, email, display_name)
select ('00000000-0190-4000-8190-00000000000' || i)::uuid, 'c' || i || '@t.io', 'C ' || i
from generate_series(1, 4) i;
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1900000-0000-4000-8000-0000000000a' || i)::uuid,
       'c1900000-0000-4000-8000-000000000010',
       ('00000000-0190-4000-8190-00000000000' || i)::uuid, '2099-11-01'
from generate_series(1, 4) i;

insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  (gen_random_uuid(), 'c1900000-0000-4000-8000-0000000000f1', 'c1900000-0000-4000-8000-0000000000a1', 2, 0, false, now()),
  (gen_random_uuid(), 'c1900000-0000-4000-8000-0000000000f2', 'c1900000-0000-4000-8000-0000000000a1', 1, 1, false, now()),
  (gen_random_uuid(), 'c1900000-0000-4000-8000-0000000000f1', 'c1900000-0000-4000-8000-0000000000a2', 1, 0, false, now()),
  (gen_random_uuid(), 'c1900000-0000-4000-8000-0000000000f3', 'c1900000-0000-4000-8000-0000000000a4', 0, 0, false, now());
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1900000-0000-4000-8000-0000000000f1', 2, 0, '2099-11-20 17:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1900000-0000-4000-8000-0000000000f1', 'c1900000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c1900000-0000-4000-8000-0000000000f1', 'c1900000-0000-4000-8000-0000000000a2', 1, 'correct_outcome', 1);

insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-11-01', false, 80);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c1900000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2099-11-01', n, ('2099-11-01'::date + (n - 1)), 6
from generate_series(1, 18) n;

-- ---------------------------------------------------------------------------
-- The order: no cup before the 19 rounds, none on or before the last round.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute cup_stage('c1900000-0000-4000-8000-0000000005a1', '2099-11-20', 1, 'semi', 1, '2099-11-20', 3)$q$,
  'h2h_cup_stages_after_league', 'no stage with 18 rounds');

insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
values ('c1900000-0000-4000-8000-000000000119', '2099-11-01', 19, '2099-11-19', 6);

select pg_temp.refused($q$execute cup_stage('c1900000-0000-4000-8000-0000000005a1', '2099-11-01', 1, 'semi', 1, '2099-11-19', 3)$q$,
  'h2h_cup_stages_after_league', 'no stage on the last round''s day');
select pg_temp.refused($q$execute cup_stage('c1900000-0000-4000-8000-0000000005a1', '2099-11-01', 4, 'semi', 1, '2099-11-20', 3)$q$,
  'h2h_cup_stages_place_range', 'a fourth path is refused');
select pg_temp.refused($q$execute cup_stage('c1900000-0000-4000-8000-0000000005a1', '2099-11-01', 1, 'quarter', 1, '2099-11-20', 3)$q$,
  'h2h_cup_stages_stage_known', 'an unknown stage is refused');

-- ---------------------------------------------------------------------------
-- The qualifiers
-- ---------------------------------------------------------------------------
execute cup_enter('2099-11-01', 1, '00000000-0190-4000-8190-000000000001', 1, 40, 120, 9);
execute cup_enter('2099-11-01', 1, '00000000-0190-4000-8190-000000000002', 2, 38, 110, 7);
execute cup_enter('2099-11-01', 1, '00000000-0190-4000-8190-000000000003', 3, 36, 100, 5);
execute cup_enter('2099-11-01', 1, '00000000-0190-4000-8190-000000000004', 4, 34, 90, 3);
-- Entered again: nothing changes.
execute cup_enter('2099-11-01', 1, '00000000-0190-4000-8190-000000000001', 1, 0, 0, 0);
select pg_temp.refused($q$execute cup_enter('2099-11-01', 2, '00000000-0190-4000-8190-000000000001', 5, 1, 1, 1)$q$,
  'h2h_cup_entries_group_range', 'group 5 is not an elite group');

create temp table entries_out as execute cup_entries('2099-11-01');
select pg_temp.check((select count(*) from entries_out) = 4, 'four qualifiers');
select pg_temp.check((select league_points from entries_out where user_id = '00000000-0190-4000-8190-000000000001') = 40,
  'an entry entered twice keeps its first figures');

-- ---------------------------------------------------------------------------
-- Path 1's semi-finals on the 20th: u1-u2 and u3-u4.
-- ---------------------------------------------------------------------------
execute cup_stage('c1900000-0000-4000-8000-0000000005a1', '2099-11-01', 1, 'semi', 1, '2099-11-20', 3);
execute cup_pair('c1900000-0000-4000-8000-0000000005a1', 1, '00000000-0190-4000-8190-000000000001', '00000000-0190-4000-8190-000000000002');
execute cup_pair('c1900000-0000-4000-8000-0000000005a1', 2, '00000000-0190-4000-8190-000000000003', '00000000-0190-4000-8190-000000000004');
select pg_temp.refused($q$execute cup_pair('c1900000-0000-4000-8000-0000000005a1', 2, '00000000-0190-4000-8190-000000000003', '00000000-0190-4000-8190-000000000003')$q$,
  'h2h_cup_pairs_two_players', 'a player is not paired with himself');
select pg_temp.refused($q$execute cup_stage('c1900000-0000-4000-8000-0000000005a2', '2099-11-01', 1, 'final', 1, '2099-11-20', 3)$q$,
  'h2h_cup_stages_in_order', 'no second stage on the same day');

-- Frozen at the first kickoff: three fixtures. Then f3 is hidden.
execute cup_freeze('c1900000-0000-4000-8000-0000000005a1', '2099-11-20');
execute cup_lock('c1900000-0000-4000-8000-0000000005a1');
create temp table locked_out as execute cup_locked('c1900000-0000-4000-8000-0000000005a1');
select pg_temp.check((select fixture_count from locked_out) = 3, 'three fixtures frozen');
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c1900000-0000-4000-8000-0000000000f3';
-- Freezing again changes nothing.
execute cup_freeze('c1900000-0000-4000-8000-0000000005a1', '2099-11-20');
execute cup_lock('c1900000-0000-4000-8000-0000000005a1');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stage_fixtures where stage_id = 'c1900000-0000-4000-8000-0000000005a1') = 3,
  'a second freeze adds nothing');

-- In play: f1 (settled) and f2 (no result yet); the hidden f3 is void.
create temp table counts_out as execute cup_counts('c1900000-0000-4000-8000-0000000005a1');
select pg_temp.check((select fixtures from counts_out) = 2, 'two fixtures in play');
select pg_temp.check((select settled from counts_out) = 1, 'one of them settled');

create temp table sides_out as execute cup_sides('c1900000-0000-4000-8000-0000000005a1');
select pg_temp.check((select points from sides_out where user_id = '00000000-0190-4000-8190-000000000001') = 3, 'u1: 3 points');
select pg_temp.check((select exact_count from sides_out where user_id = '00000000-0190-4000-8190-000000000001') = 1, 'u1: one exact');
select pg_temp.check((select predicted_count from sides_out where user_id = '00000000-0190-4000-8190-000000000001') = 2, 'u1: two predictions');
select pg_temp.check((select points from sides_out where user_id = '00000000-0190-4000-8190-000000000002') = 1, 'u2: 1 point');
select pg_temp.check(coalesce((select predicted_count from sides_out where user_id = '00000000-0190-4000-8190-000000000003'), 0) = 0,
  'u3 predicted nothing');
select pg_temp.check(coalesce((select predicted_count from sides_out where user_id = '00000000-0190-4000-8190-000000000004'), 0) = 0,
  'u4''s only prediction was on the hidden fixture');

-- f2's result: every fixture in play settled.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1900000-0000-4000-8000-0000000000f2', 1, 1, '2099-11-20 20:00Z');
create temp table counts2_out as execute cup_counts('c1900000-0000-4000-8000-0000000005a1');
select pg_temp.check((select settled from counts2_out) = 2, 'both fixtures settled');

-- ---------------------------------------------------------------------------
-- The decisions
-- ---------------------------------------------------------------------------
execute cup_result('c1900000-0000-4000-8000-0000000005a1', 1, '00000000-0190-4000-8190-000000000001', 'points', 3, 1, 1, 0, 2, 1);
execute cup_result('c1900000-0000-4000-8000-0000000005a1', 2, null, 'both_absent', 0, 0, 0, 0, 0, 0);
-- Decided again: nothing changes.
execute cup_result('c1900000-0000-4000-8000-0000000005a1', 1, '00000000-0190-4000-8190-000000000002', 'points', 0, 9, 0, 0, 0, 0);
select pg_temp.check(
  (select winner_user from gamification.h2h_cup_results where stage_id = 'c1900000-0000-4000-8000-0000000005a1' and slot = 1) = '00000000-0190-4000-8190-000000000001',
  'a result decided twice keeps its first winner');
select pg_temp.refused($q$execute cup_result('c1900000-0000-4000-8000-0000000005a9', 1, null, 'both_absent', 0, 0, 0, 0, 0, 0)$q$,
  'h2h_cup_results_pair_fkey', 'a result needs its pair');

create temp table stages_out as execute cup_stages('2099-11-01');
select pg_temp.check((select count(*) from stages_out) = 1, 'one stage');
select pg_temp.check((select fixture_count from stages_out) = 3, 'the stage reads its frozen count');
select pg_temp.check((select locked_at from stages_out) is not null, 'the stage is locked');
create temp table pairs_out as execute cup_pairs('2099-11-01');
select pg_temp.check((select count(*) from pairs_out) = 2, 'two pairs');
select pg_temp.check((select winner_user from pairs_out where slot = 1) = '00000000-0190-4000-8190-000000000001', 'pair 1: u1 won');
select pg_temp.check((select outcome from pairs_out where slot = 2) = 'both_absent', 'pair 2: both lost');
select pg_temp.check((select winner_user from pairs_out where slot = 2) is null, 'pair 2: no winner');

-- ---------------------------------------------------------------------------
-- The title: u1 alone reached the final.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute cup_title('2099-11-01', 1, null, null, 'walkover')$q$,
  'h2h_cup_titles_champion_present', 'a walkover needs a champion');
execute cup_title('2099-11-01', 1, '00000000-0190-4000-8190-000000000001', null, 'walkover');
execute cup_title('2099-11-01', 1, '00000000-0190-4000-8190-000000000002', null, 'final');
create temp table titles_out as execute cup_titles('2099-11-01');
select pg_temp.check((select champion from titles_out where place = 1) = '00000000-0190-4000-8190-000000000001',
  'a title decided twice keeps its first champion');

-- Path 2 may follow on a later day.
execute cup_stage('c1900000-0000-4000-8000-0000000005a2', '2099-11-01', 2, 'semi', 1, '2099-11-21', 1);
select pg_temp.check((select count(*) from gamification.h2h_cup_stages) = 2, 'path 2 on the 21st');

-- ---------------------------------------------------------------------------
-- Append-only, server-only.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$update gamification.h2h_cup_stages set day = '2099-11-25'$q$, null,
  'a stage is never changed');
select pg_temp.refused($q$delete from gamification.h2h_cup_results$q$, null,
  'a result is never deleted');
select pg_temp.refused($q$delete from gamification.h2h_cup_titles$q$, null,
  'a title is never deleted');
select pg_temp.check(
  (select bool_and(relrowsecurity) from pg_class
    where relnamespace = 'gamification'::regnamespace and relname like 'h2h_cup_%'
      and relkind = 'r'),
  'row level security on every cup table');
select pg_temp.check(
  not has_table_privilege('authenticated', 'gamification.h2h_cup_stages', 'select'),
  'players read nothing directly');

rollback;
