-- Migration 0204 (pictures of the Elite Cup champions, and every crowning
-- picture erased with its account, scripts 238-239) and the statements
-- PostgresCupChampionRepository runs. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

-- What the stubs lack and identity.delete_account touches (rolled back).
alter table auth.users
  add column if not exists phone text,
  add column if not exists raw_user_meta_data jsonb,
  add column if not exists banned_until timestamptz,
  add column if not exists updated_at timestamptz;
create table if not exists auth.refresh_tokens (user_id text);
create table if not exists auth.sessions (user_id uuid);
create table if not exists auth.identities (user_id uuid);

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

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

-- PostgresCupChampionRepository.setPhotoSql
create function pg_temp.cup_photo_set(bytea, text, timestamptz, date, smallint)
returns setof text language sql as $$
INSERT INTO gamification.h2h_cup_title_photos
  (month_start, place, user_id, photo_bytes, photo_mime, photo_updated_at)
SELECT t.month_start, t.place, t.champion, $1, $2, $3::timestamptz
FROM gamification.h2h_cup_titles t
WHERE t.month_start = $4::date
  AND t.place = $5::smallint
  AND t.champion IS NOT NULL
ON CONFLICT (month_start, place) DO UPDATE
SET photo_bytes = EXCLUDED.photo_bytes,
    photo_mime = EXCLUDED.photo_mime,
    photo_updated_at = EXCLUDED.photo_updated_at
RETURNING user_id::text
$$;

-- PostgresCupChampionRepository.removePhotoSql
create function pg_temp.cup_photo_remove(date, smallint)
returns setof text language sql as $$
DELETE FROM gamification.h2h_cup_title_photos
WHERE month_start = $1::date AND place = $2::smallint
RETURNING user_id::text
$$;

-- PostgresCupChampionRepository.listSql
create function pg_temp.cup_list(int)
returns table (month_start text, place smallint, how text, champion_id text,
               champion_name text, champion_avatar_updated_at timestamptz,
               runner_up_id text, runner_up_name text,
               photo_updated_at timestamptz)
language sql as $$
SELECT t.month_start::text,
       t.place,
       t.how,
       t.champion::text,
       uc.display_name,
       uc.avatar_updated_at,
       t.runner_up::text,
       ur.display_name,
       p.photo_updated_at
FROM gamification.h2h_cup_titles t
LEFT JOIN identity.users uc ON uc.id = t.champion
LEFT JOIN identity.users ur ON ur.id = t.runner_up
LEFT JOIN gamification.h2h_cup_title_photos p
  ON p.month_start = t.month_start AND p.place = t.place
ORDER BY t.month_start DESC, t.place
LIMIT $1::int
$$;

-- ---------------------------------------------------------------------------
-- A crowned September (champion P1, podium P2 and P3, all with a picture),
-- and an Elite Cup of November: path 1 won by P4, path 2 by P5, path 3 vacant.
-- ---------------------------------------------------------------------------
insert into competition.competitions (id, name, format, visibility) values
  ('c2040000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2040000-0000-4000-8000-000000000009', 'c2040000-0000-4000-8000-000000000001', '09/2099', '2099-09-01 00:00Z', '2099-09-30 21:00Z');
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0204-4000-8204-00000000000' || i)::uuid, 'p' || i || '@t.io', now()
from generate_series(1, 6) i;
insert into identity.users (id, email, display_name)
select ('00000000-0204-4000-8204-00000000000' || i)::uuid, 'p' || i || '@t.io', 'P' || i
from generate_series(1, 6) i;
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c2040000-0000-4000-8000-0000000000a' || i)::uuid,
       'c2040000-0000-4000-8000-000000000009',
       ('00000000-0204-4000-8204-00000000000' || i)::uuid, '2099-09-02'
from generate_series(1, 3) i;
insert into competition.month_champions
  (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by,
   photo_bytes, photo_mime, photo_updated_at)
