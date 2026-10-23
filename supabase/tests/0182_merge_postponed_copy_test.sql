-- End-to-end test of migration 0182: a match the provider put back to the
-- next day after its first kickoff passed (script 137). The 2026-10-23
-- case: the admin hid the first copy and added the match again a day later;
-- some players predicted only the first copy, one of them doubled it and
-- had already doubled another match of the new day. The merge goes through
-- competition.merge_fixture_copies, every trigger on. Rolled back at the end.
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

-- The SQLSTATE and constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_state text;
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate,
                          v_constraint = constraint_name;
  return v_state || '/' || coalesce(v_constraint, '');
end $$;

create function pg_temp.merge_refusal(p_dup text, p_kept text) returns text
language sql as $$
  select pg_temp.refusal(format(
    'select * from competition.merge_fixture_copies(%L, %L, %L, false)',
    p_dup, p_kept, '00000000-0000-4000-8182-0000000000ad'))
$$;

create function pg_temp.on_fixture(p_prediction text) returns text
language sql as $$
  select fixture_id::text from prediction.fixture_predictions
   where id = p_prediction::uuid
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1820000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public'),
  ('c1820000-0000-4000-8000-000000000002', 'Other', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z'),
  ('c1820000-0000-4000-8000-000000000020', 'c1820000-0000-4000-8000-000000000002',
   '06/2099 b', '2099-05-31 21:00Z', '2099-06-30 21:00Z');

insert into football_data.teams (id, name) values
  ('00000000-0182-4000-8000-000000000001', 'الأهلي'),
  ('00000000-0182-4000-8000-000000000002', 'الخليج'),
  ('00000000-0182-4000-8000-000000000003', 'الاتحاد'),
  ('00000000-0182-4000-8000-000000000004', 'الشباب');

-- D: the first copy, 21:00 Riyadh on 10 June. K: the copy kept, the same
-- match 24 hours later. O: another match of 11 June. W: the same match 8
-- days after D. S: the same clubs, home and away swapped, on 11 June. X:
-- the same match on 12 June, in the other competition's season only.
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test, hidden_at)
values
  ('c1820000-0000-4000-8000-0000000000d0', 'الأهلي', 'الخليج', '2099-06-10 18:00Z',
   '00000000-0182-4000-8000-000000000001', '00000000-0182-4000-8000-000000000002', false, null),
  ('c1820000-0000-4000-8000-0000000000a0', 'الأهلي', 'الخليج', '2099-06-11 18:00Z',
   '00000000-0182-4000-8000-000000000001', '00000000-0182-4000-8000-000000000002', false, null),
  ('c1820000-0000-4000-8000-0000000000e0', 'الاتحاد', 'الشباب', '2099-06-11 15:00Z',
   '00000000-0182-4000-8000-000000000003', '00000000-0182-4000-8000-000000000004', false, null),
  ('c1820000-0000-4000-8000-0000000000c0', 'الأهلي', 'الخليج', '2099-06-18 18:00Z',
   '00000000-0182-4000-8000-000000000001', '00000000-0182-4000-8000-000000000002', false, null),
  ('c1820000-0000-4000-8000-0000000000b0', 'الخليج', 'الأهلي', '2099-06-13 18:00Z',
   '00000000-0182-4000-8000-000000000002', '00000000-0182-4000-8000-000000000001', false, null),
  ('c1820000-0000-4000-8000-0000000000f0', 'الأهلي', 'الخليج', '2099-06-15 18:00Z',
   '00000000-0182-4000-8000-000000000001', '00000000-0182-4000-8000-000000000002', false, null);

insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-0000000000d0', 0),
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-0000000000a0', 1),
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-0000000000e0', 2),
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-0000000000c0', 3),
  ('c1820000-0000-4000-8000-000000000010', 'c1820000-0000-4000-8000-0000000000b0', 4),
  ('c1820000-0000-4000-8000-000000000020', 'c1820000-0000-4000-8000-0000000000f0', 0);

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-4000-8182-00000000000' || n)::uuid, 'r182-' || n || '@t.io', now()
  from generate_series(1, 3) n;
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8182-0000000000ad', 'a182@t.io', now());
insert into identity.users (id, email, display_name, created_at)
select ('00000000-0000-4000-8182-00000000000' || n)::uuid, 'r182-' || n || '@t.io',
       'R182-' || n, '2099-05-01'
  from generate_series(1, 3) n;
insert into identity.users (id, email, display_name, role, created_at) values
  ('00000000-0000-4000-8182-0000000000ad', 'a182@t.io', 'A182', 'admin', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1820000-0000-4000-8000-0000000001a' || n)::uuid,
       'c1820000-0000-4000-8000-000000000010'::uuid,
       ('00000000-0000-4000-8182-00000000000' || n)::uuid, '2099-06-01'
  from generate_series(1, 3) n;

-- p1 doubled D, and O on K's day. p2 predicted both copies. p3 predicted
-- D only.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  ('c1820000-0000-4000-8000-00000000b001', 'c1820000-0000-4000-8000-0000000000d0',
   'c1820000-0000-4000-8000-0000000001a1', 2, 0, true,  '2099-06-10 10:00Z'),
  ('c1820000-0000-4000-8000-00000000b002', 'c1820000-0000-4000-8000-0000000000e0',
   'c1820000-0000-4000-8000-0000000001a1', 1, 1, true,  '2099-06-10 10:05Z'),
  ('c1820000-0000-4000-8000-00000000b003', 'c1820000-0000-4000-8000-0000000000d0',
   'c1820000-0000-4000-8000-0000000001a2', 1, 0, false, '2099-06-10 11:00Z'),
  ('c1820000-0000-4000-8000-00000000b004', 'c1820000-0000-4000-8000-0000000000a0',
   'c1820000-0000-4000-8000-0000000001a2', 3, 1, false, '2099-06-11 09:00Z'),
  ('c1820000-0000-4000-8000-00000000b005', 'c1820000-0000-4000-8000-0000000000d0',
   'c1820000-0000-4000-8000-0000000001a3', 0, 1, false, '2099-06-10 12:00Z');

-- The provider match is linked to D, as the sync left it.
insert into football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id)
values ('highlightly', 'spl-182', 'fixture', 'c1820000-0000-4000-8000-0000000000d0');

