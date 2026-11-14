-- Migration 0214 (absence in every group, the vacant seat and the waiting
-- list's seats, script 278) and the statements its adapters run:
-- PostgresH2hVacancyStore, the seat swaps of PostgresH2hSeatMoveStore
-- between neighbouring groups, PostgresH2hNewcomerStore's returning players
-- and freed waiting seats, PostgresH2hSheetReader.membersSql / scoresSql and
-- PostgresH2hLeagueStore.seatSql. The PREPARE statements are the adapters'
-- SQL constants, text for text, with @name::type turned into $n::type. Then
-- the owner's files in supabase/queries: the moves, the absence check, the
-- freeze and the unfreeze. November 2026 is read and guarded as before.
-- Rolled back at the end.
\set ON_ERROR_STOP on
\set movements_sql `sed -e 's/--.*$//' -e "s/'%علوش%'/'%Absence 214 21%'/" supabase/queries/h2h_movements.sql | tr '\n' ' ' | sed -e 's/; *$//'`
\set check_sql `sed -e 's/--.*$//' supabase/queries/h2h_absence_check.sql | tr '\n' ' ' | sed -e 's/; *$//'`
\set freeze_sql `sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/queries/h2h_absence_freeze.sql`
\set unfreeze_sql `sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/queries/h2h_absence_unfreeze.sql`
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

-- Ids: player NN is 00000000-0214-4000-8214-0000000000NN.
create function pg_temp.u(n integer) returns uuid language sql immutable as $$
  select ('00000000-0214-4000-8214-0000000000' || lpad(n::text, 2, '0'))::uuid
$$;

-- PostgresH2hLeagueStore.insertGroupSql
PREPARE league_insert_group(uuid, date, smallint, smallint, smallint) AS
INSERT INTO gamification.h2h_leagues
  (id, month_start, division, group_index, capacity)
VALUES ($1::uuid, $2::date, $3::smallint,
        $4::smallint, $5::smallint);

-- PostgresH2hLeagueStore.insertSeatSql
PREPARE league_insert_seat(uuid, date, uuid, smallint) AS
INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES ($1::uuid, $2::date, $3::uuid, $4::smallint);

-- PostgresH2hLeagueStore.insertWaitingSql
PREPARE league_insert_waiting(uuid, date) AS
INSERT INTO gamification.h2h_waiting_groups (league_id, month_start)
VALUES ($1::uuid, $2::date);

-- PostgresH2hLeagueStore.seatSql
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
  UNION ALL
  SELECT NULL::uuid, NULL::smallint, v.created_at, v.from_round
  FROM gamification.h2h_seat_vacancies v
  WHERE v.out_user = $1::uuid
    AND v.month_start = $2::date
  UNION ALL
  SELECT v.league_id, v.slot, f.created_at, f.from_round
  FROM gamification.h2h_vacancy_fills f
  JOIN gamification.h2h_seat_vacancies v ON v.id = f.vacancy_id
  WHERE f.in_user = $1::uuid
    AND f.month_start = $2::date
  UNION ALL
  SELECT ws.league_id, ws.slot, ws.created_at, 1
  FROM gamification.h2h_waiting_seats ws
  WHERE ws.user_id = $1::uuid
    AND ws.month_start = $2::date
),
seat AS (
  SELECT * FROM held
  ORDER BY CASE WHEN $2::date < DATE '2026-12-01' THEN from_round
                ELSE 0 END DESC,
           joined_at DESC,
           from_round DESC
  LIMIT 1
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

-- PostgresH2hNewcomerStore.newcomersSql
PREPARE nc_newcomers(date) AS
SELECT p.user_id::text AS user_id, min(fp.submitted_at) AS first_at
FROM gamification.h2h_months mo
JOIN competition.fixture_schedules fs
  ON fs.kickoff_at >= mo.drawn_at
JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fs.fixture_id AND fp.submitted_at >= mo.drawn_at
JOIN competition.participants p ON p.id = fp.participant_id
JOIN identity.users u
  ON u.id = p.user_id AND u.status <> 'suspended' AND u.hidden_at IS NULL
WHERE mo.month_start = $1::date
  AND NOT mo.is_pilot
  AND fs.hidden_at IS NULL
  AND NOT fs.is_test
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_waiting_seats ws
    WHERE ws.month_start = mo.month_start AND ws.user_id = p.user_id
  )
  AND (
    NOT EXISTS (
      SELECT 1 FROM gamification.h2h_league_members m
      WHERE m.month_start = mo.month_start AND m.user_id = p.user_id
    )
    OR EXISTS (
      SELECT 1 FROM gamification.h2h_seat_vacancies v
      WHERE v.month_start = mo.month_start
        AND v.out_user = p.user_id
        AND fp.submitted_at > v.created_at
    )
  )
GROUP BY p.user_id
ORDER BY min(fp.submitted_at), p.user_id;

