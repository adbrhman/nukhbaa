-- Migration 0213 (new players and the waiting group, script 277) and the
-- statements its adapters run: PostgresH2hNewcomerStore, the draw's
-- waiting row (PostgresH2hLeagueStore.insertWaitingSql) and the waiting
-- gate of PostgresH2hSheetReader.membersSql. The PREPARE statements are the
-- adapters' SQL constants, text for text, with @name::type turned into
-- $n::type. Then the owner's files in supabase/queries: the moves, the
-- check, the freeze and the unfreeze. Rolled back at the end.
\set ON_ERROR_STOP on
\set movements_sql `sed -e 's/--.*$//' -e "s/'%علوش%'/'%Wait 213 %'/" supabase/queries/h2h_movements.sql | tr '\n' ' ' | sed -e 's/; *$//'`
\set check_sql `sed -e 's/--.*$//' supabase/queries/h2h_newcomers_check.sql | tr '\n' ' ' | sed -e 's/; *$//'`
-- The freeze and the unfreeze run inside this test's transaction: their own
-- begin and commit are left out.
\set freeze_sql `sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/queries/h2h_newcomers_freeze.sql`
\set unfreeze_sql `sed -e '/^begin;$/d' -e '/^commit;$/d' supabase/queries/h2h_newcomers_unfreeze.sql`
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

-- PostgresH2hNewcomerStore.nextIndexSql
PREPARE nc_next_index(date) AS
SELECT COALESCE(max(l.group_index) + 1, 0)::integer AS next_index
FROM gamification.h2h_leagues l
WHERE l.month_start = $1::date
  AND l.division = 2;

-- PostgresH2hNewcomerStore.newcomerSql
PREPARE nc_newcomer(date, uuid, uuid) AS
INSERT INTO gamification.h2h_newcomer_seatings
  (month_start, user_id, league_id)
VALUES ($1::date, $2::uuid, $3::uuid);

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

-- ---------------------------------------------------------------------------
-- The world. Players 01..60: 01..20 in group 5 (G5, playing), 21..23 in the
-- draw's waiting group W1 (group 6), 24..60 not seated. November 2026 (N5)
-- and December 2098 drawn; December's draw at 2098-12-01 00:00Z.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0213-4000-8213-0000000000' || lpad(i::text, 2, '0'))::uuid,
       'w' || i || '@t.io', now()
from generate_series(1, 60) i;
insert into identity.users (id, email, display_name)
select ('00000000-0213-4000-8213-0000000000' || lpad(i::text, 2, '0'))::uuid,
       'w' || i || '@t.io', 'Wait 213 ' || lpad(i::text, 2, '0')
from generate_series(1, 60) i;

insert into competition.competitions (id, name, format, visibility) values
  ('c2130000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2130000-0000-4000-8000-000000000010', 'c2130000-0000-4000-8000-000000000001',
   '12/2098', '2098-11-30 21:00Z', '2098-12-31 21:00Z');
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c2130000-0000-4000-8000-0000000a' || lpad(i::text, 4, '0'))::uuid,
       'c2130000-0000-4000-8000-000000000010',
       ('00000000-0213-4000-8213-0000000000' || lpad(i::text, 2, '0'))::uuid,
       '2098-12-01'
from generate_series(1, 60) i;
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c2130000-0000-4000-8000-0000000000f1', 'A', 'B', '2098-12-03 18:00Z', false),
  ('c2130000-0000-4000-8000-0000000000f2', 'C', 'D', '2098-11-28 18:00Z', false),
  ('c2130000-0000-4000-8000-0000000000f3', 'E', 'F', '2098-12-03 19:00Z', false);

insert into gamification.h2h_months (month_start, is_pilot, seated_count, drawn_at)
values ('2026-11-01', false, 20, '2026-11-01 00:00Z'),
       ('2098-12-01', false, 23, '2098-12-01 00:00Z');

-- November 2026: a group drawn as before.
execute league_insert_group('c2130000-0000-4000-8000-0000000000b5', '2026-11-01', 2, 0, 20);
select pg_temp.refused($q$execute league_insert_waiting('c2130000-0000-4000-8000-0000000000b5', '2026-11-01')$q$,
  'h2h_waiting_groups_december_on', 'no waiting group before December 2026');

