-- End-to-end test for migration 0171: scoring.my_fixture_scores returns a
-- user's own predictions that have a score or a recorded result -- the
-- grade, the points and the final score -- and nothing of anyone else's.
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
  ('c8171000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c8171000-0000-4000-8000-000000000010', 'c8171000-0000-4000-8000-000000000001',
   '07/2099', '2099-06-30 21:00Z', '2099-07-31 21:00Z');
-- Kickoffs far in the future so the kickoff trigger accepts the predictions.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8171000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-07-01 18:00Z'),
  ('c8171000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-07-01 18:00Z'),
  ('c8171000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-07-01 18:00Z'),
  ('c8171000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-07-01 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8171000-0000-4000-8000-000000000010', 'c8171000-0000-4000-8000-0000000000f1', 0),
  ('c8171000-0000-4000-8000-000000000010', 'c8171000-0000-4000-8000-0000000000f2', 1),
  ('c8171000-0000-4000-8000-000000000010', 'c8171000-0000-4000-8000-0000000000f3', 2),
  ('c8171000-0000-4000-8000-000000000010', 'c8171000-0000-4000-8000-0000000000f4', 3);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8171-000000000001', 'u1-171@t.io', now()),
  ('00000000-0000-4000-8171-000000000002', 'u2-171@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8171-000000000001', 'u1-171@t.io', 'U1-171', '2099-06-01'),
  ('00000000-0000-4000-8171-000000000002', 'u2-171@t.io', 'U2-171', '2099-06-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c8171000-0000-4000-8000-0000000000a1', 'c8171000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8171-000000000001', '2099-07-01'),
  ('c8171000-0000-4000-8000-0000000000a2', 'c8171000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8171-000000000002', '2099-07-01');

-- u1: f1 scored (result 1-0), f2 result recorded but not scored yet,
--     f3 neither.
-- u2: f1 scored too, and f4 scored -- a fixture u1 never predicted.
insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c8171000-0000-4000-8000-00000000b011', 'c8171000-0000-4000-8000-0000000000f1', 'c8171000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('c8171000-0000-4000-8000-00000000b021', 'c8171000-0000-4000-8000-0000000000f2', 'c8171000-0000-4000-8000-0000000000a1', 2, 2, false, now()),
  ('c8171000-0000-4000-8000-00000000b031', 'c8171000-0000-4000-8000-0000000000f3', 'c8171000-0000-4000-8000-0000000000a1', 0, 1, false, now()),
  ('c8171000-0000-4000-8000-00000000b012', 'c8171000-0000-4000-8000-0000000000f1', 'c8171000-0000-4000-8000-0000000000a2', 3, 3, false, now()),
  ('c8171000-0000-4000-8000-00000000b042', 'c8171000-0000-4000-8000-0000000000f4', 'c8171000-0000-4000-8000-0000000000a2', 1, 1, false, now());

insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c8171000-0000-4000-8000-0000000000f1', 1, 0, '2099-07-01 20:00Z'),
  ('c8171000-0000-4000-8000-0000000000f2', 2, 1, '2099-07-01 20:00Z'),
  ('c8171000-0000-4000-8000-0000000000f4', 1, 1, '2099-07-01 20:00Z');

insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c8171000-0000-4000-8000-0000000000f1', 'c8171000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c8171000-0000-4000-8000-0000000000f1', 'c8171000-0000-4000-8000-0000000000a2', 1, 'incorrect', 0),
  ('c8171000-0000-4000-8000-0000000000f4', 'c8171000-0000-4000-8000-0000000000a2', 1, 'exact_scoreline', 3);

do $$
declare
  got text;
begin
  select string_agg(
           format('%s|%s|%s|%s|%s-%s',
                  right(participant_id::text, 2), right(fixture_id::text, 2),
                  coalesce(grade, '-'), coalesce(points::text, '-'),
                  coalesce(result_home_goals::text, '-'),
                  coalesce(result_away_goals::text, '-')),
           ',' order by fixture_id, participant_id)
    into got
    from scoring.my_fixture_scores('00000000-0000-4000-8171-000000000001');
  perform pg_temp.check(
    got = 'a1|f1|exact_scoreline|3|1-0,a1|f2|-|-|2-1',
    'u1: the scored call with its points and final score, the recorded '
    'result not scored yet, and nothing for the match with neither (got '
    || coalesce(got, 'nothing') || ')');

  select string_agg(
           format('%s|%s|%s|%s', right(participant_id::text, 2),
                  right(fixture_id::text, 2), grade, points),
           ',' order by fixture_id, participant_id)
    into got
    from scoring.my_fixture_scores('00000000-0000-4000-8171-000000000002');
  perform pg_temp.check(
    got = 'a2|f1|incorrect|0,a2|f4|exact_scoreline|3',
    'u2 sees only their own rows, u1''s f1 score is not among them (got '
    || coalesce(got, 'nothing') || ')');

  perform pg_temp.check(
    (select count(*) from scoring.my_fixture_scores(
       '00000000-0000-4000-8171-0000000000ff')) = 0,
    'a user with no predictions gets no rows');

  insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
    ('c8171000-0000-4000-8000-0000000000f2', 'c8171000-0000-4000-8000-0000000000a1', 1, 'correct_outcome', 1);
  perform pg_temp.check(
    (select grade = 'correct_outcome' and points = 1
       from scoring.my_fixture_scores('00000000-0000-4000-8171-000000000001')
      where right(fixture_id::text, 2) = 'f2'),
    'once scored, the waiting row carries its grade and points');

  perform pg_temp.check(
    not has_function_privilege('anon', 'scoring.my_fixture_scores(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'scoring.my_fixture_scores(uuid)', 'execute'),
    'the browser roles cannot call it; only the server reads it');
end $$;

rollback;