-- Everything moves back to 1999 (a whole number of days, so every Riyadh
-- day stays as it was): both copies kicked off long ago, K as well. Stamps
-- first, while the kickoffs still allow a write.
update prediction.fixture_predictions
   set submitted_at = submitted_at - interval '36525 days'
 where id::text like 'c1820000-0000-4000-8000-00000000b00%';
alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
update competition.fixture_schedules
   set kickoff_at = kickoff_at - interval '36525 days'
 where fixture_id::text like 'c1820000-0000-4000-8000-0000000000%';
alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;

-- Then the admin hid D (0098), once the provider put it back.
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c1820000-0000-4000-8000-0000000000d0';

do $$
declare
  d   text := 'c1820000-0000-4000-8000-0000000000d0';
  k   text := 'c1820000-0000-4000-8000-0000000000a0';
  w   text := 'c1820000-0000-4000-8000-0000000000c0';
  s   text := 'c1820000-0000-4000-8000-0000000000b0';
  x   text := 'c1820000-0000-4000-8000-0000000000f0';
  adm uuid := '00000000-0000-4000-8182-0000000000ad';
  r   record;
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0182_merge_postponed_copy'),
    '0182 records itself');

  -- 1. What still is not one match.
  perform pg_temp.check(pg_temp.merge_refusal(d, w) = '23514/fixture_merge_not_copies',
    'a copy more than 7 days later is refused');
  perform pg_temp.check(pg_temp.merge_refusal(d, s) = '23514/fixture_merge_not_copies',
    'the same clubs with home and away swapped are refused');
  perform pg_temp.check(pg_temp.merge_refusal(d, x) = '23514/fixture_merge_not_copies',
    'a copy in no season of the first one is refused');
  perform pg_temp.check(pg_temp.merge_refusal(w, k) = '23514/fixture_merge_not_copies',
    'a kept copy earlier than the copy, 12 hours or more, is refused');
  perform pg_temp.check(pg_temp.merge_refusal(k, d) = '23514/fixture_merge_kept_hidden',
    'keeping the hidden first copy is still refused');

  -- 2. The preview writes nothing.
  select * into r from competition.merge_fixture_copies(d::uuid, k::uuid, adm, false);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_moved = 0 and r.doubles_dropped = 1
      and r.both_predicted = 1 and r.late = 0 and r.not_participant = 0
      and not r.link_moved and not r.kept_has_result,
    'the preview counts: 2 move (the double dropped, O keeps the day''s), 1 both');
  perform pg_temp.check(
    pg_temp.on_fixture('c1820000-0000-4000-8000-00000000b001') = d
      and not exists (select 1 from competition.fixture_merges
                       where duplicate_fixture_id = d::uuid),
    'and nothing was written');

  -- 3. The merge.
  select * into r from competition.merge_fixture_copies(d::uuid, k::uuid, adm, true);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_dropped = 1 and r.both_predicted = 1 and r.link_moved,
    'the merge answers what it did, the provider link with it');
  perform pg_temp.check(
    exists (select 1 from prediction.fixture_predictions
             where id = 'c1820000-0000-4000-8000-00000000b001'
               and fixture_id = k::uuid and not is_double
               and home_goals = 2 and away_goals = 0
               and submitted_at = '1999-06-10 10:00Z'),
    'p1''s prediction is on the kept copy: the same id, scoreline and stamp, no double');
  perform pg_temp.check(
    (select is_double from prediction.fixture_predictions
      where id = 'c1820000-0000-4000-8000-00000000b002'),
    'p1''s double on O is untouched');
  perform pg_temp.check(
    pg_temp.on_fixture('c1820000-0000-4000-8000-00000000b005') = k
      and pg_temp.on_fixture('c1820000-0000-4000-8000-00000000b003') = d
      and pg_temp.on_fixture('c1820000-0000-4000-8000-00000000b004') = k,
    'p3''s moves; p2''s first stays on the copy and the kept one stands');
  perform pg_temp.check(
    (select canonical_id::text from football_data.external_identity_map
      where external_id = 'spl-182') = k,
    'the provider link is now the kept copy''s');
  perform pg_temp.check(
    exists (select 1 from admin.audit_log
             where action = 'fixtures_merged' and actor_id = adm
               and target_ref = d and reason like 'into ' || k || ': moved 2 %'),
    'and audited');

  -- 4. A moved prediction is locked like any other after kickoff.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update prediction.fixture_predictions set home_goals = 5 where id = %L',
      'c1820000-0000-4000-8000-00000000b005')) like '23514/%',
    'a moved prediction cannot be changed after the kept copy''s kickoff');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update competition.fixture_schedules set hidden_at = null where fixture_id = %L', d))
      = '23514/fixture_schedules_merged',
    'the merged copy is never shown again');
  perform pg_temp.check(
    not has_function_privilege('authenticated',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute')
      and not has_function_privilege('anon',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute'),
    'the clients still cannot call it');
end $$;

rollback;
