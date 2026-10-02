-- End-to-end test for migration 0082: a scored fixture whose ledger post is
-- missing or out of date is found by the rescore sweep; one whose ledger
-- matches is not, and a streak bonus does not count as unposted points.
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

create function pg_temp.found() returns text language sql as $$
  select coalesce(string_agg(fixture_id::text, ',' order by fixture_id), '')
    from scoring.fixtures_with_unscored_predictions(
      '2099-05-29 00:00Z', '2099-06-02 00:00Z', 10)
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c8200000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- Kickoffs far in the future so the kickoff trigger accepts the predictions.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c8200000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c8200000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 18:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-0000000000f1', 0),
  ('c8200000-0000-4000-8000-000000000010', 'c8200000-0000-4000-8000-0000000000f2', 1);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8082-000000000001', 'u1@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8082-000000000001', 'u1@t.io', 'U1', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c8200000-0000-4000-8000-0000000000a1', 'c8200000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8082-000000000001', '2099-06-01');

insert into prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at) values
  ('c8200000-0000-4000-8000-00000000b011', 'c8200000-0000-4000-8000-0000000000f1', 'c8200000-0000-4000-8000-0000000000a1', 1, 0, false, now()),
  ('c8200000-0000-4000-8000-00000000b021', 'c8200000-0000-4000-8000-0000000000f2', 'c8200000-0000-4000-8000-0000000000a1', 0, 0, false, now());
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c8200000-0000-4000-8000-0000000000f1', 1, 0, '2099-06-01 20:10Z'),
  ('c8200000-0000-4000-8000-0000000000f2', 1, 1, '2099-06-01 20:05Z');
-- Both fixtures are fully scored.
insert into scoring.fixture_scores (fixture_id, participant_id, ruleset_version, grade, points) values
  ('c8200000-0000-4000-8000-0000000000f1', 'c8200000-0000-4000-8000-0000000000a1', 1, 'exact_scoreline', 3),
  ('c8200000-0000-4000-8000-0000000000f2', 'c8200000-0000-4000-8000-0000000000a1', 1, 'correct_outcome', 0);

do $$
begin
  perform pg_temp.check(
    pg_temp.found() = 'c8200000-0000-4000-8000-0000000000f1,c8200000-0000-4000-8000-0000000000f2',
    'scored fixtures with no ledger entry at all are found');

  insert into ledger.fixture_point_entries
    (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at) values
    (gen_random_uuid(), 'c8200000-0000-4000-8000-0000000000a1', 'c8200000-0000-4000-8000-0000000000f2',
     'fixture_score', 0, 'fixture_score:f2:a1', '2099-06-01 20:06Z');
  perform pg_temp.check(
    pg_temp.found() = 'c8200000-0000-4000-8000-0000000000f1',
    'a zero score posted as zero is finished');

  insert into ledger.fixture_point_entries
    (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at) values
    (gen_random_uuid(), 'c8200000-0000-4000-8000-0000000000a1', 'c8200000-0000-4000-8000-0000000000f1',
     'streak_bonus', 3, 'streak:3', '2099-06-01 20:11Z');
  perform pg_temp.check(
    pg_temp.found() = 'c8200000-0000-4000-8000-0000000000f1',
    'a streak bonus on the fixture is not its score');

  insert into ledger.fixture_point_entries
    (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at) values
    (gen_random_uuid(), 'c8200000-0000-4000-8000-0000000000a1', 'c8200000-0000-4000-8000-0000000000f1',
     'fixture_score', 3, 'fixture_score:f1:a1', '2099-06-01 20:12Z');
  perform pg_temp.check(pg_temp.found() = '', 'once the ledger matches, nothing is found');

  -- A corrected result rescored 3 -> 0: the ledger is behind until a
  -- correction of -3 is posted.
  update scoring.fixture_scores set points = 0, grade = 'incorrect'
   where fixture_id = 'c8200000-0000-4000-8000-0000000000f1';
  perform pg_temp.check(
    pg_temp.found() = 'c8200000-0000-4000-8000-0000000000f1',
    'a rescored fixture the ledger has not caught up with is found');

  insert into ledger.fixture_point_entries
    (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at) values
    (gen_random_uuid(), 'c8200000-0000-4000-8000-0000000000a1', 'c8200000-0000-4000-8000-0000000000f1',
     'correction', -3, 'fixture_score_correction:f1:a1:1', '2099-06-01 21:00Z');
  perform pg_temp.check(pg_temp.found() = '', 'the correction finishes it');
end $$;

rollback;
