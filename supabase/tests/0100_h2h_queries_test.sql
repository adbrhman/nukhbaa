-- End-to-end test of the statements the head-to-head adapters run (0100):
-- PostgresH2hLeagueStore, PostgresH2hRoundStore, PostgresH2hDrawSource and
-- PostgresH2hSheetReader. The PREPARE statements below are generated from
-- the adapters' SQL constants, text for text, with @name::type turned into
-- $n::type. Rows of a result kept in a fresh temp table are read back in
-- the order the statement returned them (ctid). Rolled back at the end.
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

-- monthOfSql
PREPARE league_month_of(date) AS

SELECT is_pilot, seated_count
FROM gamification.h2h_months
WHERE month_start = $1::date;

-- isClosedSql
PREPARE league_is_closed(date) AS

SELECT 1 AS hit
FROM gamification.h2h_month_closures
WHERE month_start = $1::date;

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

-- seatSql
PREPARE league_seat(uuid, date) AS

SELECT m.league_id::text AS league_id,
       l.division        AS division,
       l.group_index     AS group_index,
       m.slot            AS slot,
       l.capacity        AS capacity,
       m.joined_at       AS joined_at,
       mo.is_pilot       AS is_pilot,
       (SELECT count(*)
          FROM gamification.h2h_leagues l2
         WHERE l2.month_start = l.month_start
           AND l2.division = l.division)::integer AS division_groups
FROM gamification.h2h_league_members m
JOIN gamification.h2h_leagues l ON l.id = m.league_id
JOIN gamification.h2h_months mo ON mo.month_start = m.month_start
WHERE m.user_id = $1::uuid
  AND m.month_start = $2::date;

-- groupsSql
PREPARE league_groups(date) AS

SELECT id::text    AS league_id,
       division    AS division,
       group_index AS group_index,
       capacity    AS capacity
FROM gamification.h2h_leagues
WHERE month_start = $1::date
ORDER BY division, group_index;

-- nextUnclosedSql
PREPARE league_next_unclosed AS

SELECT to_char(min(m.month_start), 'YYYY-MM-DD') AS month
FROM gamification.h2h_months m
WHERE NOT EXISTS (
  SELECT 1 FROM gamification.h2h_month_closures c
  WHERE c.month_start = m.month_start
);

-- markClosedSql
PREPARE league_mark_closed(date, integer) AS

INSERT INTO gamification.h2h_month_closures (month_start, member_count)
VALUES ($1::date, $2::integer)
ON CONFLICT (month_start) DO NOTHING;

-- roundsSql
PREPARE round_rounds(date) AS

SELECT r.id::text                              AS id,
       r.round_no                              AS round_no,
       to_char(r.day, 'YYYY-MM-DD')            AS day,
       COALESCE(k.fixture_count, r.fixture_count) AS fixture_count,
       r.approved_by::text                     AS approved_by,
       k.locked_at                             AS locked_at
FROM gamification.h2h_rounds r
LEFT JOIN gamification.h2h_round_locks k ON k.round_id = r.id
WHERE r.month_start = $1::date
ORDER BY r.round_no;

-- daysSql
PREPARE round_days(date, date) AS

SELECT to_char((fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date, 'YYYY-MM-DD')
         AS day,
       count(DISTINCT fs.fixture_id)::integer AS fixture_count,
       min(fs.kickoff_at)                     AS first_kickoff
FROM competition.fixture_schedules fs
WHERE fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND EXISTS (
    SELECT 1 FROM competition.season_fixtures sf
    WHERE sf.fixture_id = fs.fixture_id
  )
  AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date
      BETWEEN $1::date AND $2::date
GROUP BY 1
ORDER BY 1;

-- approveSql
PREPARE round_approve(uuid, date, smallint, date, smallint, uuid) AS

INSERT INTO gamification.h2h_rounds
  (id, month_start, round_no, day, fixture_count, approved_by)
VALUES ($1::uuid, $2::date, $3::smallint, $4::date,
        $5::smallint, $6::uuid);

-- withdrawSql
PREPARE round_withdraw(uuid) AS

DELETE FROM gamification.h2h_rounds
WHERE id = $1::uuid
RETURNING 1 AS withdrawn;

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

-- lockedCountSql
PREPARE round_locked_count(uuid) AS

SELECT fixture_count
FROM gamification.h2h_round_locks
WHERE round_id = $1::uuid;

-- activeOrderSql
PREPARE draw_active_order(date, integer) AS

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
  GROUP BY p.user_id
)
SELECT user_id::text AS user_id
FROM per
WHERE active_days >= $2::integer
ORDER BY points DESC, exact DESC, user_id;

