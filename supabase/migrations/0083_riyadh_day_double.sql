-- ============================================================================
-- Migration 0083: "one double per day" counts the Riyadh day
--
-- ADDITIVE ONLY. One function replaced (same trigger); no row is touched.
--
-- Why: 0079 (and SubmitFixturePrediction) counted doubles per UTC day, while
-- the app shows match days in Riyadh time and the daily challenge, streaks
-- and reminders all use the Riyadh day. A match between 00:00 and 03:00
-- Riyadh was counted with the previous day: two doubles could be placed on
-- one day as the player sees it, and a double could be refused across two
-- days. The day is now the Riyadh calendar day of the fixture's kickoff
-- (Asia/Riyadh, UTC+3, no daylight saving) -- the same day
-- PostgresFixturePredictionRepository.countDoublesOnDay now uses, so the two
-- checks never disagree.
--
-- Decided 2026-10-02 by the owner. Doubles already stored are untouched;
-- the rule applies to every write from now on.
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

  -- Midnight in Riyadh at the start of the kickoff's Riyadh day.
  v_day_start := date_trunc('day', v_kickoff, 'Asia/Riyadh');

  perform pg_advisory_xact_lock(
    hashtextextended(
      'fixture_double:' || new.participant_id::text || ':'
        || to_char(v_day_start at time zone 'Asia/Riyadh', 'YYYY-MM-DD'),
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
     and fs.kickoff_at < v_day_start + interval '24 hours';

  if v_others > 0 then
    raise exception
      'only one double per participant per day (participant %, day %)',
      new.participant_id, to_char(v_day_start at time zone 'Asia/Riyadh', 'YYYY-MM-DD')
      using errcode = 'check_violation',
            constraint = 'fixture_predictions_one_double_per_day';
  end if;

  return new;
end;
$$;

comment on function prediction.reject_second_daily_double() is
  'Refuses a second is_double prediction for the same participant on the same '
  'Riyadh kickoff day (0079, Riyadh day since 0083). Serialised per '
  '(participant, day) by an advisory lock, so two concurrent submissions '
  'cannot both pass.';

insert into ops.applied_migrations (version)
values ('0083_riyadh_day_double')
on conflict (version) do nothing;

commit;