-- December: group 5 playing, group 6 the draw's waiting group of three.
execute league_insert_group('c2130000-0000-4000-8000-0000000000e1', '2098-12-01', 1, 0, 20);
execute league_insert_group('c2130000-0000-4000-8000-0000000000e5', '2098-12-01', 2, 0, 20);
execute league_insert_group('c2130000-0000-4000-8000-0000000000e6', '2098-12-01', 2, 1, 20);
select pg_temp.refused($q$execute league_insert_waiting('c2130000-0000-4000-8000-0000000000e1', '2098-12-01')$q$,
  'h2h_waiting_groups_extra_twenty', 'an elite group never waits');
execute league_insert_waiting('c2130000-0000-4000-8000-0000000000e6', '2098-12-01');
select pg_temp.refused($q$execute league_insert_waiting('c2130000-0000-4000-8000-0000000000e5', '2098-12-01')$q$,
  'h2h_waiting_groups_one_open', 'one waiting group open at a time');

select ('00000000-0213-4000-8213-0000000000' || lpad(i::text, 2, '0'))::uuid as u, i
  into temp players from generate_series(1, 60) i;
do $$
declare r record;
begin
  for r in select u, i from players where i <= 20 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2130000-0000-4000-8000-0000000000e5', '2098-12-01', r.u, r.i - 1);
  end loop;
  for r in select u, i from players where i between 21 and 23 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2130000-0000-4000-8000-0000000000e6', '2098-12-01', r.u, r.i - 21);
  end loop;
end $$;

create temp table g5_before as execute sheet_members('c2130000-0000-4000-8000-0000000000e5');
create temp table w_before as execute sheet_members('c2130000-0000-4000-8000-0000000000e6');
select pg_temp.check((select count(*) from g5_before) = 20 and (select bool_and(from_round = 1) from g5_before),
  'a playing group is read from round 1, as before');
select pg_temp.check((select count(*) from w_before) = 3 and (select bool_and(from_round = 20) from w_before),
  'a waiting group plays no round before it starts');

-- ---------------------------------------------------------------------------
-- Who is new
-- ---------------------------------------------------------------------------
-- 24..40 predict f1 after the draw; 41 only before the draw (f2); 42 only
-- a match hidden since (f3); 43 is hidden, 44 suspended; 05 is seated.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
select gen_random_uuid(), 'c2130000-0000-4000-8000-0000000000f1'::uuid,
       ('c2130000-0000-4000-8000-0000000a' || lpad(i::text, 4, '0'))::uuid,
       1, 0, false, timestamptz '2098-12-02 10:00Z' + (i || ' minutes')::interval
from generate_series(24, 40) i
union all
select gen_random_uuid(), 'c2130000-0000-4000-8000-0000000000f1'::uuid,
       ('c2130000-0000-4000-8000-0000000a' || lpad(i::text, 4, '0'))::uuid,
       1, 0, false, timestamptz '2098-12-02 09:00Z'
from unnest(array[5, 43, 44]) i
union all
select gen_random_uuid(), 'c2130000-0000-4000-8000-0000000000f2'::uuid,
       'c2130000-0000-4000-8000-0000000a0041'::uuid, 2, 2, false, timestamptz '2098-11-27 10:00Z'
union all
select gen_random_uuid(), 'c2130000-0000-4000-8000-0000000000f3'::uuid,
       'c2130000-0000-4000-8000-0000000a0042'::uuid, 0, 0, false, timestamptz '2098-12-02 10:00Z';
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c2130000-0000-4000-8000-0000000000f3';
update identity.users set hidden_at = now() where id = '00000000-0213-4000-8213-000000000043';
update identity.users set status = 'suspended' where id = '00000000-0213-4000-8213-000000000044';

create temp table new_out as execute nc_newcomers('2098-12-01');
select pg_temp.check((select count(*) from new_out) = 17, 'seventeen new players (24..40)');
select pg_temp.check((select user_id from new_out order by first_at, user_id limit 1)
  = '00000000-0213-4000-8213-000000000024', 'first prediction first');
select pg_temp.check(not exists (select 1 from new_out where user_id in (
  '00000000-0213-4000-8213-000000000005', '00000000-0213-4000-8213-000000000041',
  '00000000-0213-4000-8213-000000000042', '00000000-0213-4000-8213-000000000043',
  '00000000-0213-4000-8213-000000000044')),
  'not the seated, the early, a hidden match, a hidden or a suspended account');