-- carriedSql
PREPARE draw_carried(text) AS

SELECT e.user_id::text                           AS user_id,
       (e.payload ->> 'next_division')::integer   AS next_division,
       (e.payload ->> 'division')::integer        AS division,
       (e.payload ->> 'rank')::integer            AS rank
FROM gamification.events e
JOIN identity.users u ON u.id = e.user_id AND u.status <> 'suspended'
WHERE e.event_type = 'h2h_league_finished'
  AND e.payload ->> 'month' = $1::text
  AND e.payload ->> 'next_division' IS NOT NULL
ORDER BY 2, 3, 4, 1;

-- pilotOrderSql
PREPARE draw_pilot_order(date) AS

WITH pilot AS (
  SELECT a.user_id
  FROM gamification.experiment_assignments a
  JOIN identity.users u ON u.id = a.user_id AND u.status <> 'suspended'
  WHERE a.flag_key = 'h2h_pilot'
    AND a.variant = 'pilot'
),
fx AS (
  SELECT DISTINCT sf.season_id, sf.fixture_id
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
         COALESCE(sum(s.points), 0)                          AS points,
         count(*) FILTER (WHERE s.grade = 'exact_scoreline') AS exact
  FROM pilot pl
  JOIN competition.participants p ON p.user_id = pl.user_id
  JOIN fx ON fx.season_id = p.season_id
  JOIN scoring.fixture_scores s
    ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
  GROUP BY p.user_id
)
SELECT pl.user_id::text AS user_id
FROM pilot pl
LEFT JOIN per ON per.user_id = pl.user_id
ORDER BY COALESCE(per.points, 0) DESC, COALESCE(per.exact, 0) DESC, pl.user_id;

-- membersSql
PREPARE sheet_members(uuid) AS

SELECT m.user_id::text AS user_id,
       m.slot          AS slot,
       m.joined_at     AS joined_at
FROM gamification.h2h_league_members m
JOIN identity.users u ON u.id = m.user_id AND u.status <> 'suspended'
WHERE m.league_id = $1::uuid
ORDER BY m.slot;

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
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
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
  SELECT rd.round_no, rf.fixture_id
  FROM rounds rd
  JOIN gamification.h2h_round_fixtures rf ON rf.round_id = rd.id
  JOIN competition.fixture_schedules fs ON fs.fixture_id = rf.fixture_id
  WHERE fs.hidden_at IS NULL
    AND NOT fs.is_test
    AND (fs.kickoff_at AT TIME ZONE 'Asia/Riyadh')::date = rd.day
)
SELECT rd.round_no                      AS round_no,
       count(v.fixture_id)::integer     AS fixtures,
       count(v.fixture_id) FILTER (
         WHERE res.fixture_id IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM scoring.fixture_scores sp
             WHERE sp.fixture_id = v.fixture_id
               AND sp.grade = 'pending'
           ))::integer                  AS settled
FROM rounds rd
LEFT JOIN valid v ON v.round_no = rd.round_no
LEFT JOIN scoring.fixture_results res ON res.fixture_id = v.fixture_id
GROUP BY rd.round_no
ORDER BY rd.round_no;

-- activeDaysSql
PREPARE sheet_active_days(date) AS

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
)
SELECT p.user_id::text           AS user_id,
       count(DISTINCT fx.d)::integer AS active_days
