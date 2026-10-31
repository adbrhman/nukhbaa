-- Migration 0189 (relegation for absence, NK183) and the statements its
-- adapters run: PostgresH2hSeatMoveStore, and the seat-swap reading of
-- PostgresH2hSheetReader.membersSql / scoresSql and PostgresH2hLeagueStore.
-- seatSql. The PREPARE statements are generated from the adapters' SQL
-- constants, text for text, with @name::type turned into $n::type. Rows of
-- a result kept in a temp table are read back in the order the statement
-- returned them (ctid). Rolled back at the end.
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

-- movesSql
PREPARE mv_moves(date) AS

SELECT id::text                              AS id,
       to_char(month_start, 'YYYY-MM-DD')    AS month,
       from_round                            AS from_round,
       kind                                  AS kind,
       out_user::text                        AS out_user,
       in_user::text                         AS in_user,
       elite_league_id::text                 AS elite_league_id,
       elite_slot                            AS elite_slot,
       extra_league_id::text                 AS extra_league_id,
       extra_slot                            AS extra_slot,
       absent_rounds::text                   AS absent_rounds,
       candidate::text                       AS candidate,
       reason                                AS reason,
       decided_by::text                      AS decided_by,
       created_at                            AS created_at
FROM gamification.h2h_seat_moves
WHERE month_start = $1::date
ORDER BY from_round, created_at, id;

-- attendanceSql
PREPARE mv_attendance(text) AS

WITH rd AS (
  SELECT r.id, r.day
  FROM gamification.h2h_rounds r
  JOIN gamification.h2h_round_locks k ON k.round_id = r.id
  WHERE r.id = ANY(string_to_array($1, ',')::uuid[])
),
fx AS (
  SELECT rd.id AS round_id, rf.fixture_id, fs.kickoff_at
  FROM rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
)
SELECT rd.id::text AS round_id,
       (SELECT count(*) FROM fx WHERE fx.round_id = rd.id)::integer
                                                           AS fixtures,
       (SELECT max(fx.kickoff_at) FROM fx WHERE fx.round_id = rd.id)
                                                           AS last_kickoff,
       COALESCE((
         SELECT string_agg(DISTINCT p.user_id::text, ',')
         FROM fx
         JOIN prediction.fixture_predictions fp
           ON fp.fixture_id = fx.fixture_id
         JOIN competition.participants p ON p.id = fp.participant_id
         WHERE fx.round_id = rd.id
       ), '')                                              AS present
FROM rd
ORDER BY rd.day;

-- excusalsSql
PREPARE mv_excusals(text) AS

SELECT e.round_id::text  AS round_id,
       e.reason          AS reason,
       e.excused_by::text AS excused_by,
       e.created_at      AS created_at
FROM gamification.h2h_round_excusals e
WHERE e.round_id = ANY(string_to_array($1, ',')::uuid[]);

-- candidateFactsSql
PREPARE mv_facts(date, integer, text) AS

WITH fx AS (
  SELECT DISTINCT sf.season_id, fs.fixture_id,
         (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date AS d
  FROM competition.season_fixtures sf
  JOIN competition.fixture_schedules fs ON fs.fixture_id = sf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
        > ($1::date - $2::integer)
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date <= $1::date
),
who AS (
  SELECT unnest(string_to_array($3, ',')::uuid[]) AS user_id
)
SELECT w.user_id::text                                            AS user_id,
       (count(DISTINCT fx.fixture_id)
          - count(DISTINCT fx.fixture_id) FILTER (WHERE fp.id IS NOT NULL)
       )::integer                                                 AS missed,
       COALESCE(sum(s.points), 0)::integer                        AS points,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'exact_scoreline')::integer              AS exact,
       count(DISTINCT fx.d) FILTER (WHERE fp.id IS NOT NULL)::integer
                                                                  AS active_days
FROM who w
LEFT JOIN competition.participants p ON p.user_id = w.user_id
LEFT JOIN fx ON fx.season_id = p.season_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
GROUP BY w.user_id;

-- insertMoveSql
PREPARE mv_insert(uuid, date, smallint, text, uuid, uuid, uuid, smallint, uuid, smallint, jsonb, jsonb, text, uuid) AS