-- PostgresH2hNewcomerStore.waitingSql
PREPARE nc_waiting(date) AS
SELECT w.league_id::text AS league_id,
       l.group_index     AS group_index,
       (SELECT count(*)
          FROM gamification.h2h_waiting_holders(w.league_id))::integer
                         AS seated,
       (SELECT min(g.n)
          FROM generate_series(0, l.capacity - 1) AS g(n)
         WHERE NOT EXISTS (
           SELECT 1 FROM gamification.h2h_waiting_holders(w.league_id) h
           WHERE h.slot = g.n
         ))::integer     AS free_slot
FROM gamification.h2h_waiting_groups w
JOIN gamification.h2h_leagues l ON l.id = w.league_id
WHERE w.month_start = $1::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_group_starts s
    WHERE s.league_id = w.league_id
  )
ORDER BY l.group_index
LIMIT 1;

-- PostgresH2hNewcomerStore.newcomerSql
PREPARE nc_newcomer(date, uuid, uuid) AS
INSERT INTO gamification.h2h_newcomer_seatings
  (month_start, user_id, league_id)
VALUES ($1::date, $2::uuid, $3::uuid);

-- PostgresH2hNewcomerStore.seatKindSql
PREPARE nc_seat_kind(date, uuid, uuid, smallint) AS
SELECT EXISTS (
         SELECT 1 FROM gamification.h2h_seat_vacancies v
         WHERE v.month_start = $1::date AND v.out_user = $2::uuid
       ) AS is_return,
       EXISTS (
         SELECT 1 FROM gamification.h2h_league_members m
         WHERE m.league_id = $3::uuid AND m.slot = $4::smallint
       ) AS slot_used;

-- PostgresH2hNewcomerStore.waitingSeatSql
PREPARE nc_waiting_seat(date, uuid, uuid, smallint, text) AS
INSERT INTO gamification.h2h_waiting_seats
  (month_start, user_id, league_id, slot, reason)
VALUES ($1::date, $2::uuid, $3::uuid, $4::smallint,
        $5);

-- PostgresH2hNewcomerStore.startSql
PREPARE nc_start(uuid, smallint) AS
INSERT INTO gamification.h2h_group_starts (league_id, from_round)
VALUES ($1::uuid, $2::smallint);

-- PostgresH2hSheetReader.membersSql
PREPARE sheet_members(uuid) AS
WITH seats AS (
  SELECT m.user_id, m.slot, m.joined_at, 1 AS from_round
  FROM gamification.h2h_league_members m
  WHERE m.league_id = $1::uuid
    AND NOT EXISTS (
      SELECT 1 FROM gamification.h2h_waiting_groups w0
      WHERE w0.league_id = m.league_id
    )
  UNION ALL
  SELECT h.user_id, h.slot, h.held_at, 1
  FROM gamification.h2h_waiting_groups w1
  CROSS JOIN LATERAL gamification.h2h_waiting_holders(w1.league_id) h
  WHERE w1.league_id = $1::uuid
  UNION ALL
  SELECT mv.in_user, mv.elite_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.elite_league_id = $1::uuid
  UNION ALL
  SELECT mv.out_user, mv.extra_slot, mv.created_at, mv.from_round
  FROM gamification.h2h_seat_moves mv
  WHERE mv.extra_league_id = $1::uuid
  UNION ALL
  SELECT NULL::uuid, v.slot, v.created_at, v.from_round
  FROM gamification.h2h_seat_vacancies v
  WHERE v.league_id = $1::uuid
  UNION ALL
  SELECT f.in_user, v.slot, f.created_at, f.from_round
  FROM gamification.h2h_vacancy_fills f
  JOIN gamification.h2h_seat_vacancies v ON v.id = f.vacancy_id
  WHERE v.league_id = $1::uuid
),
held AS (
  SELECT s.user_id, s.slot, s.joined_at, s.from_round,
         lead(s.from_round) OVER (
           PARTITION BY s.slot ORDER BY s.from_round, s.joined_at
         ) - 1 AS until_round
  FROM seats s
),
gate AS (
  SELECT CASE WHEN w.league_id IS NULL THEN 1
              ELSE COALESCE(gs.from_round, 20)
         END AS first_round
  FROM (SELECT $1::uuid AS league_id) g
  LEFT JOIN gamification.h2h_waiting_groups w ON w.league_id = g.league_id
  LEFT JOIN gamification.h2h_group_starts gs ON gs.league_id = g.league_id
)
SELECT h.user_id::text AS user_id,
       h.slot          AS slot,
       h.joined_at     AS joined_at,
       GREATEST(h.from_round, gate.first_round) AS from_round,
       h.until_round   AS until_round
FROM held h
CROSS JOIN gate
JOIN identity.users u ON u.id = h.user_id AND u.status <> 'suspended' AND u.hidden_at IS NULL
ORDER BY h.slot, h.from_round;

-- PostgresH2hSheetReader.scoresSql
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
    UNION
    SELECT ws.user_id
    FROM gamification.h2h_waiting_seats ws
    WHERE ws.league_id = $1::uuid
    UNION
    SELECT f.in_user
    FROM gamification.h2h_vacancy_fills f
    JOIN gamification.h2h_seat_vacancies v ON v.id = f.vacancy_id
    WHERE v.league_id = $1::uuid
  ) x
  JOIN identity.users u ON u.id = x.user_id AND u.status <> 'suspended' AND u.hidden_at IS NULL
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

