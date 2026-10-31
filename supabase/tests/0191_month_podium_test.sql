-- Migration 0191 (the podium of a crowned month, script 186) and the
-- statements its adapters run: PostgresMonthPodiumRepository and the
-- picture statements of PostgresMonthChampionRepository, which cover the
-- podium too. Rolled back at the end.
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

-- PostgresMonthPodiumRepository.ofSql
PREPARE podium_of(uuid) AS
SELECT p.season_id::text AS season_id,
       p.place,
       p.user_id::text AS user_id,
       u.display_name,
       p.points,
       p.exact_count,
       p.decided_count,
       p.photo_updated_at,
       u.avatar_updated_at
FROM competition.month_podium p
JOIN competition.seasons s ON s.id = p.season_id
JOIN identity.users u ON u.id = p.user_id
WHERE p.season_id = $1::uuid
ORDER BY p.place;

-- PostgresMonthPodiumRepository.listSql
PREPARE podium_list(int) AS
SELECT p.season_id::text AS season_id,
       p.place,
       p.user_id::text AS user_id,
       u.display_name,
       p.points,
       p.exact_count,
       p.decided_count,
       p.photo_updated_at,
       u.avatar_updated_at
FROM competition.month_podium p
JOIN competition.seasons s ON s.id = p.season_id
JOIN identity.users u ON u.id = p.user_id
ORDER BY s.end_at DESC, p.place
LIMIT $1::int;

-- PostgresMonthPodiumRepository.setSql
PREPARE podium_set(uuid, smallint, uuid, int, int, int, timestamptz, uuid) AS
INSERT INTO competition.month_podium
  (season_id, place, user_id, points, exact_count, decided_count, set_at,
   set_by)
VALUES
  ($1::uuid, $2::smallint, $3::uuid, $4::int,
   $5::int, $6::int, $7::timestamptz,
   $8::uuid);

-- PostgresMonthChampionRepository._setPhotoSql
PREPARE photo_set(bytea, text, timestamptz, uuid, uuid) AS
WITH champion AS (
  UPDATE competition.month_champions
  SET photo_bytes = $1,
      photo_mime = $2,
      photo_updated_at = $3::timestamptz
  WHERE season_id = $4::uuid
    AND user_id = $5::uuid
  RETURNING user_id
),
podium AS (
  UPDATE competition.month_podium
  SET photo_bytes = $1,
      photo_mime = $2,
      photo_updated_at = $3::timestamptz
  WHERE season_id = $4::uuid
    AND user_id = $5::uuid
  RETURNING user_id
)
SELECT user_id::text AS user_id FROM champion
UNION ALL
SELECT user_id::text AS user_id FROM podium;

-- PostgresMonthChampionRepository._photoSql
PREPARE photo_get(uuid, uuid) AS
SELECT photo_bytes, photo_mime, photo_updated_at
FROM competition.month_champions
WHERE season_id = $1::uuid
  AND user_id = $2::uuid
UNION ALL
SELECT photo_bytes, photo_mime, photo_updated_at
FROM competition.month_podium
WHERE season_id = $1::uuid
  AND user_id = $2::uuid
LIMIT 1;

-- ---------------------------------------------------------------------------
-- September crowned (player 1), October not. Players 1..4 played
-- September; player 5 did not.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c1910000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1910000-0000-4000-8000-000000000009', 'c1910000-0000-4000-8000-000000000001', '09/2099', '2099-09-01 00:00Z', '2099-09-30 21:00Z'),
  ('c1910000-0000-4000-8000-000000000010', 'c1910000-0000-4000-8000-000000000001', '10/2099', '2099-09-30 21:00Z', '2099-10-31 21:00Z');
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0191-4000-8191-00000000000' || i)::uuid, 'p' || i || '@t.io', now()
from generate_series(1, 5) i;
insert into identity.users (id, email, display_name)
select ('00000000-0191-4000-8191-00000000000' || i)::uuid, 'p' || i || '@t.io', 'P' || i
from generate_series(1, 5) i;
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1910000-0000-4000-8000-0000000000a' || i)::uuid,
       'c1910000-0000-4000-8000-000000000009',
       ('00000000-0191-4000-8191-00000000000' || i)::uuid, '2099-09-02'
from generate_series(1, 4) i;
insert into competition.participants (id, season_id, user_id, joined_at)
values ('c1910000-0000-4000-8000-0000000000b2', 'c1910000-0000-4000-8000-000000000010',
        '00000000-0191-4000-8191-000000000002', '2099-10-02');
insert into competition.month_champions
  (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by)
values ('c1910000-0000-4000-8000-000000000009', '00000000-0191-4000-8191-000000000001',
        50, 6, 30, '2099-10-01 12:00Z', '00000000-0191-4000-8191-000000000004');

