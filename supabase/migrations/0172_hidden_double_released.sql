-- ============================================================================
-- Migration 0172: a hidden fixture's double is free again (script 89)
--
-- ADDITIVE ONLY. One function replaced (same name, same trigger), one value
-- added to an enum. No row is written, changed or removed.
--
-- Why: an admin hides a fixture that was postponed or called off (0098). A
-- hidden fixture is never scored, yet its double still counted towards the
-- one double a Riyadh day allows (0079, Riyadh day since 0083), and a
-- hidden fixture takes no prediction write, so the double could not be
-- taken off it either: whoever had doubled that match lost the day's double
-- for nothing. Decided 2026-10-16 by the owner.
--
-- * prediction.reject_second_daily_double() no longer counts a double on a
--   hidden fixture, so the player may double another match of that day
--   that has not kicked off. PostgresFixturePredictionRepository's
--   countDoublesOnDay leaves hidden fixtures out the same way, so the two
--   checks never disagree.
-- * notification.notification_kind gains 'double_released': the inbox row
--   that tells those players (NotifyDoubleReleased). Its subject is the
--   hidden fixture, in the fixture_id column notifications already has
--   (0041).
--
-- Showing the fixture again brings its double back as it was. A player who
-- doubled another match of that day in between then has two that day, as
-- a kickoff moved to another day can already leave; the admin decides.
--
-- Apply BEFORE deploying the server that writes 'double_released'.
-- Safe to re-run.
-- ============================================================================

begin;

alter type notification.notification_kind
  add value if not exists 'double_released';

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

  -- A hidden fixture is never scored: its double does not count (0172).
  select count(*) into v_others
    from prediction.fixture_predictions fp
    join competition.fixture_schedules fs on fs.fixture_id = fp.fixture_id
   where fp.participant_id = new.participant_id
     and fp.is_double
     and fp.fixture_id <> new.fixture_id
     and fs.hidden_at is null
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
  'Riyadh kickoff day (0079, Riyadh day since 0083); a double on a hidden '
  'fixture does not count (0172). Serialised per (participant, day) by an '
  'advisory lock, so two concurrent submissions cannot both pass.';

insert into ops.applied_migrations (version)
values ('0172_hidden_double_released')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0172_hidden_double_released';                  -- 1 row
-- select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
--  where t.typname = 'notification_kind' and e.enumlabel = 'double_released';