-- PostgresH2hSeatMoveStore.candidateFactsSql
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
                                                                  AS active_days,
       count(DISTINCT fx.fixture_id) FILTER (
         WHERE fp.id IS NOT NULL)::integer                        AS predicted,
       count(s.fixture_id) FILTER (
         WHERE s.grade = 'correct_outcome')::integer              AS outcomes
FROM who w
LEFT JOIN competition.participants p ON p.user_id = w.user_id
LEFT JOIN fx ON fx.season_id = p.season_id
LEFT JOIN prediction.fixture_predictions fp
  ON fp.fixture_id = fx.fixture_id AND fp.participant_id = p.id
LEFT JOIN scoring.fixture_scores s
  ON s.fixture_id = fx.fixture_id AND s.participant_id = p.id
GROUP BY w.user_id;

-- PostgresH2hSeatMoveStore.insertMoveSql
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

-- PostgresH2hVacancyStore.vacanciesSql
PREPARE vc_vacancies(date) AS
SELECT v.id::text        AS id,
       v.league_id::text AS league_id,
       v.slot            AS slot,
       v.out_user::text  AS out_user,
       v.from_round      AS from_round,
       f.in_user::text   AS in_user,
       f.from_round      AS filled_from
FROM gamification.h2h_seat_vacancies v
LEFT JOIN gamification.h2h_vacancy_fills f ON f.vacancy_id = v.id
WHERE v.month_start = $1::date
ORDER BY v.created_at, v.id;

-- PostgresH2hVacancyStore.insertVacancySql
PREPARE vc_vacate(uuid, date, uuid, smallint, uuid, smallint, jsonb) AS
INSERT INTO gamification.h2h_seat_vacancies
  (id, month_start, league_id, slot, out_user, from_round, kind,
   absent_rounds)
VALUES ($1::uuid, $2::date, $3::uuid, $4::smallint,
        $5::uuid, $6::smallint, 'absence',
        $7::jsonb);

-- PostgresH2hVacancyStore.insertFillSql
PREPARE vc_fill(uuid, date, uuid, smallint, uuid, smallint, jsonb) AS
INSERT INTO gamification.h2h_vacancy_fills
  (vacancy_id, month_start, in_user, from_round, from_league_id, from_slot,
   candidate)
VALUES ($1::uuid, $2::date, $3::uuid,
        $4::smallint, $5::uuid, $6::smallint,
        $7::jsonb);

-- ---------------------------------------------------------------------------
-- The world, December 2098 (December rules): المجموعة 1 (E1) players 01..04,
-- 5 (G5) 11..14, 6 (G6) 21..24 the last that plays, 7 (W7) waiting with
-- 31..33. Rounds 1 to 5 started. November 2026 beside it, as before.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select pg_temp.u(i), 'a' || i || '@t.io', now() from generate_series(1, 99) i;
insert into identity.users (id, email, display_name)
select pg_temp.u(i), 'a' || i || '@t.io', 'Absence 214 ' || lpad(i::text, 2, '0')
from generate_series(1, 99) i;

insert into competition.competitions (id, name, format, visibility) values
  ('c2140000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2140000-0000-4000-8000-000000000010', 'c2140000-0000-4000-8000-000000000001',
   '12/2098', '2024-12-31 21:00Z', '2099-12-31 21:00Z');
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c2140000-0000-4000-8000-0000000a' || lpad(i::text, 4, '0'))::uuid,
       'c2140000-0000-4000-8000-000000000010', pg_temp.u(i), '2025-01-01'
from generate_series(1, 99) i;
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c2140000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-01-02 18:00Z', false);
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c2140000-0000-4000-8000-000000000010', 'c2140000-0000-4000-8000-0000000000f1', 1);

insert into gamification.h2h_months (month_start, is_pilot, seated_count, drawn_at)
values ('2026-11-01', false, 5, '2026-11-01 00:00Z'),
       ('2098-12-01', false, 15, '2025-01-01 00:00Z');

execute league_insert_group('c2140000-0000-4000-8000-0000000000e1', '2098-12-01', 1, 0, 20);
execute league_insert_group('c2140000-0000-4000-8000-0000000000e5', '2098-12-01', 2, 0, 20);
execute league_insert_group('c2140000-0000-4000-8000-0000000000e6', '2098-12-01', 2, 1, 20);
execute league_insert_group('c2140000-0000-4000-8000-0000000000e7', '2098-12-01', 2, 2, 20);
execute league_insert_waiting('c2140000-0000-4000-8000-0000000000e7', '2098-12-01');
do $$
declare i integer;
begin
  for i in 0..3 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2140000-0000-4000-8000-0000000000e1', '2098-12-01', pg_temp.u(1 + i), i);
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2140000-0000-4000-8000-0000000000e5', '2098-12-01', pg_temp.u(11 + i), i);
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2140000-0000-4000-8000-0000000000e6', '2098-12-01', pg_temp.u(21 + i), i);
  end loop;
  for i in 0..2 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2140000-0000-4000-8000-0000000000e7', '2098-12-01', pg_temp.u(31 + i), i);
    execute format('execute nc_newcomer(%L, %L, %L)',
      '2098-12-01', pg_temp.u(31 + i), 'c2140000-0000-4000-8000-0000000000e7');
  end loop;
