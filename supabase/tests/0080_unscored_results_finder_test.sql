-- End-to-end test for migration 0080: a recorded result with an unscored
-- prediction is found; a fully scored one, one outside the window, and a
-- fixture nobody predicted are not. Rolled back at the end.
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
  ('c8000000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c8000000-0000-4000-8000-000000000010', 'c8000000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- Kickoffs far in the future so the kickoff trigger accepts the predictions.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8000000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c8000000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 18:00Z'),
  ('c8000000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-01 18:00Z'),
  ('c8000000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-06-01 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8000000-0000-4000-8000-000000000010', 'c8000000-0000-4000-8000-0000000000f1', 0),
  ('c8000000-0000-4000-8000-000000000010', 'c8000000-0000-4000-8000-0000000000f2', 1),
  ('c8000000-0000-4000-8000-000000000010', 'c8000000-0000-4000-8000-0000000000f3', 2),
  ('c8000000-0000-4000-8000-000000000010', 'c8000000-0000-4000-8000-0000000000f4', 3);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8080-000000000001', 'u1@t.io', now()),
  ('00000000-0000-4000-8080-000000000002', 'u2@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8080-000000000001', 'u1@t.io', 'U1', '2099-05-01'),
  ('00000000-0000-4000-8080-000000000002', 'u2@t.io', 'U2', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c8000000-0000-4000-8000-0000000000a1', 'c8000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8080-000000000001', '2099-06-01'),
  ('c8000000-0000-4000-8000-0000000000a2', 'c8000000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8080-000000000002', '2099-06-01');

-- f1: two predictions, only one scored -> unfinished.
-- f2: one prediction, scored -> finished.
-- f3: one prediction, unscored, but its result is outside the window.
-- f4: a result nobody predicted -> nothing to score.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c8000000-0000-4000-8000-00000000b011', 'c8000000-0000-4000-8000-0000000000f1', 'c8000000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('c8000000-0000-4000-8000-00000000b012', 'c8000000-0000-4000-8000-0000000000f1', 'c8000000-0000-4000-8000-0000000000a2', 2, 2, false, now()),
  ('c8000000-0000-4000-8000-00000000b021', 'c8000000-0000-4000-8000-0000000000f2', 'c8000000-0000-4000-8000-0000000000a1', 0, 0, false, now()),
  ('c8000000-0000-4000-8000-00000000b031', 'c8000000-0000-4000-8000-0000000000f3', 'c8000000-0000-4000-8000-0000000000a1', 3, 1, false, now());

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c8000000-0000-4000-8000-0000000000f1', 1, 0, '2099-06-01 20:10Z'),
  ('c8000000-0000-4000-8000-0000000000f2', 0, 0, '2099-06-01 20:05Z'),
  ('c8000000-0000-4000-8000-0000000000f3', 3, 1, '2099-05-20 20:00Z'),
  ('c8000000-0000-4000-8000-0000000000f4', 2, 1, '2099-06-01 20:00Z');

insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c8000000-0000-4000-8000-0000000000f1', 'c8000000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c8000000-0000-4000-8000-0000000000f2', 'c8000000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3);

do $$
declare
  found text;
begin
  select string_agg(fixture_id::text, ',') into found
    from scoring.fixtures_with_unscored_predictions(
      '2099-05-29 00:00Z', '2099-06-02 00:00Z', 10);
  perform pg_temp.check(
    found = 'c8000000-0000-4000-8000-0000000000f1',
    'only the result with an unscored prediction, inside the window, is found');

  perform pg_temp.check(
    (select count(*) from scoring.fixtures_with_unscored_predictions(
       '2099-05-29 00:00Z', '2099-06-01 20:10Z', 10)) = 0,
    'a result recorded at the window end is left for the next run');

  select string_agg(fixture_id::text, ',' order by fixture_id) into found
    from scoring.fixtures_with_unscored_predictions(
      '2099-05-01 00:00Z', '2099-06-02 00:00Z', 10);
  perform pg_temp.check(
    found = 'c8000000-0000-4000-8000-0000000000f1,c8000000-0000-4000-8000-0000000000f3',
    'a wider window reaches the older unfinished result too');

  perform pg_temp.check(
    (select count(*) from scoring.fixtures_with_unscored_predictions(
       '2099-05-01 00:00Z', '2099-06-02 00:00Z', 1)) = 1,
    'the limit caps one run');

  insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
    ('c8000000-0000-4000-8000-0000000000f1', 'c8000000-0000-4000-8000-0000000000a2', 1, 'incorrect', 0);
  perform pg_temp.check(
    (select count(*) from scoring.fixtures_with_unscored_predictions(
       '2099-05-29 00:00Z', '2099-06-02 00:00Z', 10)) = 0,
    'once every prediction is scored the fixture is no longer found');
end $$;

rollback;
