-- ============================================================================
-- Migration 0195: a match moved to another day loses its doubles (script 197)
--
-- ADDITIVE ONLY. Two functions and two triggers. No prediction is removed:
-- only the is_double flag of the moved match's predictions is cleared, and
-- each prediction stays as it was otherwise (scoreline, stamp, id).
--
-- Why (review L-7): "one double a day" was checked only when a prediction
-- was written. A match put back (or brought forward) to another Riyadh day
-- carried its doubles with it, so a player could end with two doubles on
-- one day. Decided by the owner on 2026-11-02: the double of a match moved
-- to another day is cancelled for every player who chose it; he may double
-- another match of that day that has not kicked off, and his prediction of
-- the moved match stays an ordinary prediction.
--
-- 1. competition.fixture_schedules: when kickoff_at moves to another Riyadh
--    day, before the new kickoff, with no recorded result and the fixture
--    shown, every double on it is cleared, and the cache epoch (0194) moves
--    so the server drops its held reads within a minute.
-- 2. prediction.fixture_predictions: a prediction moved by a merge onto a
--    copy of the match put back to another day (0182: 12 hours later or
--    more) arrives without its double. A merge of two copies of one kickoff
--    (0176, under 12 hours) is not a postponement and is unchanged.
--
-- Needs 0194 (ops.bump_cache_epoch). Safe to re-run.
-- ============================================================================

begin;

create or replace function prediction.release_moved_double()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_released integer;
begin
  if new.kickoff_at is not distinct from old.kickoff_at then
    return null;
  end if;
  if (old.kickoff_at at time zone 'Asia/Riyadh')::date
       = (new.kickoff_at at time zone 'Asia/Riyadh')::date then
    return null;
  end if;
  -- Not a postponement to play: hidden, already under way, or decided.
  if new.hidden_at is not null or new.kickoff_at <= now() then
    return null;
  end if;
  if exists (select 1 from scoring.fixture_results r
              where r.fixture_id = new.fixture_id) then
    return null;
  end if;

  update prediction.fixture_predictions fp
     set is_double = false
   where fp.fixture_id = new.fixture_id
     and fp.is_double;
  get diagnostics v_released = row_count;

  if v_released > 0 then
    perform ops.bump_cache_epoch('double released: ' || new.fixture_id::text);
  end if;
  return null;
end
$$;

comment on function prediction.release_moved_double() is
  'Clears the doubles of a fixture whose kickoff moved to another Riyadh '
  'day before it was played (0195, decided 2026-11-02).';

drop trigger if exists fixture_schedules_release_moved_double
  on competition.fixture_schedules;
create trigger fixture_schedules_release_moved_double
  after update of kickoff_at on competition.fixture_schedules
  for each row execute function prediction.release_moved_double();

create or replace function prediction.release_postponed_copy_double()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_from timestamptz;
  v_to   timestamptz;
begin
  if not new.is_double or new.fixture_id = old.fixture_id then
    return new;
  end if;
  select fs.kickoff_at into v_from
    from competition.fixture_schedules fs where fs.fixture_id = old.fixture_id;
  select fs.kickoff_at into v_to
    from competition.fixture_schedules fs where fs.fixture_id = new.fixture_id;
  if v_from is null or v_to is null then
    return new;
  end if;
  if v_to - v_from >= interval '12 hours'
     and (v_from at time zone 'Asia/Riyadh')::date
           <> (v_to at time zone 'Asia/Riyadh')::date then
    new.is_double := false;
  end if;
  return new;
end
$$;

comment on function prediction.release_postponed_copy_double() is
  'A prediction merged onto a copy of the match put back to another day '
  'arrives without its double (0195, decided 2026-11-02).';

-- "a_" sorts it before fixture_predictions_one_double_per_day: the daily
-- double check then sees the double already cleared.
drop trigger if exists fixture_predictions_a_postponed_copy_double
  on prediction.fixture_predictions;
create trigger fixture_predictions_a_postponed_copy_double
  before update of fixture_id on prediction.fixture_predictions
  for each row execute function prediction.release_postponed_copy_double();

insert into ops.applied_migrations (version)
values ('0195_postponed_double')
on conflict (version) do nothing;

commit;