end $$;

insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2140000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2098-12-01', n, ('2098-12-01'::date + (n - 1)), 6
from generate_series(1, 9) n;
insert into gamification.h2h_round_locks (round_id, fixture_count)
select ('c2140000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 6
from generate_series(1, 5) n;

-- November 2026: المجموعة 1 (players 91, 92), 5 (93) and 6 (94, 95).
execute league_insert_group('c2140000-0000-4000-8000-0000000000b1', '2026-11-01', 1, 0, 20);
execute league_insert_group('c2140000-0000-4000-8000-0000000000b5', '2026-11-01', 2, 0, 20);
execute league_insert_group('c2140000-0000-4000-8000-0000000000b6', '2026-11-01', 2, 1, 20);
select pg_temp.u(91) as u into temp _nov;
do $$
begin
  execute format('execute league_insert_seat(%L, %L, %L, 0)', 'c2140000-0000-4000-8000-0000000000b1', '2026-11-01', pg_temp.u(91));
  execute format('execute league_insert_seat(%L, %L, %L, 1)', 'c2140000-0000-4000-8000-0000000000b1', '2026-11-01', pg_temp.u(92));
  execute format('execute league_insert_seat(%L, %L, %L, 0)', 'c2140000-0000-4000-8000-0000000000b5', '2026-11-01', pg_temp.u(93));
  execute format('execute league_insert_seat(%L, %L, %L, 0)', 'c2140000-0000-4000-8000-0000000000b6', '2026-11-01', pg_temp.u(94));
  execute format('execute league_insert_seat(%L, %L, %L, 1)', 'c2140000-0000-4000-8000-0000000000b6', '2026-11-01', pg_temp.u(95));
end $$;

-- ---------------------------------------------------------------------------
-- November: an elite seat for any extra seat, as 0189; no vacancy
-- ---------------------------------------------------------------------------
create temp table nov_before as execute sheet_members('c2140000-0000-4000-8000-0000000000b6');
do $$
begin
  execute format('execute mv_insert(%L, %L, 3, %L, %L, %L, %L, 0, %L, 0, %L, %L, null, null)',
    'c2140000-0000-4000-8000-00000000aa01', '2026-11-01', 'absence', pg_temp.u(91), pg_temp.u(94),
    'c2140000-0000-4000-8000-0000000000b1', 'c2140000-0000-4000-8000-0000000000b6', '[]', '{}');
end $$;
select pg_temp.check(true, 'November: المجموعة 1 swaps with المجموعة 6, as before');
create temp table nov_seat as execute league_seat(pg_temp.u(91), '2026-11-01');
select pg_temp.check((select league_id = 'c2140000-0000-4000-8000-0000000000b6' and slot = 0 from nov_seat),
  'November: the seat is read by the round, as before');
create temp table nov_sheet as execute sheet_members('c2140000-0000-4000-8000-0000000000b6');
select pg_temp.check(
  (select array_agg(right(user_id, 2) || '@' || slot || ':' || from_round || '-' || coalesce(until_round::text, '') order by slot, from_round) from nov_sheet)
  = array['94@0:1-2', '91@0:3-', '95@1:1-'],
  'November: the sheet reads each holder with his rounds, as before');
select pg_temp.refused(format($q$execute vc_vacate('c2140000-0000-4000-8000-00000000bb01', '2026-11-01', 'c2140000-0000-4000-8000-0000000000b5', 0, %L, 3, '[]')$q$, pg_temp.u(93)),
  'h2h_seat_vacancies_december_on', 'November: no seat is left vacant');

-- ---------------------------------------------------------------------------
-- December: a swap is between a group and the one below it
-- ---------------------------------------------------------------------------
create function pg_temp.swap(id text, from_round integer, out_user integer, in_user integer,
  upper text, upper_slot integer, lower text, lower_slot integer) returns text
language sql as $$
  select format('execute mv_insert(%L, %L, %s, %L, %L, %L, %L, %s, %L, %s, %L, %L, null, null)',
    'c2140000-0000-4000-8000-0000000000' || id, '2098-12-01', from_round, 'absence',
    pg_temp.u(out_user), pg_temp.u(in_user),
    'c2140000-0000-4000-8000-0000000000' || upper, upper_slot,
    'c2140000-0000-4000-8000-0000000000' || lower, lower_slot, '[]', '{}')
$$;

select pg_temp.refused(pg_temp.swap('a1', 6, 1, 21, 'e1', 0, 'e6', 0),
  'h2h_seat_moves_neighbours', 'المجموعة 1 never swaps with 6');
select pg_temp.refused(pg_temp.swap('a2', 6, 21, 31, 'e6', 0, 'e7', 0),
  'h2h_seat_moves_started', 'a waiting group takes no swap');
select pg_temp.refused(pg_temp.swap('a3', 6, 2, 12, 'e1', 0, 'e5', 1),
  'h2h_seat_moves_holders', 'a swap leaves the seat its player holds');
select pg_temp.refused(pg_temp.swap('a4', 6, 11, 1, 'e5', 0, 'e1', 0),
  'h2h_seat_moves_divisions', 'never a seat for the seat above it');
do $$ begin execute pg_temp.swap('b1', 6, 1, 12, 'e1', 0, 'e5', 1); end $$;
do $$ begin execute pg_temp.swap('b2', 6, 11, 23, 'e5', 0, 'e6', 2); end $$;
select pg_temp.check(true, 'المجموعة 1 to 5 and 5 to 6, before round 6');
select pg_temp.refused(pg_temp.swap('a5', 6, 12, 13, 'e1', 0, 'e5', 2),
  'h2h_one_move_per_round', 'a player who came up moves no more before the same round');
select pg_temp.refused(pg_temp.swap('a6', 7, 2, 1, 'e1', 1, 'e5', 1),
  'h2h_seat_moves_no_return', 'a relegated player never comes back up');

-- ---------------------------------------------------------------------------
-- December: the last group's seat left for the waiting list
-- ---------------------------------------------------------------------------
create function pg_temp.vacate(id text, league text, slot integer, out_user integer, from_round integer)
returns text language sql as $$
  select format('execute vc_vacate(%L, %L, %L, %s, %L, %s, %L)',
    'c2140000-0000-4000-8000-0000000000' || id, '2098-12-01',
    'c2140000-0000-4000-8000-0000000000' || league, slot, pg_temp.u(out_user), from_round,
    '[{"month":"2098-12-01","round":3},{"month":"2098-12-01","round":4},{"month":"2098-12-01","round":5}]')
$$;
create function pg_temp.fill(vacancy text, in_user integer, from_round integer, from_league text, from_slot integer)
returns text language sql as $$
  select format('execute vc_fill(%L, %L, %L, %s, %L, %s, %L)',
    'c2140000-0000-4000-8000-0000000000' || vacancy, '2098-12-01', pg_temp.u(in_user), from_round,
    'c2140000-0000-4000-8000-0000000000' || from_league, from_slot, '{"predicted": 9}')
$$;

select pg_temp.refused(pg_temp.vacate('c0', 'e7', 0, 31, 6),
  'h2h_seat_vacancies_started', 'a waiting group leaves no seat vacant');
select pg_temp.refused(pg_temp.vacate('c0', 'e6', 0, 22, 6),
  'h2h_seat_vacancies_holder', 'a player leaves only the seat he holds');
select pg_temp.refused(pg_temp.vacate('c0', 'e6', 1, 22, 5),
  'h2h_seat_vacancies_round_not_started', 'never from a round that has started');
select pg_temp.refused(pg_temp.vacate('c0', 'e5', 1, 1, 7),
  'h2h_one_relegation_a_month', 'one relegation a month');
select pg_temp.refused(pg_temp.vacate('c0', 'e5', 0, 23, 6),
  'h2h_one_move_per_round', 'one move before a round');

-- Player 21 leaves, player 31 of the waiting list takes the seat: one go.
do $$
begin
  execute pg_temp.vacate('c1', 'e6', 0, 21, 6);
  execute pg_temp.fill('c1', 31, 6, 'e7', 0);
end $$;
-- Player 22 leaves with a fill the database refuses: neither is stored.
do $$
begin
  begin
    execute pg_temp.vacate('c2', 'e6', 1, 22, 6);
    execute pg_temp.fill('c2', 99, 6, 'e7', 1);
  exception when others then
    raise notice 'refused together: %', sqlerrm;
  end;
end $$;
select pg_temp.check(
  not exists (select 1 from gamification.h2h_seat_vacancies where out_user = pg_temp.u(22))
  and gamification.h2h_seat_holder('c2140000-0000-4000-8000-0000000000e6', 1::smallint) = pg_temp.u(22),
  'a refused fill leaves the player in his seat, with no vacancy');
select pg_temp.refused(pg_temp.fill('c1', 32, 6, 'e7', 1),
  'h2h_vacancy_fills_vacant', 'a seat is filled once: it is not vacant any more');
-- Player 22 leaves; nobody qualifies: the seat stays vacant.
do $$ begin execute pg_temp.vacate('c2', 'e6', 1, 22, 6); end $$;
select pg_temp.refused(pg_temp.fill('c2', 32, 5, 'e7', 1),
  'h2h_vacancy_fills_after_vacancy', 'a fill never before its vacancy');
select pg_temp.refused(pg_temp.fill('c2', 33, 6, 'e7', 1),
  'h2h_vacancy_fills_from_holder', 'a fill comes from the waiting seat its player holds');

create temp table g6_vacant as execute sheet_members('c2140000-0000-4000-8000-0000000000e6');
create temp table w7_left as execute nc_waiting('2098-12-01');
create temp table seat_21 as execute league_seat(pg_temp.u(21), '2098-12-01');
create temp table seat_31 as execute league_seat(pg_temp.u(31), '2098-12-01');
create temp table seat_11 as execute league_seat(pg_temp.u(11), '2098-12-01');
select pg_temp.check(
  (select array_agg(right(user_id, 2) || '@' || slot || ':' || from_round || '-' || coalesce(until_round::text, '') order by slot, from_round) from g6_vacant)
  = array['21@0:1-5', '31@0:6-', '22@1:1-5', '23@2:1-5', '11@2:6-', '24@3:1-'],
  'المجموعة 6: 21 until round 5 then 31; 22 until round 5, then vacant');
select pg_temp.check((select seated from w7_left) = 2 and (select free_slot from w7_left) = 0,
  'the filler left the waiting group: two hold its seats, seat 0 is free');
select pg_temp.check((select count(*) from seat_21) = 0,
  'the player who left holds no seat: he is on the waiting list');
select pg_temp.check((select league_id = 'c2140000-0000-4000-8000-0000000000e6' and slot = 0 from seat_31)
  and (select league_id = 'c2140000-0000-4000-8000-0000000000e6' and slot = 2 from seat_11),
  'the filler holds the vacant seat; the relegated player the seat he moved to');

-- Round 6 starts; the vacant seat is filled before round 7.
insert into gamification.h2h_round_locks (round_id, fixture_count)
values ('c2140000-0000-4000-8000-000000000106', 6);
select pg_temp.refused(pg_temp.fill('c2', 32, 6, 'e7', 1),
  'h2h_vacancy_fills_round_not_started', 'a fill never from a round that has started');
do $$ begin execute pg_temp.fill('c2', 32, 7, 'e7', 1); end $$;
create temp table g6_filled as execute sheet_members('c2140000-0000-4000-8000-0000000000e6');
select pg_temp.check(
  (select array_agg(right(user_id, 2) || ':' || from_round || '-' || coalesce(until_round::text, '') order by from_round) from g6_filled where slot = 1)
  = array['22:1-5', '32:7-'],
  'the seat was vacant in round 6, then held by 32 from round 7');
select pg_temp.check(
  (select count(*) from (select * from g6_vacant where slot <> 1 except select * from g6_filled where slot <> 1) d) = 0,
  'the other seats read exactly as before the fill');

do $$ begin execute pg_temp.vacate('c4', 'e6', 3, 24, 7); end $$;
select pg_temp.refused(pg_temp.fill('c4', 13, 7, 'e5', 2),
  'h2h_vacancy_fills_from_waiting', 'a vacant seat is filled from the waiting list only');

-- ---------------------------------------------------------------------------
-- Back from absence, and the waiting seats taken again
-- ---------------------------------------------------------------------------
-- 21 predicts after he left; 24 predicted before he left (2025); 41 and 42
-- are new.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), 'c2140000-0000-4000-8000-0000000000f1'::uuid,
       ('c2140000-0000-4000-8000-0000000a' || lpad(i::text, 4, '0'))::uuid, 1, 0, false,
       case when i = 24 then timestamptz '2025-06-01 10:00Z'
            else timestamptz '2099-01-01 10:00Z' + (i || ' minutes')::interval end
