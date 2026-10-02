-- End-to-end test for migration 0079: one double per participant per
-- kickoff day (the Riyadh day since 0083), enforced by the database
-- itself. Rolled back at the end.
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
  ('c7900000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c7900000-0000-4000-8000-000000000010', 'c7900000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- Far in the future, so the kickoff trigger never refuses these writes.
-- f1, f2: the same day (in Riyadh and in UTC alike). f3: the next day.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c7900000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c7900000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 19:30Z'),
  ('c7900000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-02 01:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c7900000-0000-4000-8000-000000000010', 'c7900000-0000-4000-8000-0000000000f1', 0),
  ('c7900000-0000-4000-8000-000000000010', 'c7900000-0000-4000-8000-0000000000f2', 1),
  ('c7900000-0000-4000-8000-000000000010', 'c7900000-0000-4000-8000-0000000000f3', 2);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8079-000000000001', 'd1@t.io', now()),
  ('00000000-0000-4000-8079-000000000002', 'd2@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8079-000000000001', 'd1@t.io', 'D1', '2099-05-01'),
  ('00000000-0000-4000-8079-000000000002', 'd2@t.io', 'D2', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c7900000-0000-4000-8000-0000000000a1', 'c7900000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8079-000000000001', '2099-06-01'),
  ('c7900000-0000-4000-8000-0000000000a2', 'c7900000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8079-000000000002', '2099-06-01');

do $$
begin
  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c7900000-0000-4000-8000-00000000b001', 'c7900000-0000-4000-8000-0000000000f1',
          'c7900000-0000-4000-8000-0000000000a1', 2, 1, true, now());
  perform pg_temp.check(true, 'the first double of the day is accepted');

  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into prediction.fixture_predictions
        (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
      values ('c7900000-0000-4000-8000-00000000b002', 'c7900000-0000-4000-8000-0000000000f2',
              'c7900000-0000-4000-8000-0000000000a1', 1, 1, true, now())
    $q$) = '23514/fixture_predictions_one_double_per_day',
    'a second double on the same day is refused by name');

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c7900000-0000-4000-8000-00000000b002', 'c7900000-0000-4000-8000-0000000000f2',
          'c7900000-0000-4000-8000-0000000000a1', 1, 1, false, now());
  perform pg_temp.check(true, 'the same fixture without the double is accepted');

  perform pg_temp.check(
    pg_temp.refusal($q$
      update prediction.fixture_predictions set is_double = true
       where id = 'c7900000-0000-4000-8000-00000000b002'
    $q$) = '23514/fixture_predictions_one_double_per_day',
    'turning a second fixture of the day into a double is refused');

  update prediction.fixture_predictions
     set home_goals = 3, is_double = true
   where id = 'c7900000-0000-4000-8000-00000000b001';
  perform pg_temp.check(true, 'amending the day''s own double keeps it');

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c7900000-0000-4000-8000-00000000b003', 'c7900000-0000-4000-8000-0000000000f3',
          'c7900000-0000-4000-8000-0000000000a1', 0, 0, true, now());
  perform pg_temp.check(true, 'the next day has its own double');

  insert into prediction.fixture_predictions
    (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
  values ('c7900000-0000-4000-8000-00000000b004', 'c7900000-0000-4000-8000-0000000000f2',
          'c7900000-0000-4000-8000-0000000000a2', 1, 0, true, now());
  perform pg_temp.check(true, 'another participant''s double is independent');

  update prediction.fixture_predictions set is_double = false
   where id = 'c7900000-0000-4000-8000-00000000b001';
  update prediction.fixture_predictions set is_double = true
   where id = 'c7900000-0000-4000-8000-00000000b002';
  perform pg_temp.check(
    (select count(*) from prediction.fixture_predictions
      where participant_id = 'c7900000-0000-4000-8000-0000000000a1'
        and is_double
        and fixture_id in ('c7900000-0000-4000-8000-0000000000f1',
                           'c7900000-0000-4000-8000-0000000000f2')) = 1,
    'moving the double to another fixture of the day is accepted');
end $$;

rollback;
