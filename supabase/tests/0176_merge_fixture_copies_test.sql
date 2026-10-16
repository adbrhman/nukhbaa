-- End-to-end test of migration 0176: an admin merges a copy of a match into
-- the copy kept (script 95), every trigger on. The 2026-10-15/16 case: the
-- kept copy kicked off already, some players predicted the copy only, one
-- doubled it and had already doubled another match of the kept copy's day.
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
    'select * from competition.merge_fixture_copies(%L, %L, %L, true)',
    p_dup, p_kept, '00000000-0000-4000-8176-0000000000ad'))
$$;

create function pg_temp.on_fixture(p_prediction text) returns text
language sql as $$
  select fixture_id::text from prediction.fixture_predictions
   where id = p_prediction::uuid
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1760000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public'),
  ('c1760000-0000-4000-8000-000000000002', 'Other', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1760000-0000-4000-8000-000000000010', 'c1760000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z'),
  ('c1760000-0000-4000-8000-000000000020', 'c1760000-0000-4000-8000-000000000002',
   '06/2099 b', '2099-05-31 21:00Z', '2099-06-30 21:00Z');

insert into football_data.teams (id, name) values
  ('00000000-0176-4000-8000-000000000001', 'سالزبورغ'),
  ('00000000-0176-4000-8000-000000000002', 'ميلان'),
  ('00000000-0176-4000-8000-000000000003', 'سلتيك'),
  ('00000000-0176-4000-8000-000000000004', 'بنفيكا');

-- Written as before 0175, when both copies could stand: the trigger is off
-- while the test lays down the past, never in the merge.
alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
-- K: the copy kept, 23:00 Riyadh on 1 June. D: the copy, 01:00 on 2 June,
-- one side misspelt. O: another match of 1 June. H: a hidden copy. X: other
-- clubs. T: a test fixture.
insert into competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at, home_team_id, away_team_id, is_test, hidden_at)
values
  ('c1760000-0000-4000-8000-0000000000a0', 'سالزبورغ', 'ميلان', '2099-06-01 20:00Z',
   '00000000-0176-4000-8000-000000000001', '00000000-0176-4000-8000-000000000002', false, null),
  ('c1760000-0000-4000-8000-0000000000d0', 'سالزبورج', 'ميلان', '2099-06-01 22:00Z',
   null, '00000000-0176-4000-8000-000000000002', false, null),
  ('c1760000-0000-4000-8000-0000000000e0', 'سلتيك', 'بنفيكا', '2099-06-01 15:00Z',
   '00000000-0176-4000-8000-000000000003', '00000000-0176-4000-8000-000000000004', false, null),
  ('c1760000-0000-4000-8000-0000000000b0', 'سالزبورغ', 'ميلان', '2099-06-01 21:00Z',
   '00000000-0176-4000-8000-000000000001', '00000000-0176-4000-8000-000000000002', false, now()),
  ('c1760000-0000-4000-8000-0000000000c0', 'سلتيك', 'بنفيكا', '2099-06-01 20:00Z',
   '00000000-0176-4000-8000-000000000003', '00000000-0176-4000-8000-000000000004', false, null),
  ('c1760000-0000-4000-8000-0000000000f0', 'سالزبورغ', 'ميلان', '2099-06-01 20:30Z',
   '00000000-0176-4000-8000-000000000001', '00000000-0176-4000-8000-000000000002', true, null);
alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;

insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1760000-0000-4000-8000-000000000010', 'c1760000-0000-4000-8000-0000000000a0', 0),
  ('c1760000-0000-4000-8000-000000000010', 'c1760000-0000-4000-8000-0000000000d0', 1),
  ('c1760000-0000-4000-8000-000000000010', 'c1760000-0000-4000-8000-0000000000e0', 2),
  ('c1760000-0000-4000-8000-000000000020', 'c1760000-0000-4000-8000-0000000000d0', 0);

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-4000-8176-00000000000' || n)::uuid, 'r176-' || n || '@t.io', now()
  from generate_series(1, 5) n;
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8176-0000000000ad', 'a176@t.io', now());
insert into identity.users (id, email, display_name, created_at)
select ('00000000-0000-4000-8176-00000000000' || n)::uuid, 'r176-' || n || '@t.io',
       'R176-' || n, '2099-05-01'
  from generate_series(1, 5) n;
insert into identity.users (id, email, display_name, role, created_at) values
  ('00000000-0000-4000-8176-0000000000ad', 'a176@t.io', 'A176', 'admin', '2099-05-01');
-- p1..p4 in the month; p5 only in the other competition's season.
insert into competition.participants (id, season_id, user_id, joined_at)
select ('c1760000-0000-4000-8000-0000000001a' || n)::uuid,
       case when n = 5 then 'c1760000-0000-4000-8000-000000000020'::uuid
            else 'c1760000-0000-4000-8000-000000000010'::uuid end,
       ('00000000-0000-4000-8176-00000000000' || n)::uuid, '2099-06-01'
  from generate_series(1, 5) n;