from unnest(array[21, 24, 41, 42]) i;
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c2140000-0000-4000-8000-0000000000f1', 'c2140000-0000-4000-8000-0000000a0021', 1, 'correct_outcome', 1);

create temp table back_out as execute nc_newcomers('2098-12-01');
select pg_temp.check(
  (select array_agg(right(user_id, 2) order by first_at) from back_out) = array['21', '41', '42'],
  'the returning player and the new ones, first prediction first; not one who predicted before he left');

create temp table kind_21 as execute nc_seat_kind('2098-12-01', pg_temp.u(21), 'c2140000-0000-4000-8000-0000000000e7', 0);
select pg_temp.check((select is_return and slot_used from kind_21), 'seat 0: a return, on a seat used before');
do $$ begin execute format('execute nc_waiting_seat(%L, %L, %L, 0, %L)', '2098-12-01', pg_temp.u(21), 'c2140000-0000-4000-8000-0000000000e7', 'return'); end $$;
create temp table kind_41 as execute nc_seat_kind('2098-12-01', pg_temp.u(41), 'c2140000-0000-4000-8000-0000000000e7', 1);
select pg_temp.check((select not is_return and slot_used from kind_41), 'seat 1: a new player on the seat a filler left');
do $$ begin execute format('execute nc_waiting_seat(%L, %L, %L, 1, %L)', '2098-12-01', pg_temp.u(41), 'c2140000-0000-4000-8000-0000000000e7', 'newcomer'); end $$;
create temp table kind_42 as execute nc_seat_kind('2098-12-01', pg_temp.u(42), 'c2140000-0000-4000-8000-0000000000e7', 3);
select pg_temp.check((select not is_return and not slot_used from kind_42), 'seat 3: a new seat, as in 0213');
do $$
begin
  execute format('execute league_insert_seat(%L, %L, %L, 3)', 'c2140000-0000-4000-8000-0000000000e7', '2098-12-01', pg_temp.u(42));
  execute format('execute nc_newcomer(%L, %L, %L)', '2098-12-01', pg_temp.u(42), 'c2140000-0000-4000-8000-0000000000e7');