FROM competition.participants p
JOIN fx ON fx.season_id = p.season_id
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
GROUP BY p.user_id;


-- ---------------------------------------------------------------------------
-- The world: one monthly season of November 2099, five players (the fifth
-- suspended), fixtures on three Riyadh days.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1010000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-000000000001',
   '11/2099', '2099-10-31 21:00Z', '2099-11-30 21:00Z');

-- f1, f2: Riyadh 2099-11-03. f3 hidden and f4 a test fixture, same day.
-- f5: 2099-11-05. f6: 22:30Z on the 3rd is 01:30 on the 4th in Riyadh.
-- f7: 2099-11-07, never linked to a season.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1010000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-11-03 15:00Z'),
  ('c1010000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-11-03 18:00Z'),
  ('c1010000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-11-03 19:00Z'),
  ('c1010000-0000-4000-8000-0000000000f5', 'I', 'J', '2099-11-05 18:00Z'),
  ('c1010000-0000-4000-8000-0000000000f6', 'K', 'L', '2099-11-03 22:30Z'),
  ('c1010000-0000-4000-8000-0000000000f7', 'M', 'N', '2099-11-07 18:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c1010000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-11-03 20:00Z', true);
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f1', 0),
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f2', 1),
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f3', 2),
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f4', 3),
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f5', 4),
  ('c1010000-0000-4000-8000-000000000010', 'c1010000-0000-4000-8000-0000000000f6', 5);
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c1010000-0000-4000-8000-0000000000f3';

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0101-4000-8101-000000000001', 'q1@t.io', now()),
  ('00000000-0101-4000-8101-000000000002', 'q2@t.io', now()),
  ('00000000-0101-4000-8101-000000000003', 'q3@t.io', now()),
  ('00000000-0101-4000-8101-000000000004', 'q4@t.io', now()),
  ('00000000-0101-4000-8101-000000000005', 'q5@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0101-4000-8101-000000000001', 'q1@t.io', 'Q One'),
  ('00000000-0101-4000-8101-000000000002', 'q2@t.io', 'Q Two'),
  ('00000000-0101-4000-8101-000000000003', 'q3@t.io', 'Q Three'),
  ('00000000-0101-4000-8101-000000000004', 'q4@t.io', 'Q Four'),
  ('00000000-0101-4000-8101-000000000005', 'q5@t.io', 'Q Five');
update identity.users set status = 'suspended'
 where id = '00000000-0101-4000-8101-000000000005';

insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1010000-0000-4000-8000-0000000000a1', 'c1010000-0000-4000-8000-000000000010', '00000000-0101-4000-8101-000000000001', '2099-11-01'),
  ('c1010000-0000-4000-8000-0000000000a2', 'c1010000-0000-4000-8000-000000000010', '00000000-0101-4000-8101-000000000002', '2099-11-01'),
  ('c1010000-0000-4000-8000-0000000000a3', 'c1010000-0000-4000-8000-000000000010', '00000000-0101-4000-8101-000000000003', '2099-11-01'),
  ('c1010000-0000-4000-8000-0000000000a4', 'c1010000-0000-4000-8000-000000000010', '00000000-0101-4000-8101-000000000004', '2099-11-01'),
  ('c1010000-0000-4000-8000-0000000000a5', 'c1010000-0000-4000-8000-000000000010', '00000000-0101-4000-8101-000000000005', '2099-11-01');

-- q1 predicts f1, f2 and f6 (two Riyadh days); q2 predicts f1; q3 nothing;
-- q4 predicts f2; q5 (suspended) predicts f1 and f2.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c1010000-0000-4000-8000-00000000b011', 'c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('c1010000-0000-4000-8000-00000000b012', 'c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a1', 2, 2, false, now()),
  ('c1010000-0000-4000-8000-00000000b016', 'c1010000-0000-4000-8000-0000000000f6', 'c1010000-0000-4000-8000-0000000000a1', 0, 0, false, now()),
  ('c1010000-0000-4000-8000-00000000b021', 'c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a2', 0, 3, false, now()),
  ('c1010000-0000-4000-8000-00000000b042', 'c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a4', 1, 1, false, now()),
  ('c1010000-0000-4000-8000-00000000b051', 'c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a5', 1, 0, false, now()),
  ('c1010000-0000-4000-8000-00000000b052', 'c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a5', 1, 1, false, now());