INSERT INTO gamification.h2h_seat_moves
  (id, month_start, from_round, kind, out_user, in_user,
   elite_league_id, elite_slot, extra_league_id, extra_slot,
   absent_rounds, candidate, reason, decided_by)
VALUES ($1::uuid, $2::date, $3::smallint, $4::text,
        $5::uuid, $6::uuid,
        $7::uuid, $8::smallint,
        $9::uuid, $10::smallint,
        $11::jsonb, $12::jsonb, $13::text,
        $14::uuid);

-- logSql
PREPARE mv_log(uuid, text, uuid, jsonb) AS

INSERT INTO gamification.h2h_admin_actions (id, action, actor, detail)
VALUES ($1::uuid, $2::text, $3::uuid, $4::jsonb);

-- excuseSql
PREPARE mv_excuse(uuid, text, uuid) AS

INSERT INTO gamification.h2h_round_excusals (round_id, reason, excused_by)
VALUES ($1::uuid, $2::text, $3::uuid)
ON CONFLICT (round_id) DO NOTHING
RETURNING 1 AS excused;

-- warningSql
PREPARE mv_warn(uuid, uuid) AS

INSERT INTO gamification.h2h_absence_warnings (round_id, user_id)
VALUES ($1::uuid, $2::uuid)
ON CONFLICT (round_id, user_id) DO NOTHING
RETURNING 1 AS warned;

-- warningsSql
PREPARE mv_warnings(text) AS

SELECT w.round_id::text AS round_id,
       w.user_id::text  AS user_id,
       w.created_at     AS created_at
FROM gamification.h2h_absence_warnings w
WHERE w.round_id = ANY(string_to_array($1, ',')::uuid[])
ORDER BY w.created_at;

-- tokensSql
PREPARE mv_tokens(uuid) AS

SELECT dt.token AS token
FROM notification.device_tokens dt
JOIN identity.users u ON u.id = dt.user_id
WHERE dt.user_id = $1::uuid
  AND u.status = 'active'
ORDER BY dt.token;

-- membersSql
PREPARE sheet_members(uuid) AS

WITH seats AS (
  SELECT m.user_id, m.slot, m.joined_at, 1 AS from_round
  FROM gamification.h2h_league_members m
  WHERE m.league_id = $1::uuid
  UNION ALL
  SELECT mv.in_user, mv.elite_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.elite_league_id = $1::uuid
  UNION ALL
  SELECT mv.out_user, mv.extra_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.extra_league_id = $1::uuid
),
held AS (
  SELECT s.user_id, s.slot, s.joined_at, s.from_round,
         lead(s.from_round) OVER (PARTITION BY s.slot ORDER BY s.from_round)
           - 1 AS until_round
  FROM seats s
)
SELECT h.user_id::text AS user_id,
       h.slot          AS slot,
       h.joined_at     AS joined_at,
       h.from_round    AS from_round,
       h.until_round   AS until_round
FROM held h
JOIN identity.users u ON u.id = h.user_id AND u.status <> 'suspended'
ORDER BY h.slot, h.from_round;

-- scoresSql
PREPARE sheet_scores(uuid) AS

