-- End-to-end test for migration 0195 (script 197): a match moved to another
-- Riyadh day loses its doubles; a time change on the same day, a decided or
-- started match keep them; the freed day takes another double; a merge onto
-- a copy put back to another day drops the double. Rolled back at the end.
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

create function pg_temp.doubled(p_prediction text) returns boolean
language sql as $$
  select is_double from prediction.fixture_predictions
   where id = p_prediction::uuid
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1950000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1950000-0000-4000-8000-000000000010', 'c1950000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');

insert into football_data.teams (id, name) values
  ('00000000-0195-4000-8000-000000000001', 'Home 195'),
  ('00000000-0195-4000-8000-000000000002', 'Away 195');

-- 1 June (Riyadh): a1 and a3. 2 June: b1. a2 also 1 June, to be decided.
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id)
values
  ('c1950000-0000-4000-8000-0000000000a1', 'A1', 'B1', '2099-06-01 15:00Z', null, null),
  ('c1950000-0000-4000-8000-0000000000a2', 'A2', 'B2', '2099-06-01 16:00Z', null, null),
  ('c1950000-0000-4000-8000-0000000000a3', 'A3', 'B3', '2099-06-01 17:00Z', null, null),
  ('c1950000-0000-4000-8000-0000000000b1', 'A4', 'B4', '2099-06-02 15:00Z', null, null),
  ('c1950000-0000-4000-8000-0000000000d0', 'Home 195', 'Away 195', '2099-06-10 18:00Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002'),
  ('c1950000-0000-4000-8000-0000000000e0', 'Home 195', 'Away 195', '2099-06-11 18:00Z',
   '00000000-0195-4000-8000-000000000001', '00000000-0195-4000-8000-000000000002');
insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c1950000-0000-4000-8000-000000000010', f, n
  from unnest(array[
    'c1950000-0000-4000-8000-0000000000a1', 'c1950000-0000-4000-8000-0000000000a2',
    'c1950000-0000-4000-8000-0000000000a3', 'c1950000-0000-4000-8000-0000000000b1',
    'c1950000-0000-4000-8000-0000000000d0', 'c1950000-0000-4000-8000-0000000000e0'
  ]::uuid[]) with ordinality as t(f, n);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8195-000000000001', 'p1-195@t.io', now()),
  ('00000000-0000-4000-8195-000000000002', 'p2-195@t.io', now()),
  ('00000000-0000-4000-8195-0000000000ad', 'ad-195@t.io', now());
insert into identity.users (id, email, display_name, created_at, role) values
  ('00000000-0000-4000-8195-000000000001', 'p1-195@t.io', 'P1 195', '2099-05-01', 'user'),
  ('00000000-0000-4000-8195-000000000002', 'p2-195@t.io', 'P2 195', '2099-05-01', 'user'),
  ('00000000-0000-4000-8195-0000000000ad', 'ad-195@t.io', 'Admin 195', '2099-05-01', 'admin');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1950000-0000-4000-8000-0000000001a1', 'c1950000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8195-000000000001', '2099-05-31'),
  ('c1950000-0000-4000-8000-0000000001a2', 'c1950000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8195-000000000002', '2099-05-31');

-- p1: a1 doubled (1 June), a3 plain, d0 doubled (10 June). p2: a1 doubled
-- (1 June), b1 doubled (2 June), a2 plain.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  ('c1950000-0000-4000-8000-00000000b001', 'c1950000-0000-4000-8000-0000000000a1',
   'c1950000-0000-4000-8000-0000000001a1', 2, 1, true,  now()),
  ('c1950000-0000-4000-8000-00000000b002', 'c1950000-0000-4000-8000-0000000000a3',
   'c1950000-0000-4000-8000-0000000001a1', 0, 0, false, now()),
  ('c1950000-0000-4000-8000-00000000b003', 'c1950000-0000-4000-8000-0000000000a1',
   'c1950000-0000-4000-8000-0000000001a2', 1, 1, true,  now()),
  ('c1950000-0000-4000-8000-00000000b004', 'c1950000-0000-4000-8000-0000000000b1',
   'c1950000-0000-4000-8000-0000000001a2', 3, 0, true,  now()),
  ('c1950000-0000-4000-8000-00000000b005', 'c1950000-0000-4000-8000-0000000000a2',
   'c1950000-0000-4000-8000-0000000001a2', 1, 0, false, now()),
  ('c1950000-0000-4000-8000-00000000b006', 'c1950000-0000-4000-8000-0000000000d0',
   'c1950000-0000-4000-8000-0000000001a1', 4, 4, true,  now());

