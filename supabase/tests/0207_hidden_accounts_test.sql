-- Test for script 258 (migration 0207): a hidden account leaves the live
-- standings view and comes back with the same points when shown again,
-- and the statements PostgresHiddenAccountStore runs (copied below with
-- their parameters as function arguments) hide, list and show it.
-- Rolled back at the end.
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

create function pg_temp.hide(p_id uuid) returns setof uuid
language sql as $f$
UPDATE identity.users
SET hidden_at = coalesce(hidden_at, now()),
    updated_at = now()
WHERE id = p_id
RETURNING id
$f$;

create function pg_temp.show_again(p_id uuid) returns setof uuid
language sql as $f$
UPDATE identity.users
SET hidden_at = NULL,
    updated_at = now()
WHERE id = p_id
RETURNING id
$f$;

create function pg_temp.list(p_limit int)
returns table (id text, email text, role text, status text,
               display_name text, hidden_at timestamptz)
language sql as $f$
SELECT u.id::text AS id, u.email, u.role::text AS role,
       u.status::text AS status, u.display_name, u.hidden_at
FROM identity.users u
WHERE u.hidden_at IS NOT NULL
ORDER BY u.hidden_at DESC, u.id
LIMIT p_limit
$f$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8207-000000000001', 'h1@t.io', now()),
  ('00000000-0000-4000-8207-000000000002', 'h2@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0000-4000-8207-000000000001', 'h1@t.io', 'H1'),
  ('00000000-0000-4000-8207-000000000002', 'h2@t.io', 'H2');
insert into competition.competitions (id, name, format, visibility)
values ('c2070000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('c2070000-0000-4000-8000-000000000010', 'c2070000-0000-4000-8000-000000000001', '07/2099', '2099-07-01', '2099-08-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c2070000-0000-4000-8000-0000000000a1', 'c2070000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8207-000000000001', '2099-07-01'),
  ('c2070000-0000-4000-8000-0000000000a2', 'c2070000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8207-000000000002', '2099-07-01');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at)
values ('c2070000-0000-4000-8000-0000000000f1', 'Hilal', 'Nassr', '2099-07-10 18:00+03');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
values ('c2070000-0000-4000-8000-000000000010', 'c2070000-0000-4000-8000-0000000000f1', 0);
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c2070000-0000-4000-8000-0000000000f1', 'c2070000-0000-4000-8000-0000000000a1', 1, 'correct_outcome', 1),
  ('c2070000-0000-4000-8000-0000000000f1', 'c2070000-0000-4000-8000-0000000000a2', 1, 'exact_scoreline', 3);

do $$
begin
  perform pg_temp.check(
    exists (
      select 1 from information_schema.columns
       where table_schema = 'identity' and table_name = 'users'
         and column_name = 'hidden_at'),
    'identity.users has hidden_at');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0207_hidden_accounts'),
    '0207 records itself');
  perform pg_temp.check(
    (select count(*) from pg_temp.hide('00000000-0000-4000-8207-0000000000ff')) = 0,
    'hiding an unknown account touches nothing');
  perform pg_temp.check(
    (select count(*) from pg_temp.hide('00000000-0000-4000-8207-000000000002')) = 1,
    'hiding an account finds it');
end $$;

do $$
declare
  first_time timestamptz;
begin
  perform pg_temp.check(
    (select count(*) from leaderboard.season_fixture_standings
      where season_id = 'c2070000-0000-4000-8000-000000000010') = 1
    and (select participant_id from leaderboard.season_fixture_standings
          where season_id = 'c2070000-0000-4000-8000-000000000010')
        = 'c2070000-0000-4000-8000-0000000000a1',
    'a hidden account leaves the standings');
  perform pg_temp.check(
    (select string_agg(display_name, ',') from pg_temp.list(200)) = 'H2',
    'the owner list shows the hidden account only');
  select hidden_at into first_time from identity.users
   where id = '00000000-0000-4000-8207-000000000002';
  perform pg_temp.hide('00000000-0000-4000-8207-000000000002');
  perform pg_temp.check(
    (select hidden_at from identity.users
      where id = '00000000-0000-4000-8207-000000000002') = first_time,
    'hiding twice keeps the first time');
  perform pg_temp.check(
    (select status::text from identity.users
      where id = '00000000-0000-4000-8207-000000000002') = 'active',
    'a hidden account stays active: it still signs in');
end $$;

do $$
begin
  perform pg_temp.check(
    (select count(*) from pg_temp.show_again('00000000-0000-4000-8207-000000000002')) = 1,
    'showing an account finds it');
  perform pg_temp.check(
    (select total_points from leaderboard.season_fixture_standings
      where participant_id = 'c2070000-0000-4000-8000-0000000000a2') = 3,
    'showing it again brings the same points back');
  perform pg_temp.check(
    (select count(*) from pg_temp.list(200)) = 0,
    'nothing is hidden any more');
end $$;

rollback;