WITH members AS (
  SELECT x.user_id
  FROM (
    SELECT m.user_id
    FROM gamification.h2h_league_members m
    WHERE m.league_id = $1::uuid
    UNION
    SELECT mv.in_user
    FROM gamification.h2h_seat_moves mv
    WHERE mv.elite_league_id = $1::uuid
    UNION
    SELECT mv.out_user
    FROM gamification.h2h_seat_moves mv
    WHERE mv.extra_league_id = $1::uuid
  ) x
  JOIN identity.users u ON u.id = x.user_id AND u.status <> 'suspended'
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

-- seatSql
PREPARE league_seat(uuid, date) AS

WITH held AS (
  SELECT m.league_id, m.slot, m.joined_at, 1 AS from_round
  FROM gamification.h2h_league_members m
  WHERE m.user_id = $1::uuid
    AND m.month_start = $2::date
  UNION ALL
  SELECT mv.elite_league_id, mv.elite_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.in_user = $1::uuid
    AND mv.month_start = $2::date
  UNION ALL
  SELECT mv.extra_league_id, mv.extra_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.out_user = $1::uuid
    AND mv.month_start = $2::date
),
seat AS (
  SELECT * FROM held ORDER BY from_round DESC LIMIT 1
)
SELECT s.league_id::text AS league_id,
       l.division        AS division,
       l.group_index     AS group_index,
       s.slot            AS slot,
       l.capacity        AS capacity,
       s.joined_at       AS joined_at,
       mo.is_pilot       AS is_pilot,
       (SELECT count(*)
          FROM gamification.h2h_leagues l2
         WHERE l2.month_start = l.month_start
           AND l2.division = l.division)::integer AS division_groups
FROM seat s
JOIN gamification.h2h_leagues l ON l.id = s.league_id
JOIN gamification.h2h_months mo ON mo.month_start = l.month_start;


-- ---------------------------------------------------------------------------
-- The world: November 2099 drawn. Elite group E (division 1): q1, q2, q3 in
-- slots 0..2. Extra group X (division 2): q4, q5 in slots 0, 1. Rounds 1
-- (the 3rd) and 2 (the 4th) locked; round 3 (the 5th) approved only.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1890000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1890000-0000-4000-8000-000000000010', 'c1890000-0000-4000-8000-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');
-- f1, f2: the 3rd (Riyadh); f3 the 3rd, hidden; f4: the 4th; f5: the 5th.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1890000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-11-03 15:00Z'),
  ('c1890000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-11-03 18:00Z'),
  ('c1890000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-11-03 19:00Z'),
  ('c1890000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-11-04 18:00Z'),
  ('c1890000-0000-4000-8000-0000000000f5', 'I', 'J', '2099-11-05 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c1890000-0000-4000-8000-000000000010', f, n
from unnest(array['c1890000-0000-4000-8000-0000000000f1',
                  'c1890000-0000-4000-8000-0000000000f2',
                  'c1890000-0000-4000-8000-0000000000f3',
                  'c1890000-0000-4000-8000-0000000000f4',
                  'c1890000-0000-4000-8000-0000000000f5']::uuid[])
     with ordinality as t(f, n);

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0189-4000-8189-00000000000' || i)::uuid, 'q' || i || '@t.io', now()
from generate_series(1, 6) i;
insert into identity.users (id, email, display_name)
select ('00000000-0189-4000-8189-00000000000' || i)::uuid, 'q' || i || '@t.io', 'Q ' || i
from generate_series(1, 6) i;
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1890000-0000-4000-8000-0000000000a' || i)::uuid,
       'c1890000-0000-4000-8000-000000000010',
       ('00000000-0189-4000-8189-00000000000' || i)::uuid, '2099-11-01'
from generate_series(1, 6) i;
insert into notification.device_tokens (user_id, token, platform)
values ('00000000-0189-4000-8189-000000000004', 'tok-q4', 'android');

-- q1 nothing; q2 f1 and the hidden f3; q3 f2 and f4; q4 f1, f4, f5; q5 f3 only.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f1', 'c1890000-0000-4000-8000-0000000000a2', 1, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f3', 'c1890000-0000-4000-8000-0000000000a2', 1, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f2', 'c1890000-0000-4000-8000-0000000000a3', 1, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f4', 'c1890000-0000-4000-8000-0000000000a3', 1, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f1', 'c1890000-0000-4000-8000-0000000000a4', 2, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f4', 'c1890000-0000-4000-8000-0000000000a4', 2, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f5', 'c1890000-0000-4000-8000-0000000000a4', 2, 0, false, now()),
  (gen_random_uuid(), 'c1890000-0000-4000-8000-0000000000f3', 'c1890000-0000-4000-8000-0000000000a5', 1, 1, false, now());
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c1890000-0000-4000-8000-0000000000f3';
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1890000-0000-4000-8000-0000000000f1', 2, 0, '2099-11-03 17:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1890000-0000-4000-8000-0000000000f1', 'c1890000-0000-4000-8000-0000000000a4', 1, 'exact_scoreline', 3),
  ('c1890000-0000-4000-8000-0000000000f1', 'c1890000-0000-4000-8000-0000000000a2', 1, 'correct_outcome', 1);

insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-11-01', false, 5);
insert into gamification.h2h_leagues (id, month_start, division, group_index, capacity) values
  ('c1890000-0000-4000-8000-0000000000e1', '2099-11-01', 1, 0, 20),
  ('c1890000-0000-4000-8000-0000000000e5', '2099-11-01', 2, 0, 20);
insert into gamification.h2h_league_members (league_id, month_start, user_id, slot) values
  ('c1890000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0189-4000-8189-000000000001', 0),
  ('c1890000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0189-4000-8189-000000000002', 1),
  ('c1890000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0189-4000-8189-000000000003', 2),
  ('c1890000-0000-4000-8000-0000000000e5', '2099-11-01', '00000000-0189-4000-8189-000000000004', 0),
  ('c1890000-0000-4000-8000-0000000000e5', '2099-11-01', '00000000-0189-4000-8189-000000000005', 1);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count) values
  ('c1890000-0000-4000-8000-0000000000d1', '2099-11-01', 1, '2099-11-03', 3),
  ('c1890000-0000-4000-8000-0000000000d2', '2099-11-01', 2, '2099-11-04', 1),
  ('c1890000-0000-4000-8000-0000000000d3', '2099-11-01', 3, '2099-11-05', 1);
insert into gamification.h2h_round_fixtures (round_id, fixture_id) values
  ('c1890000-0000-4000-8000-0000000000d1', 'c1890000-0000-4000-8000-0000000000f1'),
  ('c1890000-0000-4000-8000-0000000000d1', 'c1890000-0000-4000-8000-0000000000f2'),
  ('c1890000-0000-4000-8000-0000000000d1', 'c1890000-0000-4000-8000-0000000000f3'),
  ('c1890000-0000-4000-8000-0000000000d2', 'c1890000-0000-4000-8000-0000000000f4');
insert into gamification.h2h_round_locks (round_id, fixture_count) values
  ('c1890000-0000-4000-8000-0000000000d1', 3),
  ('c1890000-0000-4000-8000-0000000000d2', 1);

-- ---------------------------------------------------------------------------
-- Attendance: a prediction is a presence; hidden fixtures are not the
-- round's; results do not matter.
-- ---------------------------------------------------------------------------
create temp table att_out as execute mv_attendance(
  'c1890000-0000-4000-8000-0000000000d1,c1890000-0000-4000-8000-0000000000d2,c1890000-0000-4000-8000-0000000000d3');
do $$
begin
  perform pg_temp.check(
    (select array_agg(round_id || ':' || fixtures order by ctid) from att_out)
      = array['c1890000-0000-4000-8000-0000000000d1:2',
              'c1890000-0000-4000-8000-0000000000d2:1'],
    'locked rounds only, counting the fixtures still on the day');
  perform pg_temp.check(
    (select last_kickoff from att_out
      where round_id = 'c1890000-0000-4000-8000-0000000000d1')
      = '2099-11-03 18:00Z'::timestamptz,
    'the last kickoff of the round''s own fixtures');
  perform pg_temp.check(
    (select string_to_array(present, ',')::text[] from att_out
      where round_id = 'c1890000-0000-4000-8000-0000000000d1')
      @> array['00000000-0189-4000-8189-000000000002',
               '00000000-0189-4000-8189-000000000003',
               '00000000-0189-4000-8189-000000000004']
    and not (select present like '%000000000005%' or present like '%000000000001%'
               from att_out
              where round_id = 'c1890000-0000-4000-8000-0000000000d1'),
    'present: a prediction on a counted fixture, with or without a result; '
    'q5''s only pick was the hidden match');
end $$;

-- ---------------------------------------------------------------------------
-- Candidate facts over a window
-- ---------------------------------------------------------------------------
create temp table facts_out as execute mv_facts('2099-11-04', 30,
  '00000000-0189-4000-8189-000000000004,00000000-0189-4000-8189-000000000005,00000000-0189-4000-8189-000000000006');
do $$
begin
  perform pg_temp.check(
    (select missed || ':' || points || ':' || exact || ':' || active_days
       from facts_out where user_id = '00000000-0189-4000-8189-000000000004')
      = '1:3:1:2',
    'q4 missed f2 in the window (f5 is after it), 3 points, 1 exact, 2 days');
  perform pg_temp.check(
    (select missed || ':' || active_days from facts_out
      where user_id = '00000000-0189-4000-8189-000000000006') = '3:0',
    'a player who predicted nothing: every match missed, no day');
end $$;

-- ---------------------------------------------------------------------------
-- A swap: q1 (absent) leaves E slot 0 to q4, who leaves X slot 0, from
-- round 3.
-- ---------------------------------------------------------------------------
execute mv_insert('c1890000-0000-4000-8000-00000000aa01', '2099-11-01', 3,
  'absence', '00000000-0189-4000-8189-000000000001',
  '00000000-0189-4000-8189-000000000004',
  'c1890000-0000-4000-8000-0000000000e1', 0,
  'c1890000-0000-4000-8000-0000000000e5', 0,
  '[{"month":"2099-11-01","round":1},{"month":"2099-11-01","round":2}]',
  '{"user_id":"00000000-0189-4000-8189-000000000004","missed":1,"points":3,"exact":1,"active_days":2}',
  null, null);
execute mv_log('c1890000-0000-4000-8000-00000000ab01', 'seat_moved', null, '{}');

create temp table moves_out as execute mv_moves('2099-11-01');
create temp table e_members as execute sheet_members('c1890000-0000-4000-8000-0000000000e1');
create temp table x_members as execute sheet_members('c1890000-0000-4000-8000-0000000000e5');
create temp table e_scores as execute sheet_scores('c1890000-0000-4000-8000-0000000000e1');
create temp table seat_q1 as execute league_seat('00000000-0189-4000-8189-000000000001', '2099-11-01');
create temp table seat_q4 as execute league_seat('00000000-0189-4000-8189-000000000004', '2099-11-01');
create temp table seat_q2 as execute league_seat('00000000-0189-4000-8189-000000000002', '2099-11-01');
do $$
begin
  perform pg_temp.check(
    (select from_round = 3 and kind = 'absence' and elite_slot = 0
        and absent_rounds::jsonb -> 1 ->> 'round' = '2'
        and candidate::jsonb ->> 'missed' = '1'
       from moves_out),
    'the swap reads back with its rounds and facts');
  perform pg_temp.check(
    (select array_agg(substr(user_id, 33) || '@' || slot || ':' || from_round
                      || '-' || coalesce(until_round::text, '') order by ctid)
       from e_members)
      = array['0001@0:1-2', '0004@0:3-', '0002@1:1-', '0003@2:1-'],
    'the elite seat: q1 for rounds 1-2, q4 from round 3');
  perform pg_temp.check(
    (select array_agg(substr(user_id, 33) || '@' || slot || ':' || from_round
                      || '-' || coalesce(until_round::text, '') order by ctid)
       from x_members)
      = array['0004@0:1-2', '0001@0:3-', '0005@1:1-'],
    'the extra seat: q4 for rounds 1-2, q1 from round 3');
  perform pg_temp.check(
    exists (select 1 from e_scores
             where user_id = '00000000-0189-4000-8189-000000000004'
               and round_no = 1 and points = 3),
    'the elite group reads the scores of the player who came in');
  perform pg_temp.check(
    (select league_id = 'c1890000-0000-4000-8000-0000000000e5' and slot = 0
        and division = 2 from seat_q1)
    and (select league_id = 'c1890000-0000-4000-8000-0000000000e1' and slot = 0
        and division = 1 from seat_q4)
    and (select league_id = 'c1890000-0000-4000-8000-0000000000e1' and slot = 1
        from seat_q2),
    'each player''s seat is the one he holds now');
end $$;

-- ---------------------------------------------------------------------------
-- The backstops
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa02',
  '2099-11-01', 3, 'absence', '00000000-0189-4000-8189-000000000001',
  '00000000-0189-4000-8189-000000000005', 'c1890000-0000-4000-8000-0000000000e1', 1,
  'c1890000-0000-4000-8000-0000000000e5', 1, '[]', '{}', null, null)$q$,
  'h2h_seat_moves_out_once', 'a player is relegated once a month');
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa03',
  '2099-11-01', 3, 'absence', '00000000-0189-4000-8189-000000000002',
  '00000000-0189-4000-8189-000000000001', 'c1890000-0000-4000-8000-0000000000e1', 1,
  'c1890000-0000-4000-8000-0000000000e5', 0, '[]', '{}', null, null)$q$,
  'h2h_seat_moves_no_return', 'a relegated player does not come back');
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa04',
  '2099-11-01', 2, 'absence', '00000000-0189-4000-8189-000000000002',
  '00000000-0189-4000-8189-000000000005', 'c1890000-0000-4000-8000-0000000000e1', 1,
  'c1890000-0000-4000-8000-0000000000e5', 1, '[]', '{}', null, null)$q$,
  'h2h_seat_moves_round_not_started', 'a swap never touches a round that started');
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa05',
  '2099-11-01', 3, 'absence', '00000000-0189-4000-8189-000000000002',
  '00000000-0189-4000-8189-000000000005', 'c1890000-0000-4000-8000-0000000000e5', 1,
  'c1890000-0000-4000-8000-0000000000e1', 1, '[]', '{}', null, null)$q$,
  'h2h_seat_moves_divisions', 'an elite seat for an extra seat, never the other way');
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa06',
  '2099-11-01', 3, 'admin', '00000000-0189-4000-8189-000000000002',
  '00000000-0189-4000-8189-000000000005', 'c1890000-0000-4000-8000-0000000000e1', 1,
  'c1890000-0000-4000-8000-0000000000e5', 1, '[]', '{}', ' ', null)$q$,
  'h2h_seat_moves_admin_reason', 'a swap by hand needs a reason and its admin');