create temp table seen as select epoch from ops.cache_epoch where id = 1;

-- The server's own session: only the release itself moves the epoch.
set local application_name = 'nukhbaa-server';

-- 1. a1 put back from 1 June to 2 June.
update competition.fixture_schedules set kickoff_at = '2099-06-02 18:00Z'
 where fixture_id = 'c1950000-0000-4000-8000-0000000000a1';
select pg_temp.check(not pg_temp.doubled('c1950000-0000-4000-8000-00000000b001')
  and not pg_temp.doubled('c1950000-0000-4000-8000-00000000b003'),
  'a match put back to another day loses its doubles, for every player');
select pg_temp.check(
  (select home_goals = 2 and away_goals = 1 and fixture_id::text like '%0a1'
     from prediction.fixture_predictions
    where id = 'c1950000-0000-4000-8000-00000000b001'),
  'the prediction itself stays, an ordinary one');
select pg_temp.check(pg_temp.doubled('c1950000-0000-4000-8000-00000000b004'),
  'p2''s double on the new day''s own match is untouched');
select pg_temp.check(
  (select epoch from ops.cache_epoch) = (select epoch from seen) + 1
    and (select source from ops.cache_epoch)
          = 'double released: c1950000-0000-4000-8000-0000000000a1',
  'the release moves the cache epoch, even from the server''s session');

-- 2. The freed day takes another double; the new day keeps one a day.
update prediction.fixture_predictions set is_double = true
 where id = 'c1950000-0000-4000-8000-00000000b002';
select pg_temp.check(pg_temp.doubled('c1950000-0000-4000-8000-00000000b002'),
  'p1 doubles another match of 1 June that has not kicked off');

-- 3. A new time on the same Riyadh day keeps the double.
update competition.fixture_schedules set kickoff_at = '2099-06-01 19:00Z'
 where fixture_id = 'c1950000-0000-4000-8000-0000000000a3';
select pg_temp.check(pg_temp.doubled('c1950000-0000-4000-8000-00000000b002'),
  'a new kickoff time on the same day keeps the double');

-- 4. A decided match keeps its doubles, whatever its kickoff does.
update prediction.fixture_predictions set is_double = true
 where id = 'c1950000-0000-4000-8000-00000000b005';
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
values ('c1950000-0000-4000-8000-0000000000a2', 1, 0, now());
update competition.fixture_schedules set kickoff_at = '2099-06-05 18:00Z'
 where fixture_id = 'c1950000-0000-4000-8000-0000000000a2';
select pg_temp.check(pg_temp.doubled('c1950000-0000-4000-8000-00000000b005'),
  'a match with a recorded result keeps its doubles');

-- 5. Brought into the past (a correction of a match under way): nothing
--    moves and the correction is not refused.
update competition.fixture_schedules set kickoff_at = now() - interval '1 hour'
 where fixture_id = 'c1950000-0000-4000-8000-0000000000a3';
select pg_temp.check(pg_temp.doubled('c1950000-0000-4000-8000-00000000b002'),
  'a kickoff moved into the past keeps the double and goes through');

-- 6. A merge onto a copy put back to another day (0182) drops the double.
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c1950000-0000-4000-8000-0000000000d0';
select pg_temp.check(
  (select r.moved = 1 from competition.merge_fixture_copies(
     'c1950000-0000-4000-8000-0000000000d0'::uuid,
     'c1950000-0000-4000-8000-0000000000e0'::uuid,
     '00000000-0000-4000-8195-0000000000ad'::uuid, true) r),
  'the copy put back a day is merged');
select pg_temp.check(
  (select fixture_id::text like '%0e0' and not is_double
     from prediction.fixture_predictions
    where id = 'c1950000-0000-4000-8000-00000000b006'),
  'the merged prediction arrives on the new day without its double');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0195_postponed_double'),
  '0195 recorded in ops.applied_migrations');

rollback;