-- f1 has a result and scores; f2 is still waiting for its result.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1010000-0000-4000-8000-0000000000f1', 1, 0, '2099-11-03 17:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a2', 1, 'incorrect', 0),
  ('c1010000-0000-4000-8000-0000000000f1', 'c1010000-0000-4000-8000-0000000000a5', 1, 'exact_scoreline', 3);

-- ---------------------------------------------------------------------------
-- Days and rounds
-- ---------------------------------------------------------------------------
create temp table days_out as execute round_days('2099-11-01', '2099-11-10');
do $$
begin
  perform pg_temp.check(
    (select array_agg(day || ':' || fixture_count order by day) from days_out)
      = array['2099-11-03:2', '2099-11-04:1', '2099-11-05:1'],
    'days count visible, real, season fixtures by Riyadh day');
  perform pg_temp.check(
    (select first_kickoff from days_out where day = '2099-11-03')
      = '2099-11-03 15:00Z'::timestamptz,
    'a day carries its first kickoff');
end $$;

execute league_insert_month('2099-11-01', false, 5);
execute league_insert_month('2099-11-01', true, 9);
do $$
begin
  perform pg_temp.check(
    (select seated_count = 5 and not is_pilot from gamification.h2h_months
      where month_start = '2099-11-01'),
    'a month row is inserted once; a second draw changes nothing');
end $$;

execute league_insert_group('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', 1, 0, 20);
execute league_insert_seat('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0101-4000-8101-000000000001', 0);
execute league_insert_seat('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0101-4000-8101-000000000002', 1);
execute league_insert_seat('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0101-4000-8101-000000000003', 2);
execute league_insert_seat('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0101-4000-8101-000000000004', 3);
execute league_insert_seat('c1010000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0101-4000-8101-000000000005', 4);

create temp table month_out as execute league_month_of('2099-11-01');
create temp table seat_out as execute league_seat('00000000-0101-4000-8101-000000000002', '2099-11-01');
create temp table groups_out as execute league_groups('2099-11-01');
do $$
begin
  perform pg_temp.check(
    (select not is_pilot and seated_count = 5 from month_out),
    'the month reads back');
  perform pg_temp.check(
    (select league_id = 'c1010000-0000-4000-8000-0000000000e1'
        and division = 1 and group_index = 0 and slot = 1
        and capacity = 20 and division_groups = 1 and not is_pilot
       from seat_out),
    'a seat reads back with its group');
  perform pg_temp.check((select count(*) from groups_out) = 1,
    'the month has one group');
end $$;

execute round_approve('c1010000-0000-4000-8000-0000000000d1', '2099-11-01', 1, '2099-11-03', 2, '00000000-0101-4000-8101-000000000001');
execute round_approve('c1010000-0000-4000-8000-0000000000d2', '2099-11-01', 2, '2099-11-05', 1, null);
execute round_approve('c1010000-0000-4000-8000-0000000000d3', '2099-11-01', 3, '2099-11-07', 1, null);
execute round_withdraw('c1010000-0000-4000-8000-0000000000d3');
execute round_withdraw('c1010000-0000-4000-8000-0000000000d9');
do $$
begin
  perform pg_temp.check(
    (select count(*) from gamification.h2h_rounds
      where month_start = '2099-11-01') = 2,
    'the last unlocked round is withdrawn; an unknown one touches nothing');
end $$;

