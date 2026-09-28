-- ============================================================================
-- Migration 0076: the monthly contest turns over at midnight Riyadh time
--
-- MODIFY-ONLY. No row is inserted or deleted. Only the start_at/end_at of
-- monthly contests (`MM/YYYY` labels) that have not begun or not ended yet
-- move three hours earlier; a month already running keeps its start, a month
-- already finished is not touched at all.
--
-- Why: a month used to run from 00:00 UTC on the 1st, which is 03:00 in
-- Riyadh. The app's day is the Riyadh day everywhere else (fixture sync,
-- daily challenge, weekly league, reminders), so the new month appeared
-- three hours after midnight. From here on a month runs from 00:00 Riyadh
-- (21:00 UTC the evening before) to 00:00 Riyadh on the 1st of the next
-- month. Riyadh has no daylight saving, so the offset is always three hours.
--
-- The half-open windows [start_at, end_at) of one competition still touch
-- without overlapping (seasons_no_overlap, 0022): every future END moves
-- first, then every future START, so no intermediate row ever overlaps.
--
-- Guard: a fixture already linked to a month whose end moves earlier, with a
-- kickoff inside the three hours that month gives up, would leave the feed.
-- The function refuses rather than strand it.
--
-- Month membership elsewhere reads the label, not the instants
-- (sporting-season standings, referral season points), so no month changes
-- sporting season. Safe to re-run: a moved instant is no longer on a UTC
-- month boundary, so a second run changes nothing.
-- ============================================================================

begin;

create or replace function competition.align_monthly_seasons_to_riyadh(
  p_now timestamptz default now()
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_stranded integer;
  v_ends integer;
  v_starts integer;
begin
  select count(*) into v_stranded
    from competition.seasons s
    join competition.season_fixtures sf on sf.season_id = s.id
    join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
   where s.label ~ '^[0-9]{2}/[0-9]{4}$'
     and s.end_at > p_now
     and s.end_at = date_trunc('month', s.end_at, 'UTC')
     and fs.kickoff_at >= s.end_at - interval '3 hours'
     and fs.kickoff_at < s.end_at;
  if v_stranded > 0 then
    raise exception
      'align_monthly_seasons_to_riyadh: % linked fixture(s) kick off in the last three UTC hours of their month',
      v_stranded;
  end if;

  update competition.seasons s
     set end_at = s.end_at - interval '3 hours'
   where s.label ~ '^[0-9]{2}/[0-9]{4}$'
     and s.end_at > p_now
     and s.end_at = date_trunc('month', s.end_at, 'UTC');
  get diagnostics v_ends = row_count;

  update competition.seasons s
     set start_at = s.start_at - interval '3 hours'
   where s.label ~ '^[0-9]{2}/[0-9]{4}$'
     and s.start_at > p_now
     and s.start_at = date_trunc('month', s.start_at, 'UTC');
  get diagnostics v_starts = row_count;

  return v_ends + v_starts;
end;
$$;

comment on function competition.align_monthly_seasons_to_riyadh(timestamptz) is
  'Moves the not-yet-started starts and not-yet-passed ends of monthly '
  'contests from 00:00 UTC to 00:00 Riyadh (0076). Returns the number of '
  'instants moved; refuses when a linked fixture would leave its month.';

revoke execute on function competition.align_monthly_seasons_to_riyadh(timestamptz)
  from public, anon, authenticated;

select competition.align_monthly_seasons_to_riyadh(now());

commit;
