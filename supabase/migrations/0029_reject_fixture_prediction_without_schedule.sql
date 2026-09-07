-- Migration 0029 — a fixture with no schedule row is NOT predictable.
--
-- Migration 0019 installed prediction.reject_fixture_write_after_kickoff()
-- with the guard `if fixture_kickoff is not null and now() >= fixture_kickoff`.
-- The `is not null` half meant that a fixture with no row in
-- competition.fixture_schedules was never rejected: it stayed writable
-- forever, including after it had been played and its result was public. The
-- absence of a kickoff time is not evidence that kickoff has not happened.
--
-- This replaces the function so a missing schedule raises instead. The
-- application enforces the same rule (SubmitFixturePrediction, error code
-- prediction.fixture_not_scheduled); this is the database-side backstop for
-- any writer that bypasses the use-case.
--
-- Forward-only. `create or replace function` rebinds the existing trigger
-- automatically -- the trigger from 0019 stays as it is and simply calls the
-- new body.

create or replace function prediction.reject_fixture_write_after_kickoff()
returns trigger
language plpgsql
as $$
declare
  fixture_kickoff timestamptz;
begin
  select kickoff_at into fixture_kickoff
  from competition.fixture_schedules
  where fixture_id = new.fixture_id;

  if fixture_kickoff is null then
    raise exception
      'fixture predictions require a registered kickoff (fixture % has no '
      'schedule row)',
      new.fixture_id
      using errcode = 'check_violation';
  end if;

  if now() >= fixture_kickoff then
    raise exception
      'fixture predictions can only be written before kickoff (fixture % '
      'kicked off at %)',
      new.fixture_id, fixture_kickoff
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function prediction.reject_fixture_write_after_kickoff() is
  'Rejects a fixture prediction write when the fixture has no registered '
  'kickoff, or when its kickoff has passed (server clock, UTC). Migration '
  '0029 tightened the first case: 0019 treated a missing schedule as '
  'unlocked.';
