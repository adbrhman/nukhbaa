-- End-to-end test of migration 0200 (script 218, audit 32): the merge
-- counts a double that 0195 clears as dropped. A: the match put back from
-- 10 July 21:00 to 11 July 21:00 (Riyadh); p1 doubled only the first copy,
-- so 0195 clears the double as it moves. B: put back 12.5 hours within one
-- Riyadh day (00:30 to 13:00 on 21 July); p1's double moves with it. The
-- merges go through competition.merge_fixture_copies, every trigger on.
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

insert into competition.competitions (id, name, format, visibility) values
  ('c2000000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c2000000-0000-4000-8000-000000000010', 'c2000000-0000-4000-8000-000000000001',
   '07/2099', '2099-06-30 21:00Z', '2099-07-31 21:00Z');

insert into football_data.teams (id, name) values
  ('00000000-0200-4000-8000-000000000001', 'Home 200'),
  ('00000000-0200-4000-8000-000000000002', 'Away 200');

-- A: D1 21:00 Riyadh on 10 July, K1 the same match 24 hours later.
-- B: D2 00:30 Riyadh on 21 July, K2 the same match at 13:00 that day.
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test, hidden_at)
values
  ('c2000000-0000-4000-8000-0000000000a1', 'Home 200', 'Away 200', '2099-07-10 18:00Z',
   '00000000-0200-4000-8000-000000000001', '00000000-0200-4000-8000-000000000002', false, null),
  ('c2000000-0000-4000-8000-0000000000a2', 'Home 200', 'Away 200', '2099-07-11 18:00Z',
   '00000000-0200-4000-8000-000000000001', '00000000-0200-4000-8000-000000000002', false, null),
  ('c2000000-0000-4000-8000-0000000000b1', 'Home 200', 'Away 200', '2099-07-20 21:30Z',
   '00000000-0200-4000-8000-000000000001', '00000000-0200-4000-8000-000000000002', false, null),
  ('c2000000-0000-4000-8000-0000000000b2', 'Home 200', 'Away 200', '2099-07-21 10:00Z',
   '00000000-0200-4000-8000-000000000001', '00000000-0200-4000-8000-000000000002', false, null);

insert into competition.season_fixtures (season_id, fixture_id, display_order)
select 'c2000000-0000-4000-8000-000000000010'::uuid, f::uuid, n
  from unnest(array[
         'c2000000-0000-4000-8000-0000000000a1', 'c2000000-0000-4000-8000-0000000000a2',
         'c2000000-0000-4000-8000-0000000000b1', 'c2000000-0000-4000-8000-0000000000b2'])
       with ordinality as t(f, n);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8200-000000000001', 'r200-1@t.io', now()),
  ('00000000-0000-4000-8200-000000000002', 'r200-2@t.io', now()),
  ('00000000-0000-4000-8200-0000000000ad', 'a200@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8200-000000000001', 'r200-1@t.io', 'R200-1', '2099-06-01'),
  ('00000000-0000-4000-8200-000000000002', 'r200-2@t.io', 'R200-2', '2099-06-01');
insert into identity.users (id, email, display_name, role, created_at) values
  ('00000000-0000-4000-8200-0000000000ad', 'a200@t.io', 'A200', 'admin', '2099-06-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c2000000-0000-4000-8000-0000000001a1', 'c2000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8200-000000000001', '2099-07-01'),
  ('c2000000-0000-4000-8000-0000000001a2', 'c2000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8200-000000000002', '2099-07-01');

-- p1 doubled D1 and D2, his only doubles of those days; p2 predicted D1
-- without a double.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  ('c2000000-0000-4000-8000-00000000b001', 'c2000000-0000-4000-8000-0000000000a1',
   'c2000000-0000-4000-8000-0000000001a1', 2, 0, true,  '2099-07-10 10:00Z'),
  ('c2000000-0000-4000-8000-00000000b002', 'c2000000-0000-4000-8000-0000000000a1',
   'c2000000-0000-4000-8000-0000000001a2', 1, 1, false, '2099-07-10 11:00Z'),
  ('c2000000-0000-4000-8000-00000000b003', 'c2000000-0000-4000-8000-0000000000b1',
   'c2000000-0000-4000-8000-0000000001a1', 0, 1, true,  '2099-07-20 10:00Z');

do $$
declare
  d1  uuid := 'c2000000-0000-4000-8000-0000000000a1';
  k1  uuid := 'c2000000-0000-4000-8000-0000000000a2';
  d2  uuid := 'c2000000-0000-4000-8000-0000000000b1';
  k2  uuid := 'c2000000-0000-4000-8000-0000000000b2';
  adm uuid := '00000000-0000-4000-8200-0000000000ad';
  r   record;
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0200_merge_double_count'),
    '0200 records itself');

  -- A. Put back to another Riyadh day: p1's double is dropped.
  select * into r from competition.merge_fixture_copies(d1, k1, adm, false);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_moved = 0 and r.doubles_dropped = 1,
    'the preview counts the double 0195 clears as dropped, not moved');

  select * into r from competition.merge_fixture_copies(d1, k1, adm, true);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_moved = 0 and r.doubles_dropped = 1,
    'the merge answers the same counts');
  perform pg_temp.check(
    exists (select 1 from prediction.fixture_predictions
             where id = 'c2000000-0000-4000-8000-00000000b001'
               and fixture_id = k1 and not is_double),
    'and they match the rows: p1''s prediction is on K1 without its double');
  perform pg_temp.check(
    exists (select 1 from competition.fixture_merges
             where duplicate_fixture_id = d1 and moved = 2 and doubles_dropped = 1),
    'the merge record keeps the dropped double');
  perform pg_temp.check(
    exists (select 1 from admin.audit_log
             where action = 'fixtures_merged' and target_ref = d1::text
               and reason like '%(doubles 0, doubles dropped 1)%'),
    'and so does the audit line');

  -- B. Put back 12.5 hours within one Riyadh day: the double moves.
  select * into r from competition.merge_fixture_copies(d2, k2, adm, false);
  perform pg_temp.check(
    r.moved = 1 and r.doubles_moved = 1 and r.doubles_dropped = 0,
    'the same Riyadh day: the preview counts the double as moved');
  select * into r from competition.merge_fixture_copies(d2, k2, adm, true);
  perform pg_temp.check(
    r.doubles_moved = 1 and r.doubles_dropped = 0
      and exists (select 1 from prediction.fixture_predictions
                   where id = 'c2000000-0000-4000-8000-00000000b003'
                     and fixture_id = k2 and is_double),
    'and p1''s prediction is on K2 with its double, as counted');

  perform pg_temp.check(
    not has_function_privilege('authenticated',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute')
      and not has_function_privilege('anon',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute'),
    'the clients still cannot call it');
end $$;

rollback;