select pg_temp.refused($q$execute mv_insert('c1890000-0000-4000-8000-00000000aa07',
  '2099-11-01', 20, 'absence', '00000000-0189-4000-8189-000000000002',
  '00000000-0189-4000-8189-000000000005', 'c1890000-0000-4000-8000-0000000000e1', 1,
  'c1890000-0000-4000-8000-0000000000e5', 1, '[]', '{}', null, null)$q$,
  'h2h_seat_moves_from_round_range', 'no swap after round 19');
select pg_temp.refused(
  $q$update gamification.h2h_seat_moves set from_round = 4$q$,
  null, 'a swap is never changed');


-- ---------------------------------------------------------------------------
-- Excusals and warnings: once each.
-- ---------------------------------------------------------------------------
execute mv_excuse('c1890000-0000-4000-8000-0000000000d2', 'تعطل', '00000000-0189-4000-8189-000000000006');
execute mv_excuse('c1890000-0000-4000-8000-0000000000d2', 'تعطل', '00000000-0189-4000-8189-000000000006');
create temp table exs as execute mv_excusals('c1890000-0000-4000-8000-0000000000d1,c1890000-0000-4000-8000-0000000000d2');
execute mv_warn('c1890000-0000-4000-8000-0000000000d2', '00000000-0189-4000-8189-000000000002');
execute mv_warn('c1890000-0000-4000-8000-0000000000d2', '00000000-0189-4000-8189-000000000002');
create temp table ws as execute mv_warnings('c1890000-0000-4000-8000-0000000000d2');
create temp table toks as execute mv_tokens('00000000-0189-4000-8189-000000000004');
execute mv_log('c1890000-0000-4000-8000-00000000ab02', 'round_excused', '00000000-0189-4000-8189-000000000006', '{}');
do $$
begin
  perform pg_temp.check(
    (select count(*) from gamification.h2h_round_excusals
      where round_id = 'c1890000-0000-4000-8000-0000000000d2') = 1,
    'a round is excused once; a second excusal changes nothing');
  perform pg_temp.check((select reason from exs) = 'تعطل', 'the excusal reads back');
  perform pg_temp.check((select count(*) from ws) = 1,
    'a warning is recorded once per round and player');
  perform pg_temp.check((select array_agg(token) from toks) = array['tok-q4'],
    'the player''s push tokens');
  perform pg_temp.check(
    (select count(*) from gamification.h2h_admin_actions
      where id in ('c1890000-0000-4000-8000-00000000ab01',
                   'c1890000-0000-4000-8000-00000000ab02')) = 2,
    'the admin log takes seat_moved and round_excused');
end $$;

insert into notification.push_opens (user_id, link)
values ('00000000-0189-4000-8189-000000000004', 'h2h');
select pg_temp.check(true, 'a push opening the league''s tab is recorded');

rollback;
