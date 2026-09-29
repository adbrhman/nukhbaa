-- End-to-end test for migration 0078: a crowning may carry a prize, the
-- prize is bounded, and it is frozen like the rest of the crowning while the
-- picture still changes. Rolled back at the end.
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

-- True when [stmt] raises, false when it runs.
create function pg_temp.refused(stmt text) returns boolean
language plpgsql as $$
begin
  execute stmt;
  return false;
exception when others then
  return true;
end $$;

insert into competition.competitions (id, name, format, visibility) values
  ('c7800000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7800000-0000-4000-8000-000000000009', 'c7800000-0000-4000-8000-000000000001', '09/2026', '2026-08-31 21:00Z', '2026-09-30 21:00Z'),
  ('c7800000-0000-4000-8000-000000000008', 'c7800000-0000-4000-8000-000000000001', '08/2026', '2026-07-31 21:00Z', '2026-08-31 21:00Z');

do $$
declare
  n integer;
  u uuid;
begin
  for n in 1..2 loop
    u := ('00000000-0000-4000-8078-00000000000' || n)::uuid;
    insert into auth.users (id, email, email_confirmed_at) values (u, 'p' || n || '@t.io', now());
    insert into identity.users (id, email, display_name, created_at)
    values (u, 'p' || n || '@t.io', 'P' || n, '2026-08-01');
    insert into competition.participants (id, season_id, user_id, joined_at)
    values (('00000000-0000-4000-8178-00000000000' || n)::uuid,
            'c7800000-0000-4000-8000-000000000009', u, '2026-09-02');
    insert into competition.participants (id, season_id, user_id, joined_at)
    values (('00000000-0000-4000-8278-00000000000' || n)::uuid,
            'c7800000-0000-4000-8000-000000000008', u, '2026-08-02');
  end loop;
end $$;

insert into competition.month_champions
  (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by, prize)
values ('c7800000-0000-4000-8000-000000000009', '00000000-0000-4000-8078-000000000001',
        126, 21, 210, '2026-10-01 00:30Z', '00000000-0000-4000-8078-000000000002',
        '150 ريال سعودي');

do $$
begin
  perform pg_temp.check(
    (select prize from competition.month_champions
      where season_id = 'c7800000-0000-4000-8000-000000000009') = '150 ريال سعودي',
    'a crowning carries its prize');

  perform pg_temp.check(
    not pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by)
      values ('c7800000-0000-4000-8000-000000000008', '00000000-0000-4000-8078-000000000001',
              90, 10, 150, '2026-09-01 00:30Z', '00000000-0000-4000-8078-000000000002')
    $q$),
    'a crowning without a prize is still allowed');

  perform pg_temp.check(
    pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by, prize)
      values ('c7800000-0000-4000-8000-000000000009', '00000000-0000-4000-8078-000000000002',
              126, 21, 210, '2026-10-01 00:30Z', '00000000-0000-4000-8078-000000000002',
              repeat('x', 81))
    $q$),
    'a prize longer than 80 characters is refused');

  perform pg_temp.check(
    pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by, prize)
      values ('c7800000-0000-4000-8000-000000000009', '00000000-0000-4000-8078-000000000002',
              126, 21, 210, '2026-10-01 00:30Z', '00000000-0000-4000-8078-000000000002',
              '   ')
    $q$),
    'a blank prize is refused (the server sends null instead)');

  perform pg_temp.check(
    pg_temp.refused($q$
      update competition.month_champions set prize = '500 ريال سعودي'
       where season_id = 'c7800000-0000-4000-8000-000000000009'
    $q$),
    'the prize is frozen after the crowning');

  perform pg_temp.check(
    not pg_temp.refused($q$
      update competition.month_champions
         set photo_bytes = '\x89504e47'::bytea, photo_mime = 'image/png',
             photo_updated_at = '2026-10-01 00:35Z'
       where season_id = 'c7800000-0000-4000-8000-000000000009'
    $q$),
    'the picture still changes');
end $$;

rollback;
