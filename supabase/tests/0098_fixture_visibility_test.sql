-- End-to-end test for migration 0098: hidden and test fixtures, enforced by
-- the database itself. Rolled back at the end.
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

insert into competition.competitions (id, name, format, visibility) values
  ('c9800000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c9800000-0000-4000-8000-000000000010', 'c9800000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- f1: an ordinary fixture. f2: hidden later. f3: a test fixture.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c9800000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c9800000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 19:00Z');
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at, is_test) values
  ('c9800000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-01 20:00Z', true);
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c9800000-0000-4000-8000-000000000010', 'c9800000-0000-4000-8000-0000000000f1', 0),
  ('c9800000-0000-4000-8000-000000000010', 'c9800000-0000-4000-8000-0000000000f2', 1),
  ('c9800000-0000-4000-8000-000000000010', 'c9800000-0000-4000-8000-0000000000f3', 2);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8098-000000000001', 'p98@t.io', now()),
  ('00000000-0000-4000-8098-000000000002', 'a98@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8098-000000000001', 'p98@t.io', 'P98', '2099-05-01');
insert into identity.users (id, email, display_name, created_at, role) values
  ('00000000-0000-4000-8098-000000000002', 'a98@t.io', 'A98', '2099-05-01', 'admin');
-- a1: a player. a2: an admin.
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c9800000-0000-4000-8000-0000000000a1', 'c9800000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8098-000000000001', '2099-06-01'),
  ('c9800000-0000-4000-8000-0000000000a2', 'c9800000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8098-000000000002', '2099-06-01');

