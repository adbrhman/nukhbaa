-- End-to-end test for migration 0077: a month is crowned once, with one or
-- two champions who played it; afterwards only the picture may change and
-- nothing is deleted. Rolled back at the end.
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
  ('c7700000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7700000-0000-4000-8000-000000000009', 'c7700000-0000-4000-8000-000000000001', '09/2026', '2026-09-01 00:00Z', '2026-09-30 21:00Z'),
  ('c7700000-0000-4000-8000-000000000010', 'c7700000-0000-4000-8000-000000000001', '10/2026', '2026-09-30 21:00Z', '2026-10-31 21:00Z');

do $$
declare
  n integer;
  u uuid;
begin
  for n in 1..4 loop
    u := ('00000000-0000-4000-8077-00000000000' || n)::uuid;
    insert into auth.users (id, email, email_confirmed_at) values (u, 'c' || n || '@t.io', now());
    insert into identity.users (id, email, display_name, created_at)
    values (u, 'c' || n || '@t.io', 'C' || n, '2026-09-01');
    -- players 1..3 played September; player 4 did not
    if n <= 3 then
      insert into competition.participants (id, season_id, user_id, joined_at)
      values (('00000000-0000-4000-8177-00000000000' || n)::uuid,
              'c7700000-0000-4000-8000-000000000009', u, '2026-09-02');
    end if;
  end loop;
end $$;

do $$
begin
  perform pg_temp.check(
    pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by)
      values ('c7700000-0000-4000-8000-000000000009', '00000000-0000-4000-8077-000000000004',
              40, 5, 20, '2026-10-01 12:00Z', '00000000-0000-4000-8077-000000000003')
    $q$),
    'a player who did not play the month cannot be its champion');

  -- Two players level on everything: one crowning, two champions.
  insert into competition.month_champions
    (season_id, user_id, points, exact_count, decided_count, referral_points, crowned_at, crowned_by)
  values
    ('c7700000-0000-4000-8000-000000000009', '00000000-0000-4000-8077-000000000001',
     42, 6, 30, 2, '2026-10-01 12:00Z', '00000000-0000-4000-8077-000000000003'),
    ('c7700000-0000-4000-8000-000000000009', '00000000-0000-4000-8077-000000000002',
     42, 6, 28, 2, '2026-10-01 12:00Z', '00000000-0000-4000-8077-000000000003');
  perform pg_temp.check(
    (select count(*) from competition.month_champions
      where season_id = 'c7700000-0000-4000-8000-000000000009') = 2,
    'one crowning may name two champions');

  perform pg_temp.check(
    pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by)
      values ('c7700000-0000-4000-8000-000000000009', '00000000-0000-4000-8077-000000000003',
              40, 5, 20, '2026-10-01 12:00Z', '00000000-0000-4000-8077-000000000003')
    $q$),
    'never a third champion');

  perform pg_temp.check(
    pg_temp.refused($q$
      insert into competition.month_champions
        (season_id, user_id, points, exact_count, decided_count, crowned_at, crowned_by)
      values ('c7700000-0000-4000-8000-000000000009', '00000000-0000-4000-8077-000000000003',
              40, 5, 20, '2026-10-02 12:00Z', '00000000-0000-4000-8077-000000000003')
    $q$),
    'a crowned month is not crowned again');

  perform pg_temp.check(
    pg_temp.refused($q$
      update competition.month_champions set points = 99
      where user_id = '00000000-0000-4000-8077-000000000001'
    $q$),
    'the frozen figures never change');

  perform pg_temp.check(
    pg_temp.refused($q$
      delete from competition.month_champions
      where user_id = '00000000-0000-4000-8077-000000000002'
    $q$),
    'a crowning is never deleted');

  update competition.month_champions
  set photo_bytes = '\x89504e47'::bytea,
      photo_mime = 'image/png',
      photo_updated_at = '2026-10-01 12:05Z'
  where season_id = 'c7700000-0000-4000-8000-000000000009'
    and user_id = '00000000-0000-4000-8077-000000000001';
  perform pg_temp.check(
    (select photo_mime from competition.month_champions
      where user_id = '00000000-0000-4000-8077-000000000001') = 'image/png',
    'the picture can be set after the crowning');

  perform pg_temp.check(
    pg_temp.refused($q$
      update competition.month_champions
      set photo_bytes = '\x00'::bytea, photo_mime = 'image/gif', photo_updated_at = now()
      where user_id = '00000000-0000-4000-8077-000000000002'
    $q$),
    'only JPEG, PNG or WEBP');

  perform pg_temp.check(
    pg_temp.refused($q$
      update competition.month_champions
      set photo_bytes = '\x00'::bytea, photo_mime = 'image/png', photo_updated_at = null
      where user_id = '00000000-0000-4000-8077-000000000002'
    $q$),
    'a picture carries its type and its time together');

  perform pg_temp.check(
    (select count(*) from competition.month_champions) = 2,
    'nothing else changed');

  perform pg_temp.check(
    not has_table_privilege('authenticated', 'competition.month_champions', 'select'),
    'server-only: the app roles cannot read it');
end $$;

rollback;