end $$;

select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e7', 0, 'newcomer')$q$, pg_temp.u(43)),
  'h2h_waiting_slot_free', 'a waiting seat held is never taken');
select pg_temp.refused(format($q$execute league_insert_seat('c2140000-0000-4000-8000-0000000000e7', '2098-12-01', %L, 1)$q$, pg_temp.u(43)),
  'h2h_waiting_slot_free', 'nor by a new seat row');
select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e7', 4, 'return')$q$, pg_temp.u(43)),
  'h2h_waiting_seats_return_after_vacancy', 'a return only after leaving a seat');
select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e7', 4, 'newcomer')$q$, pg_temp.u(2)),
  'h2h_waiting_seats_newcomer_unseated', 'a player with a seat is no new player');
select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e7', 5, 'newcomer')$q$, pg_temp.u(41)),
  'h2h_waiting_seats_pkey', 'one waiting seat a month');
select pg_temp.refused(pg_temp.fill('c4', 21, 7, 'e7', 0),
  'h2h_no_return_in_month', 'a player who left a seat never takes a vacant one in the month');

create temp table again_out as execute nc_newcomers('2098-12-01');
create temp table seat_21b as execute league_seat(pg_temp.u(21), '2098-12-01');
create temp table seat_41 as execute league_seat(pg_temp.u(41), '2098-12-01');
select pg_temp.check((select count(*) from again_out) = 0, 'nobody is read twice');
select pg_temp.check(
  (select league_id = 'c2140000-0000-4000-8000-0000000000e7' and slot = 0 from seat_21b)
  and (select league_id = 'c2140000-0000-4000-8000-0000000000e7' and slot = 1 from seat_41),
  'the returning player and the new one hold their waiting seats');