do $$
begin
  perform pg_temp.check(
    (select hidden_at is null and not is_test
       from competition.fixture_schedules
      where fixture_id = 'c9800000-0000-4000-8000-0000000000f1'),
    'a fixture is visible and real by default');

  -- A prediction made before the fixture is hidden stays.
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c9800000-0000-4000-8000-00000000b001', 'c9800000-0000-4000-8000-0000000000f2',
          'c9800000-0000-4000-8000-0000000000a1', 1, 0, false, now());

  update competition.fixture_schedules set hidden_at = now()
   where fixture_id = 'c9800000-0000-4000-8000-0000000000f2';
  perform pg_temp.check(
    (select count(*) from prediction.fixture_predictions
      where fixture_id = 'c9800000-0000-4000-8000-0000000000f2') = 1,
    'hiding a fixture keeps its predictions');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into prediction.fixture_predictions
        (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
      values ('c9800000-0000-4000-8000-00000000b002', 'c9800000-0000-4000-8000-0000000000f2',
              'c9800000-0000-4000-8000-0000000000a2', 2, 2, false, now())
    $q$) = '23514/fixture_predictions_fixture_hidden',
    'nobody can predict a hidden fixture');

  perform pg_temp.check(
    pg_temp.refusal($q$
      update prediction.fixture_predictions set home_goals = 3
       where id = 'c9800000-0000-4000-8000-00000000b001'
    $q$) = '23514/fixture_predictions_fixture_hidden',
    'a prediction on a hidden fixture cannot be amended');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into scoring.fixture_scores
        (fixture_id, participant_id, ruleset_version, grade, points)
      values ('c9800000-0000-4000-8000-0000000000f2',
              'c9800000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3)
    $q$) = '23514/fixture_scores_fixture_unavailable',
    'a hidden fixture is not scored');

  update competition.fixture_schedules set hidden_at = null
   where fixture_id = 'c9800000-0000-4000-8000-0000000000f2';
  update prediction.fixture_predictions set home_goals = 3
   where id = 'c9800000-0000-4000-8000-00000000b001';
  perform pg_temp.check(true, 'shown again, the fixture takes predictions');

  perform pg_temp.check(
    pg_temp.refusal($q$
      update competition.fixture_schedules set is_test = true
       where fixture_id = 'c9800000-0000-4000-8000-0000000000f1'
    $q$) = '23514/fixture_schedules_is_test_fixed',
    'a real fixture cannot become a test fixture');

  perform pg_temp.check(
    pg_temp.refusal($q$
      update competition.fixture_schedules set is_test = false
       where fixture_id = 'c9800000-0000-4000-8000-0000000000f3'
    $q$) = '23514/fixture_schedules_is_test_fixed',
    'a test fixture cannot become a real one');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into prediction.fixture_predictions
        (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
      values ('c9800000-0000-4000-8000-00000000b003', 'c9800000-0000-4000-8000-0000000000f3',
              'c9800000-0000-4000-8000-0000000000a1', 1, 1, false, now())
    $q$) = '23514/fixture_predictions_test_fixture_admins_only',
    'a player cannot predict a test fixture');

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c9800000-0000-4000-8000-00000000b004', 'c9800000-0000-4000-8000-0000000000f3',
          'c9800000-0000-4000-8000-0000000000a2', 2, 0, false, now());
  perform pg_temp.check(true, 'an admin predicts a test fixture');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into scoring.fixture_scores
        (fixture_id, participant_id, ruleset_version, grade, points)
      values ('c9800000-0000-4000-8000-0000000000f3',
              'c9800000-0000-4000-8000-0000000000a2', 1, 'exact_scoreline', 3)
    $q$) = '23514/fixture_scores_fixture_unavailable',
    'a test fixture is never scored');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into ledger.fixture_point_entries
        (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
      values ('c9800000-0000-4000-8000-00000000e001',
              'c9800000-0000-4000-8000-0000000000a2',
              'c9800000-0000-4000-8000-0000000000f3', 'fixture_score', 3,
              'fixture_score:test', now())
    $q$) = '23514/fixture_point_entries_test_fixture',
    'a test fixture never reaches the ledger');

  insert into scoring.fixture_scores
    (fixture_id, participant_id, ruleset_version, grade, points)
  values ('c9800000-0000-4000-8000-0000000000f1',
          'c9800000-0000-4000-8000-0000000000a1', 1, 'incorrect', 0);
  insert into ledger.fixture_point_entries
    (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
  values ('c9800000-0000-4000-8000-00000000e002',
          'c9800000-0000-4000-8000-0000000000a1',
          'c9800000-0000-4000-8000-0000000000f1', 'fixture_score', 0,
          'fixture_score:real', now());
  perform pg_temp.check(true, 'a real fixture is scored and posted as before');
end $$;

-- The rescore sweep: results for all three, each with an unscored prediction.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
values ('c9800000-0000-4000-8000-00000000b005', 'c9800000-0000-4000-8000-0000000000f1',
        'c9800000-0000-4000-8000-0000000000a2', 0, 0, false, now());
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c9800000-0000-4000-8000-0000000000f1', 1, 0, '2099-06-01 20:10Z'),
  ('c9800000-0000-4000-8000-0000000000f2', 0, 0, '2099-06-01 21:10Z'),
  ('c9800000-0000-4000-8000-0000000000f3', 2, 0, '2099-06-01 22:10Z');
update competition.fixture_schedules set hidden_at = now()
 where fixture_id = 'c9800000-0000-4000-8000-0000000000f2';

do $$
begin
  perform pg_temp.check(
    array(select fixture_id::text
            from scoring.fixtures_with_unscored_predictions(
                   '2099-06-01 00:00Z', '2099-06-02 00:00Z', 10))
      = array['c9800000-0000-4000-8000-0000000000f1'],
    'the sweep finds the real fixture and leaves the hidden and test ones');
end $$;

update competition.fixture_schedules set hidden_at = null
 where fixture_id = 'c9800000-0000-4000-8000-0000000000f2';

do $$
begin
  perform pg_temp.check(
    array(select fixture_id::text
            from scoring.fixtures_with_unscored_predictions(
                   '2099-06-01 00:00Z', '2099-06-02 00:00Z', 10))
      = array['c9800000-0000-4000-8000-0000000000f1',
              'c9800000-0000-4000-8000-0000000000f2'],
    'shown again, the fixture goes back to the sweep');
end $$;

rollback;