values ('c2040000-0000-4000-8000-000000000009', '00000000-0204-4000-8204-000000000001',
        50, 6, 30, '2099-10-01 12:00Z', '00000000-0204-4000-8204-000000000006',
        '\x01'::bytea, 'image/png', '2099-10-02');
insert into competition.month_podium
  (season_id, place, user_id, points, exact_count, decided_count, set_at, set_by,
   photo_bytes, photo_mime, photo_updated_at)
values ('c2040000-0000-4000-8000-000000000009', 2, '00000000-0204-4000-8204-000000000002',
        40, 4, 30, '2099-10-01 12:05Z', '00000000-0204-4000-8204-000000000006',
        '\x02'::bytea, 'image/png', '2099-10-02'),
       ('c2040000-0000-4000-8000-000000000009', 3, '00000000-0204-4000-8204-000000000003',
        30, 3, 30, '2099-10-01 12:05Z', '00000000-0204-4000-8204-000000000006',
        '\x03'::bytea, 'image/png', '2099-10-02');
insert into gamification.h2h_months (month_start, seated_count) values ('2099-11-01', 16);
insert into gamification.h2h_cup_titles (month_start, place, champion, runner_up, how) values
  ('2099-11-01', 1, '00000000-0204-4000-8204-000000000004', '00000000-0204-4000-8204-000000000005', 'final'),
  ('2099-11-01', 2, '00000000-0204-4000-8204-000000000005', null, 'walkover'),
  ('2099-11-01', 3, null, null, 'vacant');

-- ---------------------------------------------------------------------------
-- The picture of a cup champion
-- ---------------------------------------------------------------------------
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_set('\x0a'::bytea, 'image/png', '2099-12-01 10:00Z'::timestamptz, '2099-11-01', 1::smallint)) = 1,
  'the champion of path 1 gets a picture');
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_set('\x0b'::bytea, 'image/webp', '2099-12-01 11:00Z'::timestamptz, '2099-11-01', 1::smallint)) = 1,
  'the champion replaces the picture');
select pg_temp.check(
  (select photo_mime = 'image/webp' and photo_updated_at = '2099-12-01 11:00Z'::timestamptz
     from gamification.h2h_cup_title_photos
    where month_start = '2099-11-01' and place = 1)
  and (select count(*) from gamification.h2h_cup_title_photos where month_start = '2099-11-01') = 1,
  'the picture is replaced in place, not added');
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_set('\x0c'::bytea, 'image/png', '2099-12-01 12:00Z'::timestamptz, '2099-11-01', 3::smallint)) = 0,
  'a vacant title has no champion: no picture');
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_set('\x0c'::bytea, 'image/png', '2099-12-01 12:00Z'::timestamptz, '2099-12-01', 1::smallint)) = 0,
  'a month without a cup: no picture');
select pg_temp.refused(
  $q$insert into gamification.h2h_cup_title_photos (month_start, place, user_id, photo_bytes, photo_mime)
     values ('2099-11-01', 2, '00000000-0204-4000-8204-000000000004', '\x01', 'image/png')$q$,
  'h2h_cup_title_photos_champion', 'only the champion of a title can have its picture');
select pg_temp.refused(
  $q$insert into gamification.h2h_cup_title_photos (month_start, place, user_id, photo_bytes, photo_mime)
     values ('2099-11-01', 2, '00000000-0204-4000-8204-000000000005', '\x01', 'image/gif')$q$,
  'h2h_cup_title_photos_mime_check', 'only jpeg, png and webp');
select pg_temp.refused(
  $q$insert into gamification.h2h_cup_title_photos (month_start, place, user_id, photo_bytes, photo_mime)
     values ('2099-11-01', 2, '00000000-0204-4000-8204-000000000005', ''::bytea, 'image/png')$q$,
  'h2h_cup_title_photos_size_check', 'an empty picture is refused');