-- The start counts the holders: 16 more seat rows make 21 rows ever
-- taken, but 19 holders: no start until the twentieth.
do $$
declare i integer;
begin
  for i in 4..18 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)', 'c2140000-0000-4000-8000-0000000000e7', '2098-12-01', pg_temp.u(46 + i), i);
  end loop;
end $$;
select pg_temp.check(
  (select count(*) from gamification.h2h_league_members where league_id = 'c2140000-0000-4000-8000-0000000000e7')
  + (select count(*) from gamification.h2h_waiting_seats where league_id = 'c2140000-0000-4000-8000-0000000000e7') = 21
  and (select count(*) from gamification.h2h_waiting_holders('c2140000-0000-4000-8000-0000000000e7')) = 19,
  'twenty-one seat rows, nineteen holders');
select pg_temp.refused($q$execute nc_start('c2140000-0000-4000-8000-0000000000e7', 7)$q$,
  'h2h_group_starts_twenty', 'nobody counted twice: no start with nineteen');
do $$ begin execute format('execute league_insert_seat(%L, %L, %L, 19)', 'c2140000-0000-4000-8000-0000000000e7', '2098-12-01', pg_temp.u(65)); end $$;
execute nc_start('c2140000-0000-4000-8000-0000000000e7', 7);
create temp table w7_started as execute sheet_members('c2140000-0000-4000-8000-0000000000e7');
select pg_temp.check(
  (select count(*) from w7_started) = 20
  and (select bool_and(from_round = 7) from w7_started)
  and exists (select 1 from w7_started where right(user_id, 2) = '21' and slot = 0)
  and exists (select 1 from w7_started where right(user_id, 2) = '41' and slot = 1)
  and not exists (select 1 from w7_started where right(user_id, 2) in ('31', '32')),
  'the started group plays its twenty holders from round 7, not the fillers who left');
select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e7', 2, 'newcomer')$q$, pg_temp.u(43)),
  'h2h_waiting_seats_waiting_only', 'no waiting seat in a group that started');

-- ---------------------------------------------------------------------------
-- What the adapters read back
-- ---------------------------------------------------------------------------
create temp table vac_out as execute vc_vacancies('2098-12-01');
select pg_temp.check(
  (select array_agg(right(out_user, 2) || ':' || coalesce(right(in_user, 2), '-') || ':' || coalesce(filled_from::text, '-') order by ctid) from vac_out)
  = array['21:31:6', '22:32:7', '24:-:-'],
  'the vacancies, oldest first, with their fills');
create temp table facts_out as execute mv_facts('2099-01-10', 30, pg_temp.u(21)::text);
select pg_temp.check((select predicted = 1 and outcomes = 1 from facts_out),
  'the facts read predictions and right outcomes');
create temp table scores_g6 as execute sheet_scores('c2140000-0000-4000-8000-0000000000e6');
select pg_temp.check((select count(*) from scores_g6) >= 0, 'the scores of a group with vacancies and fills are read without error');