-- Lock round 1 twice: one frozen list.
execute round_freeze_fixtures('c1010000-0000-4000-8000-0000000000d1', '2099-11-03');
execute round_lock('c1010000-0000-4000-8000-0000000000d1');
execute round_freeze_fixtures('c1010000-0000-4000-8000-0000000000d1', '2099-11-03');
execute round_lock('c1010000-0000-4000-8000-0000000000d1');
create temp table locked_out as execute round_locked_count('c1010000-0000-4000-8000-0000000000d1');
-- Round 2 is locked, then its only fixture moves to another day.
execute round_freeze_fixtures('c1010000-0000-4000-8000-0000000000d2', '2099-11-05');
execute round_lock('c1010000-0000-4000-8000-0000000000d2');
update competition.fixture_schedules set kickoff_at = '2099-11-06 18:00Z'
 where fixture_id = 'c1010000-0000-4000-8000-0000000000f5';
create temp table rounds_out as execute round_rounds('2099-11-01');
do $$
begin
  perform pg_temp.check((select fixture_count from locked_out) = 2,
    'a round freezes its day: the hidden and the test fixture stay out');
  perform pg_temp.check(
    (select count(*) from gamification.h2h_round_fixtures
      where round_id = 'c1010000-0000-4000-8000-0000000000d1') = 2,
    'locking twice freezes once');
  perform pg_temp.check(
    (select array_agg(round_no || ':' || day || ':' || (locked_at is not null)
                      || ':' || coalesce(approved_by, '-') order by round_no)
       from rounds_out)
      = array['1:2099-11-03:true:00000000-0101-4000-8101-000000000001',
              '2:2099-11-05:true:-'],
    'rounds read back in order with their approver and lock');
end $$;

-- ---------------------------------------------------------------------------
-- The sheet
-- ---------------------------------------------------------------------------
create temp table members_out as execute sheet_members('c1010000-0000-4000-8000-0000000000e1');
create temp table scores_out as execute sheet_scores('c1010000-0000-4000-8000-0000000000e1');
create temp table status_out as execute sheet_round_status('c1010000-0000-4000-8000-0000000000e1');
do $$
begin
  perform pg_temp.check(
    (select array_agg(slot::int order by slot) from members_out) = array[0, 1, 2, 3],
    'members in slot order, the suspended one left out');
  perform pg_temp.check(
    (select array_agg(user_id || ':' || round_no || ':' || points || ':' ||
                      exact_count || ':' || predicted_count order by user_id)
       from scores_out)
      = array['00000000-0101-4000-8101-000000000001:1:3:1:2',
              '00000000-0101-4000-8101-000000000002:1:0:0:1',
              '00000000-0101-4000-8101-000000000004:1:0:0:1'],
    'round scores: frozen fixtures only, absent members omitted');
  perform pg_temp.check(
    (select array_agg(round_no || ':' || fixtures || ':' || settled
                      order by round_no) from status_out)
      = array['1:2:1', '2:0:0'],
    'round 1 waits for one result; round 2 lost its fixture');
end $$;

-- f2's result and scores arrive: round 1 is settled.
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c1010000-0000-4000-8000-0000000000f2', 2, 2, '2099-11-03 20:00Z');
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a4', 1, 'correct_outcome', 1),
  ('c1010000-0000-4000-8000-0000000000f2', 'c1010000-0000-4000-8000-0000000000a5', 1, 'correct_outcome', 1);
create temp table status_after as execute sheet_round_status('c1010000-0000-4000-8000-0000000000e1');
create temp table scores_after as execute sheet_scores('c1010000-0000-4000-8000-0000000000e1');
do $$
begin
  perform pg_temp.check(
    (select fixtures = settled from status_after where round_no = 1),
    'round 1 is settled once every result is scored');
  perform pg_temp.check(
    (select points from scores_after
      where user_id = '00000000-0101-4000-8101-000000000001') = 6,
    'a member sums the round fixtures');
end $$;