-- p1 doubled D only. p2 doubled O (1 June) and D (2 June). p3 predicted
-- both copies. p4's prediction on D was stamped after K's kickoff. p5 is
-- not in K's season.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values
  ('c1760000-0000-4000-8000-00000000b001', 'c1760000-0000-4000-8000-0000000000d0',
   'c1760000-0000-4000-8000-0000000001a1', 2, 1, true,  '2099-06-01 10:00Z'),
  ('c1760000-0000-4000-8000-00000000b002', 'c1760000-0000-4000-8000-0000000000e0',
   'c1760000-0000-4000-8000-0000000001a2', 0, 0, true,  '2099-06-01 10:00Z'),
  ('c1760000-0000-4000-8000-00000000b003', 'c1760000-0000-4000-8000-0000000000d0',
   'c1760000-0000-4000-8000-0000000001a2', 1, 1, true,  '2099-06-01 11:00Z'),
  ('c1760000-0000-4000-8000-00000000b004', 'c1760000-0000-4000-8000-0000000000a0',
   'c1760000-0000-4000-8000-0000000001a3', 3, 0, false, '2099-06-01 09:00Z'),
  ('c1760000-0000-4000-8000-00000000b005', 'c1760000-0000-4000-8000-0000000000d0',
   'c1760000-0000-4000-8000-0000000001a3', 0, 3, false, '2099-06-01 09:30Z'),
  ('c1760000-0000-4000-8000-00000000b006', 'c1760000-0000-4000-8000-0000000000d0',
   'c1760000-0000-4000-8000-0000000001a4', 1, 0, false, '2099-06-01 20:05Z'),
  ('c1760000-0000-4000-8000-00000000b007', 'c1760000-0000-4000-8000-0000000000d0',
   'c1760000-0000-4000-8000-0000000001a5', 2, 2, false, '2099-06-01 12:00Z');

-- D is the one linked to the provider; K is not.
insert into football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id)
values ('highlightly', 'uel-176', 'fixture', 'c1760000-0000-4000-8000-0000000000d0');

-- Everything moves back to 1 June 1999 (a whole number of days, so every
-- Riyadh day stays as it was): K kicked off long ago. Stamps first, while
-- the kickoffs still allow a write.
update prediction.fixture_predictions
   set submitted_at = submitted_at - interval '36525 days'
 where id::text like 'c1760000-0000-4000-8000-00000000b00%';
alter table competition.fixture_schedules disable trigger fixture_schedules_one_match;
update competition.fixture_schedules
   set kickoff_at = kickoff_at - interval '36525 days'
 where fixture_id::text like 'c1760000-0000-4000-8000-0000000000%';
alter table competition.fixture_schedules enable trigger fixture_schedules_one_match;