-- ---------------------------------------------------------------------------
-- The record: every move with its reason
-- ---------------------------------------------------------------------------
select pg_temp.check((select count(*) from gamification.h2h_movements
  where month_start = '2098-12-01' and kind = 'seat_vacated') = 3, 'three seats vacated');
select pg_temp.check((select count(*) from gamification.h2h_movements
  where month_start = '2098-12-01' and kind = 'vacancy_filled') = 2, 'two vacant seats filled');
select pg_temp.check((select string_agg(reason, ',' order by reason) from gamification.h2h_movements
  where month_start = '2098-12-01' and kind = 'waiting_seat') = 'newcomer,return', 'a return and a new player on a freed seat');
create temp table moves_out as select * from (:movements_sql) q;
select pg_temp.check(
  (select string_agg(what || ':' || coalesce(why, '-'), ',' order by what) from moves_out where player = 'Absence 214 21')
  = 'group_start:-,seat:draw,seat_vacated:absence,waiting_seat:return',
  'the owner''s query: 21 drawn, left for absence, back, his group started');
create temp table check_out as select * from (:check_sql) q;
select pg_temp.check((select count(*) from check_out where month = '2098-12') = 3
  and (select filled_by from check_out where left_by = 'Absence 214 21') = 'Absence 214 31'
  and (select came_back from check_out where left_by = 'Absence 214 21')
  and (select filled_by is null from check_out where left_by = 'Absence 214 24'),
  'the owner''s check: each vacancy, its fill, who came back');

-- ---------------------------------------------------------------------------
-- The freeze: nothing vacated, filled or retaken; nothing lost; undone
-- ---------------------------------------------------------------------------
-- The next waiting group opens, with player 80.
execute league_insert_group('c2140000-0000-4000-8000-0000000000e8', '2098-12-01', 2, 3, 20);
execute league_insert_waiting('c2140000-0000-4000-8000-0000000000e8', '2098-12-01');
do $$
begin
  execute format('execute league_insert_seat(%L, %L, %L, 0)', 'c2140000-0000-4000-8000-0000000000e8', '2098-12-01', pg_temp.u(80));
  execute format('execute nc_newcomer(%L, %L, %L)', '2098-12-01', pg_temp.u(80), 'c2140000-0000-4000-8000-0000000000e8');
end $$;
:freeze_sql
:freeze_sql
select pg_temp.refused(pg_temp.vacate('c5', 'e7', 2, 33, 8),
  'h2h_seat_vacancies_frozen', 'frozen: no seat left vacant');
select pg_temp.refused(pg_temp.fill('c4', 80, 8, 'e8', 0),
  'h2h_vacancy_fills_frozen', 'frozen: no seat filled');
select pg_temp.refused(format($q$execute nc_waiting_seat('2098-12-01', %L, 'c2140000-0000-4000-8000-0000000000e8', 1, 'newcomer')$q$, pg_temp.u(81)),
  'h2h_waiting_seats_frozen', 'frozen: no waiting seat taken again');
create temp table check_frozen as select * from (:check_sql) q;
select pg_temp.check((select bool_and(frozen) from check_frozen) and (select count(*) from check_frozen) = 3,
  'the check reads every vacancy, frozen');
:unfreeze_sql
:unfreeze_sql
do $$ begin execute pg_temp.vacate('c5', 'e7', 2, 33, 8); end $$;
do $$ begin execute pg_temp.fill('c4', 80, 8, 'e8', 0); end $$;
select pg_temp.check((select count(*) from gamification.h2h_seat_vacancies where month_start = '2098-12-01') = 4
  and (select count(*) from gamification.h2h_vacancy_fills where month_start = '2098-12-01') = 3,
  'unfrozen: a seat of the started group is left, a vacant one filled');

-- ---------------------------------------------------------------------------
-- Append-only; server-only
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$update gamification.h2h_seat_vacancies set from_round = 9$q$, null,
  'a vacancy is never changed');
select pg_temp.refused($q$delete from gamification.h2h_vacancy_fills$q$, null,
  'a fill is never deleted');
select pg_temp.refused($q$delete from gamification.h2h_waiting_seats$q$, null,
  'a waiting seat is never deleted');
select pg_temp.check(
  (select bool_and(relrowsecurity) from pg_class
    where relnamespace = 'gamification'::regnamespace
      and relname in ('h2h_seat_vacancies', 'h2h_vacancy_fills', 'h2h_waiting_seats')),
  'row level security on the three tables');
select pg_temp.check(
  not has_table_privilege('authenticated', 'gamification.h2h_seat_vacancies', 'select')
  and not has_table_privilege('anon', 'gamification.h2h_waiting_seats', 'select')
  and not has_table_privilege('authenticated', 'gamification.h2h_vacancy_fills', 'insert'),
  'players read and write nothing directly');
select pg_temp.check(
  (select count(*) from ops.applied_migrations where version = '0214_h2h_absence_all_groups') = 1,
  'the migration records itself');

rollback;
