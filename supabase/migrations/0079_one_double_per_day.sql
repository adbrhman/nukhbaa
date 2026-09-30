-- ============================================================================
-- Migration 0079: at most one double per participant per day, in the database
--
-- ADDITIVE ONLY. One function and one trigger; no row is touched.
--
-- Why: SubmitFixturePrediction counts the participant's doubles on the
-- fixture's UTC kickoff day and only then writes. Two submissions that arrive
-- together (a double tapped on two cards within the same second) both count
-- zero and both write, so the day ends with two doubles and 6 + 6 points.
-- The application check stays as the first line; this trigger is the
-- backstop (Axiom 6), and it closes the race: a transaction-scoped advisory
-- lock per (participant, day) makes the second writer wait for the first to
-- commit, and its count then sees the first double.
--
-- The day is the UTC calendar day of the fixture's kickoff -- the same day
-- PostgresFixturePredictionRepository.countDoublesOnDay uses, so the two
-- checks can never disagree.
--
-- The refusal is a check_violation named fixture_predictions_one_double_per_day;
-- the Dart adapter maps that name to prediction.daily_double_exceeded, the code
-- the application check already returns and the client already handles.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function prediction.reject_second_daily_double()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_kickoff   timestamptz;
  v_day_start timestamptz;
  v_others    integer;
begin
  if not new.is_double then
    return new;
  end if;

  select fs.kickoff_at into v_kickoff
    from competition.fixture_schedules fs
   where fs.fixture_id = new.fixture_id;
  -- No kickoff: prediction.reject_fixture_write_after_kickoff refuses the row.
  if v_kickoff is null then
    return new;
  end if;

  v_day_start := date_trunc('day', v_kickoff, 'UTC');

  perform pg_advisory_xact_lock(
    hashtextextended(
      'fixture_double:' || new.participant_id::text || ':'
        || to_char(v_day_start at time zone 'UTC', 'YYYY-MM-DD'),
      0
    )
  );

  select count(*) into v_others
    from prediction.fixture_predictions fp
    join competition.fixture_schedules fs on fs.fixture_id = fp.fixture_id
   where fp.participant_id = new.participant_id
     and fp.is_double
     and fp.fixture_id <> new.fixture_id
     and fs.kickoff_at >= v_day_start
     and fs.kickoff_at < v_day_start + interval '1 day';

  if v_others > 0 then
    raise exception
      'only one double per participant per day (participant %, day %)',
      new.participant_id, v_day_start
      using errcode = 'check_violation',
            constraint = 'fixture_predictions_one_double_per_day';
  end if;

  return new;
end;
$$;

comment on function prediction.reject_second_daily_double() is
  'Refuses a second is_double prediction for the same participant on the same '
  'UTC kickoff day (0079). Serialised per (participant, day) by an advisory '
  'lock, so two concurrent submissions cannot both pass.';

drop trigger if exists fixture_predictions_one_double_per_day
  on prediction.fixture_predictions;
create trigger fixture_predictions_one_double_per_day
  before insert or update of is_double, fixture_id, participant_id
  on prediction.fixture_predictions
  for each row execute function prediction.reject_second_daily_double();

commit;