do $$
declare
  k   text := 'c1760000-0000-4000-8000-0000000000a0';
  d   text := 'c1760000-0000-4000-8000-0000000000d0';
  o   text := 'c1760000-0000-4000-8000-0000000000e0';
  h   text := 'c1760000-0000-4000-8000-0000000000b0';
  x   text := 'c1760000-0000-4000-8000-0000000000c0';
  t   text := 'c1760000-0000-4000-8000-0000000000f0';
  adm uuid := '00000000-0000-4000-8176-0000000000ad';
  r   record;
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0176_merge_fixture_copies'),
    '0176 records itself');

  -- The kickoff lock without a merge: nothing moves after kickoff.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update prediction.fixture_predictions set fixture_id = %L where id = %L',
      k, 'c1760000-0000-4000-8000-00000000b001')) like '23514/%',
    'moving a prediction to a match that kicked off is refused without a merge');

  -- 1. The preview writes nothing.
  select * into r from competition.merge_fixture_copies(d::uuid, k::uuid, adm, false);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_moved = 1 and r.doubles_dropped = 1
      and r.both_predicted = 1 and r.late = 1 and r.not_participant = 1
      and not r.link_moved and not r.kept_has_result,
    'the preview counts: 2 move (one double kept, one dropped), 1 both, 1 late, 1 not in the season');
  perform pg_temp.check(
    (select hidden_at is null from competition.fixture_schedules where fixture_id = d::uuid)
      and pg_temp.on_fixture('c1760000-0000-4000-8000-00000000b001') = d
      and not exists (select 1 from competition.fixture_merges)
      and not exists (select 1 from admin.audit_log where action = 'fixtures_merged'),
    'and nothing was written');

  -- 2. What is refused.
  perform pg_temp.check(pg_temp.merge_refusal(d, d) = '23514/fixture_merge_same',
    'a fixture into itself is refused');
  perform pg_temp.check(
    pg_temp.merge_refusal(d, 'c1760000-0000-4000-8000-0000000000ff') = '23514/fixture_merge_not_found',
    'a fixture with no schedule is refused');
  perform pg_temp.check(pg_temp.merge_refusal(d, h) = '23514/fixture_merge_kept_hidden',
    'keeping a hidden copy is refused');
  perform pg_temp.check(pg_temp.merge_refusal(d, t) = '23514/fixture_merge_test',
    'a test fixture is refused');
  perform pg_temp.check(pg_temp.merge_refusal(x, k) = '23514/fixture_merge_not_copies',
    'two matches with no club in common are refused');

  -- 3. The merge.
  select * into r from competition.merge_fixture_copies(d::uuid, k::uuid, adm, true);
  perform pg_temp.check(
    r.moved = 2 and r.doubles_moved = 1 and r.doubles_dropped = 1
      and r.both_predicted = 1 and r.late = 1 and r.not_participant = 1
      and r.link_moved,
    'the merge answers what it did');
  perform pg_temp.check(
    (select hidden_at is not null from competition.fixture_schedules where fixture_id = d::uuid),
    'the copy is hidden');
  perform pg_temp.check(
    exists (select 1 from prediction.fixture_predictions
             where id = 'c1760000-0000-4000-8000-00000000b001'
               and fixture_id = k::uuid and is_double
               and home_goals = 2 and away_goals = 1
               and submitted_at = '1999-06-01 10:00Z'),
    'p1''s prediction is on the kept copy: the same id, scoreline, stamp and double');
  perform pg_temp.check(
    exists (select 1 from prediction.fixture_predictions
             where id = 'c1760000-0000-4000-8000-00000000b003'
               and fixture_id = k::uuid and not is_double),
    'p2''s moves without its double: O keeps the day''s one double');
  perform pg_temp.check(
    (select is_double from prediction.fixture_predictions
      where id = 'c1760000-0000-4000-8000-00000000b002'),
    'p2''s double on O is untouched');
  perform pg_temp.check(
    pg_temp.on_fixture('c1760000-0000-4000-8000-00000000b005') = d
      and pg_temp.on_fixture('c1760000-0000-4000-8000-00000000b004') = k
      and pg_temp.on_fixture('c1760000-0000-4000-8000-00000000b006') = d
      and pg_temp.on_fixture('c1760000-0000-4000-8000-00000000b007') = d,
    'both predicted, late and not in the season stay where they were');
  perform pg_temp.check(
    (select canonical_id::text from football_data.external_identity_map
      where external_id = 'uel-176') = k,
    'the provider link is now the kept copy''s');
  perform pg_temp.check(
    exists (select 1 from competition.fixture_merges
             where duplicate_fixture_id = d::uuid and kept_fixture_id = k::uuid
               and merged_by = adm and moved = 2 and doubles_dropped = 1),
    'the merge is recorded');
  perform pg_temp.check(
    exists (select 1 from admin.audit_log
             where action = 'fixtures_merged' and actor_id = adm
               and target_ref = d and reason like 'into ' || k || ': moved 2 %'
               and reason like '%provider link moved'),
    'and audited');

  -- 4. The exemption is for that merge's moves only.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update prediction.fixture_predictions set fixture_id = %L where id = %L',
      k, 'c1760000-0000-4000-8000-00000000b006')) like '23514/%',
    'a late prediction still cannot be moved after kickoff');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update prediction.fixture_predictions set fixture_id = %L where id = %L',
      k, 'c1760000-0000-4000-8000-00000000b002')) like '23514/%',
    'nor one of another match');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update prediction.fixture_predictions set home_goals = 5 where id = %L',
      'c1760000-0000-4000-8000-00000000b001')) like '23514/%',
    'a moved prediction is locked like any other after kickoff');

  -- 5. A merged copy stays merged and hidden.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'update competition.fixture_schedules set hidden_at = null where fixture_id = %L', d))
      = '23514/fixture_schedules_merged',
    'the merged copy is never shown again');
  perform pg_temp.check(pg_temp.merge_refusal(d, k) = '23514/fixture_merge_already_merged',
    'and is never merged twice');

  -- 6. The kept copy's result is reported, for the server to score it.
  insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at)
  values (k::uuid, 2, 1, now());
  select * into r from competition.merge_fixture_copies(h::uuid, k::uuid, adm, false);
  perform pg_temp.check(r.kept_has_result and r.moved = 0,
    'a hidden copy can be previewed into a kept copy with a result');

  perform pg_temp.check(
    not has_function_privilege('authenticated',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute')
      and not has_function_privilege('anon',
      'competition.merge_fixture_copies(uuid, uuid, uuid, boolean)', 'execute'),
    'the clients cannot call it');
end $$;

rollback;
