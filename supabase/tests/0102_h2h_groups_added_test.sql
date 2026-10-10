-- End-to-end test for migration 0102 and the statements
-- PostgresH2hGroupExtension runs: the admin log takes 'groups_added' and
-- still refuses an unknown action; the players waiting for a seat are read
-- most days first; new groups and seats are written into a drawn month and
-- 0100's constraints refuse a place or a player taken twice. The PREPARE
-- statements below are generated from the adapter's SQL constants, text for
-- text, with @name::type turned into $n::type. Rolled back at the end.
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

-- The constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_constraint = constraint_name;
  return coalesce(v_constraint, sqlerrm);
end $$;

-- waitingSql
PREPARE ext_waiting(date, integer) AS
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
         COALESCE(sum(s.points), 0)                           AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline')  AS exact
  FROM competition.participants p
  JOIN identity.users u ON u.id = p.user_id AND u.status <> 'suspended'
  JOIN fx ON fx.season_id = p.season_id
  LEFT JOIN prediction.fixture_predictions fp
    ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
  LEFT JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  WHERE NOT EXISTS (
    SELECT 1
    FROM gamification.h2h_league_members m
    WHERE m.month_start = $1::date
      AND m.user_id = p.user_id
  )
  GROUP BY p.user_id
)
SELECT user_id::text AS user_id
FROM per
WHERE active_days >= $2::integer
ORDER BY active_days DESC, points DESC, exact DESC, user_id;


-- insertGroupSql
PREPARE ext_insert_group(uuid, date, smallint, smallint, smallint) AS
INSERT INTO gamification.h2h_leagues
  (id, month_start, division, group_index, capacity)
VALUES ($1::uuid, $2::date, $3::smallint,
        $4::smallint, $5::smallint);


-- insertSeatSql
PREPARE ext_insert_seat(uuid, date, uuid, smallint) AS
INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES ($1::uuid, $2::date, $3::uuid, $4::smallint);


-- ---------------------------------------------------------------------------
-- The admin log
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0102-4000-8102-000000000000', 'admin102@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0102-4000-8102-000000000000', 'admin102@t.io', 'Admin');

do $$
begin
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_admin_actions (id, action, actor, detail)
      values (gen_random_uuid(), 'groups_added', '00000000-0102-4000-8102-000000000000',
              '{"month":"2099-12-01","groups":3,"seats":60}')$q$) = 'none',
    'the admin log takes groups_added');
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_admin_actions (id, action)
      values (gen_random_uuid(), 'points_changed')$q$) = 'h2h_admin_actions_action_known',
    'an unknown action is still refused');
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_admin_actions (id, action)
      values (gen_random_uuid(), 'seat_added')$q$) = 'none',
    'the actions of 0101 are still taken');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations where version = '0102_h2h_groups_added'),
    'the migration records itself');
end $$;

-- ---------------------------------------------------------------------------
-- The world: December 2099, fixtures on three Riyadh days (the 3rd, 4th and
-- 5th), seven players. w4 already holds a seat; w5 is suspended.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1020000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-000000000001',
   '12/2099', '2099-11-30 21:00Z', '2099-12-31 21:00Z');

-- f1: Riyadh 2099-12-03. f2: 22:30Z on the 3rd is 01:30 on the 4th in
-- Riyadh. f3: 2099-12-05. f4: a test fixture on the 6th, which makes no
-- day.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1020000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-12-03 15:00Z'),
  ('c1020000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-12-03 22:30Z'),
  ('c1020000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-12-05 18:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c1020000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-12-06 18:00Z', true);
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f1', 0),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f2', 1),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f3', 2),
  ('c1020000-0000-4000-8000-000000000010', 'c1020000-0000-4000-8000-0000000000f4', 3);

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0102-4000-8102-00000000000' || n)::uuid, 'w' || n || '@t.io', now()
from generate_series(1, 7) n;
insert into identity.users (id, email, display_name)
select ('00000000-0102-4000-8102-00000000000' || n)::uuid, 'w' || n || '@t.io', 'W' || n
from generate_series(1, 7) n;
update identity.users set status = 'suspended'
 where id = '00000000-0102-4000-8102-000000000005';

insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1020000-0000-4000-8000-0000000000a' || n)::uuid,
       'c1020000-0000-4000-8000-000000000010',
       ('00000000-0102-4000-8102-00000000000' || n)::uuid, '2099-12-01'
from generate_series(1, 7) n;

-- Days predicted: w1 three, w2 three, w3 two (with the most points), w4
-- three (seated), w5 three (suspended), w6 one, w7 none.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), ('c1020000-0000-4000-8000-0000000000f' || f)::uuid,
       ('c1020000-0000-4000-8000-0000000000a' || p)::uuid, 1, 0, false, now()
