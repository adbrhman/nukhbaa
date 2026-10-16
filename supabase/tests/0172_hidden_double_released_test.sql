-- End-to-end test for migration 0172: a double on a hidden fixture no longer
-- counts towards the one double a Riyadh day allows, in the trigger and in
-- PostgresFixturePredictionRepository._countDoublesSql (parameters inlined
-- as function arguments; keep the body identical to the adapter's
-- constant). Script 89. Rolled back at the end.
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

create function pg_temp.double(id uuid, fixture uuid) returns text
language sql as $$
  select pg_temp.refusal(format(
    'insert into prediction.fixture_predictions
       (id, fixture_id, participant_id, home_goals, away_goals, is_double, submitted_at)
     values (%L, %L, %L, 1, 0, true, now())',
    id, fixture, 'c1720000-0000-4000-8000-0000000000a1'))
$$;

-- PostgresFixturePredictionRepository._countDoublesSql
create function pg_temp.count_doubles(
  p_participant_id uuid, p_day_start timestamptz, p_day_end timestamptz,
  p_excluding_fixture_id uuid)
returns bigint
language sql as $q$
SELECT count(*) AS n
FROM prediction.fixture_predictions fp
JOIN competition.fixture_schedules fs ON fs.fixture_id = fp.fixture_id
WHERE fp.participant_id = p_participant_id
  AND fp.is_double = true
  AND fs.hidden_at IS NULL
  AND fs.kickoff_at >= p_day_start AND fs.kickoff_at < p_day_end
  AND (p_excluding_fixture_id::uuid IS NULL
       OR fp.fixture_id <> p_excluding_fixture_id)
$q$;

-- 1 June 2099 in Riyadh runs from 21:00Z on 31 May.
create function pg_temp.doubles_on_1_june() returns bigint
language sql as $$
  select pg_temp.count_doubles(
    'c1720000-0000-4000-8000-0000000000a1',
    '2099-05-31 21:00Z', '2099-06-01 21:00Z', null)
$$;

insert into competition.competitions (id, name, format, visibility) values
  ('c1720000-0000-4000-8000-000000000001', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c1720000-0000-4000-8000-000000000010', 'c1720000-0000-4000-8000-000000000001',
   '06/2099', '2099-05-31 21:00Z', '2099-06-30 21:00Z');
-- Far in the future, so the kickoff trigger never refuses these writes.
-- f1 21:00, f2 22:00 and f3 23:00 Riyadh, all on 1 June.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c1720000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c1720000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 19:00Z'),
  ('c1720000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-01 20:00Z');
insert into competition.season_fixtures (season_id, fixture_id, display_order) values
  ('c1720000-0000-4000-8000-000000000010', 'c1720000-0000-4000-8000-0000000000f1', 0),
  ('c1720000-0000-4000-8000-000000000010', 'c1720000-0000-4000-8000-0000000000f2', 1),
  ('c1720000-0000-4000-8000-000000000010', 'c1720000-0000-4000-8000-0000000000f3', 2);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8172-000000000001', 'r172@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8172-000000000001', 'r172@t.io', 'R172', '2099-05-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('c1720000-0000-4000-8000-0000000000a1', 'c1720000-0000-4000-8000-000000000010',
   '00000000-0000-4000-8172-000000000001', '2099-06-01');

do $$
begin
  perform pg_temp.check(
    pg_temp.double('c1720000-0000-4000-8000-00000000b001', 'c1720000-0000-4000-8000-0000000000f1') = 'none',
    'the day''s double on f1 is accepted');

  perform pg_temp.check(
    pg_temp.double('c1720000-0000-4000-8000-00000000b002', 'c1720000-0000-4000-8000-0000000000f2')
      = '23514/fixture_predictions_one_double_per_day',
    'a second double that day is refused while f1 is shown');
  perform pg_temp.check(pg_temp.doubles_on_1_june() = 1,
    'the adapter counts f1''s double while f1 is shown');

  -- The admin hides f1: postponed.
  update competition.fixture_schedules
     set hidden_at = now()
   where fixture_id = 'c1720000-0000-4000-8000-0000000000f1';

  perform pg_temp.check(pg_temp.doubles_on_1_june() = 0,
    'the adapter no longer counts the double on hidden f1');
  perform pg_temp.check(
    pg_temp.double('c1720000-0000-4000-8000-00000000b002', 'c1720000-0000-4000-8000-0000000000f2') = 'none',
    'with f1 hidden, the double moves to f2');
  perform pg_temp.check(
    pg_temp.double('c1720000-0000-4000-8000-00000000b003', 'c1720000-0000-4000-8000-0000000000f3')
      = '23514/fixture_predictions_one_double_per_day',
    'still one double a day among the shown matches');
  perform pg_temp.check(pg_temp.doubles_on_1_june() = 1,
    'the adapter counts the one double on f2');

  -- Showing f1 again brings its double back as it was.
  update competition.fixture_schedules
     set hidden_at = null
   where fixture_id = 'c1720000-0000-4000-8000-0000000000f1';
  perform pg_temp.check(pg_temp.doubles_on_1_june() = 2,
    'f1 shown again: its double counts again, beside f2''s');

  perform pg_temp.check(
    exists (
      select 1
        from pg_enum e
        join pg_type t on t.oid = e.enumtypid
        join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'notification'
         and t.typname = 'notification_kind'
         and e.enumlabel = 'double_released'),
    'notification_kind has double_released');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0172_hidden_double_released'),
    '0172 is recorded');
end $$;

rollback;