-- ---------------------------------------------------------------------------
-- Activity, carry-over and the pilot
-- ---------------------------------------------------------------------------
create temp table active_out as execute sheet_active_days('2099-11-01');
create temp table order1_out as execute draw_active_order('2099-11-01', 1);
create temp table order2_out as execute draw_active_order('2099-11-01', 2);
do $$
begin
  perform pg_temp.check(
    (select active_days from active_out
      where user_id = '00000000-0101-4000-8101-000000000001') = 2
      and (select active_days from active_out
            where user_id = '00000000-0101-4000-8101-000000000002') = 1
      and not exists (select 1 from active_out
            where user_id = '00000000-0101-4000-8101-000000000003'),
    'active days are Riyadh days with a prediction');
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from order1_out)
      = array['00000000-0101-4000-8101-000000000001',
              '00000000-0101-4000-8101-000000000004',
              '00000000-0101-4000-8101-000000000002'],
    'the active order is best points first, the suspended left out');
  perform pg_temp.check(
    (select array_agg(user_id) from order2_out)
      = array['00000000-0101-4000-8101-000000000001'],
    'the activity threshold applies');
end $$;

insert into gamification.events (id, user_id, event_type, dedupe_key, occurred_at, payload, ref_type, ref_id) values
  (gen_random_uuid(), '00000000-0101-4000-8101-000000000002', 'h2h_league_finished',
   'h2h_league_finished:q2', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":2,"next_division":1,"outcome":"held"}',
   'h2h_league', 'c1010000-0000-4000-8000-0000000000e1'),
  (gen_random_uuid(), '00000000-0101-4000-8101-000000000001', 'h2h_league_finished',
   'h2h_league_finished:q1', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":1,"next_division":1,"outcome":"held"}',
   'h2h_league', 'c1010000-0000-4000-8000-0000000000e1'),
  (gen_random_uuid(), '00000000-0101-4000-8101-000000000003', 'h2h_league_finished',
   'h2h_league_finished:q3', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":4,"next_division":null,"outcome":"out"}',
   'h2h_league', 'c1010000-0000-4000-8000-0000000000e1'),
  (gen_random_uuid(), '00000000-0101-4000-8101-000000000005', 'h2h_league_finished',
   'h2h_league_finished:q5', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":3,"next_division":1,"outcome":"held"}',
   'h2h_league', 'c1010000-0000-4000-8000-0000000000e1');
create temp table carried_out as execute draw_carried('2099-11-01');
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id || ':' || next_division || ':' || rank
                      order by ctid) from carried_out)
      = array['00000000-0101-4000-8101-000000000001:1:1',
              '00000000-0101-4000-8101-000000000002:1:2'],
    'carried: drawn members only, by division and rank, the suspended out');
end $$;

insert into gamification.experiment_assignments (user_id, flag_key, variant) values
  ('00000000-0101-4000-8101-000000000004', 'h2h_pilot', 'pilot'),
  ('00000000-0101-4000-8101-000000000003', 'h2h_pilot', 'pilot'),
  ('00000000-0101-4000-8101-000000000005', 'h2h_pilot', 'pilot'),
  ('00000000-0101-4000-8101-000000000002', 'h2h_pilot', 'control');
create temp table pilot_out as execute draw_pilot_order('2099-11-01');
do $$
begin
  perform pg_temp.check(
    (select array_agg(user_id order by ctid) from pilot_out)
      = array['00000000-0101-4000-8101-000000000004',
              '00000000-0101-4000-8101-000000000003'],
    'the pilot is the pilot variant, best points first, a pilot with no '
    'points included, the suspended left out');
end $$;

-- ---------------------------------------------------------------------------
-- Closing
-- ---------------------------------------------------------------------------
create temp table next_before as execute league_next_unclosed;
execute league_mark_closed('2099-11-01', 4);
execute league_mark_closed('2099-11-01', 9);
create temp table next_after as execute league_next_unclosed;
create temp table closed_out as execute league_is_closed('2099-11-01');
do $$
begin
  perform pg_temp.check((select month from next_before) = '2099-11-01',
    'the oldest unclosed month is found');
  perform pg_temp.check((select month from next_after) is null,
    'a closed month is no longer unclosed');
  perform pg_temp.check(
    (select count(*) from closed_out) = 1
      and (select member_count from gamification.h2h_month_closures
            where month_start = '2099-11-01') = 4,
    'a month is closed once');
end $$;

rollback;