create temp table waiting_out as execute nc_waiting('2098-12-01');
select pg_temp.check((select seated from waiting_out) = 3 and (select group_index from waiting_out) = 1,
  'the waiting group: group 6 with three');
create temp table next_out as execute nc_next_index('2098-12-01');
select pg_temp.check((select next_index from next_out) = 2, 'the next extra group is index 2');

-- ---------------------------------------------------------------------------
-- Seating: 24..39 take seats 3..18 of group 6
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select u, i from players where i between 24 and 39 loop
    execute format('execute league_insert_seat(%L, %L, %L, %s)',
      'c2130000-0000-4000-8000-0000000000e6', '2098-12-01', r.u, r.i - 21);
    execute format('execute nc_newcomer(%L, %L, %L)',
      '2098-12-01', r.u, 'c2130000-0000-4000-8000-0000000000e6');
  end loop;
end $$;
select pg_temp.check((select count(*) from gamification.h2h_league_members
  where league_id = 'c2130000-0000-4000-8000-0000000000e6') = 19, 'nineteen in the waiting group');

-- Never seated twice, never in two groups.
select pg_temp.refused($q$execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000024', 'c2130000-0000-4000-8000-0000000000e6')$q$,
  'h2h_newcomer_seatings_pkey', 'a new player is recorded once');
select pg_temp.refused($q$execute league_insert_seat('c2130000-0000-4000-8000-0000000000e6', '2098-12-01', '00000000-0213-4000-8213-000000000024', 19)$q$,
  'h2h_league_members_pkey', 'a player is not seated twice in a group');
select pg_temp.refused($q$execute league_insert_seat('c2130000-0000-4000-8000-0000000000e5', '2098-12-01', '00000000-0213-4000-8213-000000000024', 19)$q$,
  'h2h_league_members_month_user_uniq', 'a player is never in two groups');
select pg_temp.refused($q$execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000005', 'c2130000-0000-4000-8000-0000000000e5')$q$,
  'h2h_newcomer_seatings_waiting_only', 'a new player only joins a waiting group');