from (values (1, 1), (1, 2), (1, 3),
             (2, 1), (2, 2), (2, 3),
             (3, 1), (3, 3),
             (4, 1), (4, 2), (4, 3),
             (5, 1), (5, 2), (5, 3),
             (6, 1)) v(p, f);

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1020000-0000-4000-8000-0000000000f1', 1, 0, '2099-12-03 17:00Z'),
  ('c1020000-0000-4000-8000-0000000000f3', 1, 0, '2099-12-05 20:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a2', 1, 'incorrect', 0),
  ('c1020000-0000-4000-8000-0000000000f1', 'c1020000-0000-4000-8000-0000000000a3', 1, 'exact_scoreline', 3),
  ('c1020000-0000-4000-8000-0000000000f3', 'c1020000-0000-4000-8000-0000000000a3', 1, 'exact_scoreline', 6);

-- December is drawn with one first-division group; w4 holds its seat 0.
insert into gamification.h2h_months (month_start, is_pilot, seated_count) values
  ('2099-12-01', true, 1);
execute ext_insert_group('c1020000-0000-4000-8000-0000000000e1', '2099-12-01', 1, 0, 20);
execute ext_insert_seat('c1020000-0000-4000-8000-0000000000e1', '2099-12-01', '00000000-0102-4000-8102-000000000004', 0);

-- ---------------------------------------------------------------------------
-- Who is waiting
-- ---------------------------------------------------------------------------
create temp table waiting2_out as execute ext_waiting('2099-12-01', 2);
create temp table waiting1_out as execute ext_waiting('2099-12-01', 1);
create temp table waiting_none_out as execute ext_waiting('2099-11-01', 1);

do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from waiting2_out)
      = array['00000000-0102-4000-8102-000000000001',
              '00000000-0102-4000-8102-000000000002',
              '00000000-0102-4000-8102-000000000003'],
    'two days or more: the most days first, then the most points; seated and suspended left out');
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from waiting1_out)
      = array['00000000-0102-4000-8102-000000000001',
              '00000000-0102-4000-8102-000000000002',
              '00000000-0102-4000-8102-000000000003',
              '00000000-0102-4000-8102-000000000006'],
    'one day or more adds w6; w7 predicted nothing');
  perform pg_temp.check(
    (select count(*) from waiting_none_out) = 0,
    'a month without fixtures has nobody waiting');
end $$;

-- ---------------------------------------------------------------------------
-- New groups in the drawn month
-- ---------------------------------------------------------------------------
execute ext_insert_group('c1020000-0000-4000-8000-0000000000e2', '2099-12-01', 2, 0, 20);
execute ext_insert_seat('c1020000-0000-4000-8000-0000000000e2', '2099-12-01', '00000000-0102-4000-8102-000000000001', 0);
execute ext_insert_seat('c1020000-0000-4000-8000-0000000000e2', '2099-12-01', '00000000-0102-4000-8102-000000000002', 1);

create temp table waiting_after_out as execute ext_waiting('2099-12-01', 2);

do $$
begin
  perform pg_temp.check(
    (select count(*) from gamification.h2h_leagues where month_start = '2099-12-01') = 2
      and (select count(*) from gamification.h2h_league_members where month_start = '2099-12-01') = 3,
    'a second group and its seats are written into the drawn month');
  perform pg_temp.check(
    (select seated_count from gamification.h2h_months where month_start = '2099-12-01') = 1,
    'the month row keeps the seats of its own draw');
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from waiting_after_out)
      = array['00000000-0102-4000-8102-000000000003'],
    'the new members are no longer waiting');
  perform pg_temp.check(
    pg_temp.refusal($q$execute ext_insert_group('c1020000-0000-4000-8000-0000000000e3', '2099-12-01', 2, 0, 20)$q$)
      = 'h2h_leagues_month_division_index_uniq',
    'a group place taken twice is refused');
  perform pg_temp.check(
    pg_temp.refusal($q$execute ext_insert_group('c1020000-0000-4000-8000-0000000000e4', '2100-01-01', 1, 0, 20)$q$)
      = 'h2h_leagues_month_fkey',
    'a group of a month not drawn is refused');
  perform pg_temp.check(
    pg_temp.refusal($q$execute ext_insert_seat('c1020000-0000-4000-8000-0000000000e2', '2099-12-01', '00000000-0102-4000-8102-000000000004', 2)$q$)
      in ('h2h_league_members_month_user_uniq', 'h2h_league_members_pkey'),
    'a player seated twice in a month is refused');
end $$;

rollback;
