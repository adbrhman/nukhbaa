-- Script 195 (review L-8): in the Elite Cup a suspended account counts no
-- point, exact call or prediction on the stage, so it is absent and its
-- opponent goes through on a walkover. Runs the side query of
-- PostgresH2hCupStore.sidesSql as written there. Rolled back at the end.
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

insert into competition.competitions (id, name, format, visibility) values
  ('e9000000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('e9000000-0000-4000-8000-000000000010', 'e9000000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('e9000000-0000-4000-8000-0000000000f1', 'Cup Home 195', 'Cup Away 195',
   '2099-06-01 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('e9000000-0000-4000-8000-000000000010', 'e9000000-0000-4000-8000-0000000000f1', 0);
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8095-000000000001', 'cup1@t.io', now()),
  ('00000000-0000-4000-8095-000000000002', 'cup2@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8095-000000000001', 'cup1@t.io', 'Cup1', '2099-05-01'),
  ('00000000-0000-4000-8095-000000000002', 'cup2@t.io', 'Cup2', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('e9000000-0000-4000-8000-0000000000a1', 'e9000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8095-000000000001', '2099-06-01'),
  ('e9000000-0000-4000-8000-0000000000a2', 'e9000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8095-000000000002', '2099-06-01');
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('e9000000-0000-4000-8000-00000000b011', 'e9000000-0000-4000-8000-0000000000f1',
   'e9000000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('e9000000-0000-4000-8000-00000000b012', 'e9000000-0000-4000-8000-0000000000f1',
   'e9000000-0000-4000-8000-0000000000a2', 1, 0, true, now());

-- The cup's own guards want a judged league month; this test reads one
-- stage only, so the stage, its fixture and its pair are seeded past them.
set local session_replication_role = replica;
insert into gamification.h2h_cup_stages
  (id, month_start, place, stage, attempt, day, fixture_count, created_at) values
  ('e9000000-0000-4000-8000-0000000000c1', '2099-06-01', 1, 'semi', 1, '2099-06-01', 1, now());
insert into gamification.h2h_cup_stage_fixtures (stage_id, fixture_id) values
  ('e9000000-0000-4000-8000-0000000000c1', 'e9000000-0000-4000-8000-0000000000f1');
insert into gamification.h2h_cup_pairs (stage_id, slot, home_user, away_user) values
  ('e9000000-0000-4000-8000-0000000000c1', 1,
   '00000000-0000-4000-8095-000000000001', '00000000-0000-4000-8095-000000000002');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('e9000000-0000-4000-8000-0000000000f1', 'e9000000-0000-4000-8000-0000000000a1', 4, 'exact_scoreline', 3),
  ('e9000000-0000-4000-8000-0000000000f1', 'e9000000-0000-4000-8000-0000000000a2', 4, 'exact_scoreline', 6);
set local session_replication_role = origin;

-- PostgresH2hCupStore.sidesSql, the stage id bound.
create temp view cup_sides as
WITH st AS (
  SELECT s.id, s.day FROM gamification.h2h_cup_stages s
  WHERE s.id = 'e9000000-0000-4000-8000-0000000000c1'::uuid
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
  WHERE p.stage_id = 'e9000000-0000-4000-8000-0000000000c1'::uuid
  UNION
  SELECT p.away_user FROM gamification.h2h_cup_pairs p
  WHERE p.stage_id = 'e9000000-0000-4000-8000-0000000000c1'::uuid
)
SELECT pl.user_id::text                                    AS user_id,
       COALESCE(sum(s.points), 0)::integer                 AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer       AS exact_count,
       count(fp.id)::integer                               AS predicted_count
FROM players pl
JOIN competition.participants p ON p.user_id = pl.user_id
JOIN identity.users u ON u.id = pl.user_id
JOIN competition.season_fixtures sf ON sf.season_id = p.season_id
JOIN valid v ON v.fixture_id = sf.fixture_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = v.fixture_id AND fp.participant_id = p.id
  AND u.status <> 'suspended'
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = v.fixture_id AND s.participant_id = p.id
  AND u.status <> 'suspended'
GROUP BY pl.user_id;

select pg_temp.check(
  (select points = 6 and predicted_count = 1 from cup_sides
    where user_id = '00000000-0000-4000-8095-000000000002'),
  'both active: the away side counts its 6 points and its call');

update identity.users set status = 'suspended'
 where id = '00000000-0000-4000-8095-000000000002';

select pg_temp.check(
  (select points = 0 and exact_count = 0 and predicted_count = 0 from cup_sides
    where user_id = '00000000-0000-4000-8095-000000000002'),
  'suspended: no point, no exact call, no prediction (absent)');
select pg_temp.check(
  (select points = 3 and predicted_count = 1 from cup_sides
    where user_id = '00000000-0000-4000-8095-000000000001'),
  'the opponent keeps his 3 points and his call');
select pg_temp.check(
  (select count(*) = 2 from cup_sides), 'both sides still listed');

rollback;