-- Seven rounds of December played.
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2130000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2098-12-01', n, ('2098-12-01'::date + (n - 1)), 6
from generate_series(1, 8) n;
insert into gamification.h2h_round_locks (round_id, fixture_count)
select ('c2130000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 6
from generate_series(1, 7) n;

select pg_temp.refused($q$execute nc_start('c2130000-0000-4000-8000-0000000000e6', 8)$q$,
  'h2h_group_starts_twenty', 'no start with nineteen');

-- The twentieth (player 40): seat, record and start in one go.
execute league_insert_seat('c2130000-0000-4000-8000-0000000000e6', '2098-12-01', '00000000-0213-4000-8213-000000000040', 19);
execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000040', 'c2130000-0000-4000-8000-0000000000e6');
select pg_temp.refused($q$execute nc_start('c2130000-0000-4000-8000-0000000000e6', 7)$q$,
  'h2h_group_starts_not_played', 'never from a round that has started');
execute nc_start('c2130000-0000-4000-8000-0000000000e6', 8);
select pg_temp.refused($q$execute nc_start('c2130000-0000-4000-8000-0000000000e6', 9)$q$,
  'h2h_group_starts_pkey', 'a group starts once');

create temp table w_after as execute sheet_members('c2130000-0000-4000-8000-0000000000e6');
create temp table g5_after as execute sheet_members('c2130000-0000-4000-8000-0000000000e5');
select pg_temp.check((select count(*) from w_after) = 20 and (select bool_and(from_round = 8) from w_after),
  'the started group plays from round 8, none before');
select pg_temp.check(
  (select count(*) from (select * from g5_before except select * from g5_after) d) = 0
  and (select count(*) from (select * from g5_after except select * from g5_before) d) = 0,
  'the playing group is read exactly as before the start');
select pg_temp.refused($q$execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000045', 'c2130000-0000-4000-8000-0000000000e6')$q$,
  null, 'nobody joins a group that has started');

create temp table waiting_none as execute nc_waiting('2098-12-01');
select pg_temp.check((select count(*) from waiting_none) = 0, 'no waiting group once it started');
-- A new waiting group may open now.
execute league_insert_group('c2130000-0000-4000-8000-0000000000e7', '2098-12-01', 2, 2, 20);
execute league_insert_waiting('c2130000-0000-4000-8000-0000000000e7', '2098-12-01');
select pg_temp.check((select count(*) from gamification.h2h_waiting_groups where month_start = '2098-12-01') = 2,
  'the next waiting group opens after the first started');

-- ---------------------------------------------------------------------------
-- The record: every move with its reason
-- ---------------------------------------------------------------------------
select pg_temp.check((select count(*) from gamification.h2h_movements
  where month_start = '2098-12-01' and kind = 'seat' and reason = 'newcomer') = 17,
  'seventeen seats recorded as new players');
select pg_temp.check((select count(*) from gamification.h2h_movements
  where month_start = '2098-12-01' and kind = 'seat' and reason = 'draw') = 23,
  'twenty-three seats recorded as the draw');
select pg_temp.check((select from_round from gamification.h2h_movements
  where kind = 'group_start' and to_league_id = 'c2130000-0000-4000-8000-0000000000e6') = 8,
  'the start recorded with its round');
create temp table moves_out as select * from (:movements_sql) q;
select pg_temp.check((select count(*) from moves_out where player = 'Wait 213 40') = 2,
  'the owner''s query: player 40 joined, then his group started');

-- ---------------------------------------------------------------------------
-- The freeze: nothing seated, nothing started, nothing lost; then undone
-- ---------------------------------------------------------------------------
:freeze_sql
:freeze_sql
execute league_insert_seat('c2130000-0000-4000-8000-0000000000e7', '2098-12-01', '00000000-0213-4000-8213-000000000045', 0);
select pg_temp.refused($q$execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000045', 'c2130000-0000-4000-8000-0000000000e7')$q$,
  'h2h_newcomers_frozen', 'frozen: no new player recorded');
create temp table check_frozen as select * from (:check_sql) q;
select pg_temp.check((select bool_and(frozen) from check_frozen) and (select count(*) from check_frozen) = 2,
  'the check reads both waiting groups, frozen');
select pg_temp.check((select seated from check_frozen where group_no = 6) = 20
  and (select started_from from check_frozen where group_no = 6) = 8,
  'the freeze kept every seat and the start');
:unfreeze_sql
:unfreeze_sql
execute nc_newcomer('2098-12-01', '00000000-0213-4000-8213-000000000045', 'c2130000-0000-4000-8000-0000000000e7');
select pg_temp.check((select count(*) from gamification.h2h_newcomer_seatings
  where user_id = '00000000-0213-4000-8213-000000000045') = 1, 'unfrozen: seated again');

-- ---------------------------------------------------------------------------
-- November is read as before; append-only; server-only
-- ---------------------------------------------------------------------------
execute league_insert_seat('c2130000-0000-4000-8000-0000000000b5', '2026-11-01', '00000000-0213-4000-8213-000000000050', 0);
create temp table nov_out as execute sheet_members('c2130000-0000-4000-8000-0000000000b5');
select pg_temp.check((select from_round from nov_out) = 1, 'a November group is read from round 1');
select pg_temp.refused($q$update gamification.h2h_group_starts set from_round = 9$q$, null,
  'a start is never changed');
select pg_temp.refused($q$delete from gamification.h2h_newcomer_seatings$q$, null,
  'a new player''s record is never deleted');
select pg_temp.refused($q$delete from gamification.h2h_waiting_groups$q$, null,
  'a waiting group is never deleted');
select pg_temp.check(
  (select bool_and(relrowsecurity) from pg_class
    where relnamespace = 'gamification'::regnamespace
      and relname in ('h2h_waiting_groups', 'h2h_group_starts', 'h2h_newcomer_seatings')),
  'row level security on the three tables');
select pg_temp.check(
  not has_table_privilege('authenticated', 'gamification.h2h_movements', 'select')
  and not has_table_privilege('anon', 'gamification.h2h_newcomer_seatings', 'select'),
  'players read nothing directly');
select pg_temp.check(
  (select count(*) from ops.applied_migrations where version = '0213_h2h_waiting_groups') = 1,
  'the migration records itself');

rollback;
