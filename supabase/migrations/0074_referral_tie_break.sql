-- ============================================================================
-- Migration 0074: invitation points break ties on the month's rank arrows
--
-- MODIFY-ONLY. One function is redefined (same signature, same idempotence,
-- same pg_cron schedule from 0030) and one partial index is added. No row,
-- column, table or ledger entry is changed or deleted.
--
-- ## The order (decided 2026-09-27), the same as the Dart FixtureLeaderboard
-- 1. prediction points, most first;
-- 2. then the month's invitation points (`gamification.referral_month_points`,
--    capped at 20), most first -- they never add to the points;
-- 3. then exact scorelines, most first;
-- 4. still level on all three: the same rank (standard "1224" ranking).
--
-- The daily snapshot behind the movement arrows must rank exactly as the
-- board does, or the arrows would show moves that never happened.
-- ============================================================================

begin;

-- The month and season views read only paid and revoked invitations; this
-- keeps them off a scan of every gamification event.
create index if not exists events_referral_paid_idx
  on gamification.events (event_type, ref_id, occurred_at)
  where event_type in ('referral_qualified', 'referral_revoked');

create or replace function leaderboard.capture_season_rank_snapshots(
  p_captured_on date default (now() at time zone 'utc')::date
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_rows integer;
begin
  insert into leaderboard.season_rank_snapshots as t
    (season_id, participant_id, captured_on, rank, total_points)
  select
    s.season_id,
    s.participant_id,
    p_captured_on,
    rank() over (
      partition by s.season_id
      order by s.total_points desc,
               coalesce(rm.referral_points, 0) desc,
               s.exact_count desc
    ),
    s.total_points
  from leaderboard.season_fixture_standings s
  join competition.seasons cs
    on cs.id = s.season_id
   and cs.start_at <  ((p_captured_on + 1)::timestamp at time zone 'utc')
   and cs.end_at   >  (p_captured_on::timestamp at time zone 'utc')
  join competition.participants p
    on p.id = s.participant_id
  left join gamification.referral_month_points rm
    on rm.season_id = s.season_id
   and rm.user_id = p.user_id
  on conflict (season_id, participant_id, captured_on) do update
    set rank         = excluded.rank,
        total_points = excluded.total_points,
        captured_at  = now();

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function leaderboard.capture_season_rank_snapshots(date) is
  'Captures today''s FIXTURE standings for every open season into '
  'leaderboard.season_rank_snapshots, ranked by points, then the month''s '
  'invitation points, then exact scorelines (0074). Idempotent per day. '
  'Returns the row count written.';

commit;