-- ---------------------------------------------------------------------------
-- The backstops
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$execute podium_set('c1910000-0000-4000-8000-000000000010', 2,
  '00000000-0191-4000-8191-000000000002', 10, 1, 5, '2099-11-01', '00000000-0191-4000-8191-000000000004')$q$,
  'month_podium_after_crowning', 'no podium for a month not crowned');
select pg_temp.refused($q$execute podium_set('c1910000-0000-4000-8000-000000000009', 2,
  '00000000-0191-4000-8191-000000000001', 50, 6, 30, '2099-10-02', '00000000-0191-4000-8191-000000000004')$q$,
  'month_podium_not_champion', 'the champion is not on the podium');
select pg_temp.refused($q$execute podium_set('c1910000-0000-4000-8000-000000000009', 2,
  '00000000-0191-4000-8191-000000000005', 10, 1, 5, '2099-10-02', '00000000-0191-4000-8191-000000000004')$q$,
  'month_podium_played', 'a player who did not play the month is not on it');
select pg_temp.refused($q$execute podium_set('c1910000-0000-4000-8000-000000000009', 4,
  '00000000-0191-4000-8191-000000000002', 10, 1, 5, '2099-10-02', '00000000-0191-4000-8191-000000000004')$q$,
  'month_podium_place_range', 'only places 2 and 3');

-- The podium of September: player 2 second, player 3 third.
execute podium_set('c1910000-0000-4000-8000-000000000009', 2,
  '00000000-0191-4000-8191-000000000002', 44, 7, 30, '2099-10-02', '00000000-0191-4000-8191-000000000004');
execute podium_set('c1910000-0000-4000-8000-000000000009', 3,
  '00000000-0191-4000-8191-000000000003', 44, 5, 30, '2099-10-02', '00000000-0191-4000-8191-000000000004');

select pg_temp.refused($q$execute podium_set('c1910000-0000-4000-8000-000000000009', 3,
  '00000000-0191-4000-8191-000000000004', 1, 1, 1, '2099-10-02', '00000000-0191-4000-8191-000000000004')$q$,
  'month_podium_pkey', 'a place is set once');
select pg_temp.refused($q$update competition.month_podium set points = 99
  where season_id = 'c1910000-0000-4000-8000-000000000009' and place = 2$q$,
  null, 'the figures are frozen');
select pg_temp.refused($q$delete from competition.month_podium$q$, null,
  'a podium is never deleted');

create temp table of_out as execute podium_of('c1910000-0000-4000-8000-000000000009');
select pg_temp.check((select count(*) from of_out) = 2, 'two places');
select pg_temp.check((select user_id from of_out where place = 2) = '00000000-0191-4000-8191-000000000002',
  'player 2 is second');
select pg_temp.check((select display_name from of_out where place = 3) = 'P3', 'with his name');

-- ---------------------------------------------------------------------------
-- The pictures: the champion's statement covers the podium.
-- ---------------------------------------------------------------------------
create temp table set_podium as execute photo_set('\x89504e47'::bytea, 'image/png', '2099-10-03',
  'c1910000-0000-4000-8000-000000000009', '00000000-0191-4000-8191-000000000002');
select pg_temp.check((select count(*) from set_podium) = 1, 'a podium picture is set');
create temp table set_champion as execute photo_set('\x89504e47'::bytea, 'image/png', '2099-10-03',
  'c1910000-0000-4000-8000-000000000009', '00000000-0191-4000-8191-000000000001');
select pg_temp.check((select count(*) from set_champion) = 1, 'the champion''s picture still is');
create temp table set_none as execute photo_set('\x89504e47'::bytea, 'image/png', '2099-10-03',
  'c1910000-0000-4000-8000-000000000009', '00000000-0191-4000-8191-000000000004');
select pg_temp.check((select count(*) from set_none) = 0, 'nobody else''s');

create temp table get_podium as execute photo_get('c1910000-0000-4000-8000-000000000009',
  '00000000-0191-4000-8191-000000000002');
select pg_temp.check((select photo_mime from get_podium) = 'image/png', 'the podium picture reads back');

create temp table list_out as execute podium_list(48);
select pg_temp.check((select count(*) from list_out) = 2, 'the list carries the podium');
select pg_temp.check((select photo_updated_at from list_out where place = 2) is not null,
  'with the picture''s time');

select pg_temp.check(
  (select relrowsecurity from pg_class where oid = 'competition.month_podium'::regclass),
  'row level security on');
select pg_temp.check(
  not has_table_privilege('authenticated', 'competition.month_podium', 'select'),
  'players read nothing directly');

rollback;