select pg_temp.refused(
  $q$insert into gamification.h2h_cup_title_photos (month_start, place, user_id, photo_bytes, photo_mime)
     values ('2099-11-01', 2, '00000000-0204-4000-8204-000000000005', repeat('x', 524289)::bytea, 'image/png')$q$,
  'h2h_cup_title_photos_size_check', 'a picture over 512 KB is refused');
select pg_temp.refused(
  $q$update gamification.h2h_cup_title_photos set user_id = '00000000-0204-4000-8204-000000000005'
      where month_start = '2099-11-01' and place = 1$q$,
  'h2h_cup_title_photos_frozen', 'only the picture may change');
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_set('\x0d'::bytea, 'image/png', '2099-12-01 13:00Z'::timestamptz, '2099-11-01', 2::smallint)) = 1,
  'the champion of path 2 gets a picture too (a walkover champion)');
select pg_temp.check(
  (select count(*) from pg_temp.cup_photo_remove('2099-11-01', 2::smallint)) = 1,
  'a picture is removed');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_title_photos where month_start = '2099-11-01' and place = 2) = 0
  and (select count(*) from pg_temp.cup_photo_remove('2099-11-01', 2::smallint)) = 0,
  'removing it again finds nothing');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_titles where month_start = '2099-11-01') = 3,
  'the titles are untouched');

-- The list: newest month first, the picture's stamp beside its title.
select pg_temp.check(
  (select string_agg(place || ':' || coalesce(champion_name, '-') || ':' || (photo_updated_at is not null)::text, ',' order by place)
     from pg_temp.cup_list(10) l) = '1:P4:true,2:P5:false,3:-:false',
  'the list gives each path, its champion and whether it has a picture');

-- ---------------------------------------------------------------------------
-- Deleting an account erases its crowning pictures, and only its own
-- ---------------------------------------------------------------------------
select pg_temp.check(identity.delete_account('00000000-0204-4000-8204-000000000001'), 'the month champion deletes his account');
select pg_temp.check(
  (select photo_bytes is null and photo_mime is null and photo_updated_at is null
     from competition.month_champions
    where season_id = 'c2040000-0000-4000-8000-000000000009' and user_id = '00000000-0204-4000-8204-000000000001'),
  'his champion picture is erased and the crowning stays');
select pg_temp.check(
  (select photo_bytes is not null from competition.month_podium
    where season_id = 'c2040000-0000-4000-8000-000000000009' and place = 2),
  'another player''s picture is not touched');
select pg_temp.check(identity.delete_account('00000000-0204-4000-8204-000000000002'), 'a podium player deletes his account');
select pg_temp.check(
  (select photo_bytes is null from competition.month_podium
    where season_id = 'c2040000-0000-4000-8000-000000000009' and place = 2)
  and (select photo_bytes is not null from competition.month_podium
        where season_id = 'c2040000-0000-4000-8000-000000000009' and place = 3),
  'his podium picture is erased, the other place keeps its own');
select pg_temp.check(identity.delete_account('00000000-0204-4000-8204-000000000004'), 'the cup champion deletes his account');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_title_photos where month_start = '2099-11-01') = 0
  and (select champion is not null from gamification.h2h_cup_titles where month_start = '2099-11-01' and place = 1),
  'his cup picture is erased and the title record stays');
select pg_temp.check(
  (select champion_name is distinct from 'P4' from pg_temp.cup_list(10) l where l.place = 1),
  'a deleted champion keeps no trace of his name in the list');

-- Safe to re-run, and nothing here is open to the app's roles.
select pg_temp.check(
  not has_table_privilege('anon', 'gamification.h2h_cup_title_photos', 'select')
  and not has_table_privilege('authenticated', 'gamification.h2h_cup_title_photos', 'select')
  and not has_function_privilege('authenticated', 'identity.delete_account(uuid)', 'execute'),
  'the app''s roles cannot read the pictures nor delete an account');
select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0204_cup_champion_photos_and_erasure'),
  '0204 is recorded as applied');

rollback;
