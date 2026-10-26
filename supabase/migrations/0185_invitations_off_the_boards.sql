-- ============================================================================
-- Migration 0185: the invitations and the duels are removed; the boards no
-- longer read invitation points (script 153, 2026-10-26)
--
-- MODIFY-ONLY. One function is redefined (same signature, same schedule),
-- the ranks of each season's latest daily snapshot are re-ordered among
-- players who were level on its points, and the `referrals` switch is
-- turned off. No point, score, prediction, user, invitation, duel or
-- ledger row is written, changed or removed: the invitations and the duels
-- stay stored as they are, read by nothing.
--
-- Why: the owner removed the invitations and the duels from every layer
-- (2026-10-26). The month board, the season board, the personal record and
-- the crown now break a points tie by exact scorelines, then right
-- outcomes, then the earlier join -- the month's invitation points are no
-- longer a step. The daily snapshot behind the movement arrows must rank
-- exactly as the board does, or the arrows would show moves that never
-- happened, so it drops the step too, and the latest snapshot of every
-- season is re-ordered once here (as 0108 did).
--
-- Safe to apply BEFORE the server that stops reading the invitations: the
-- running server's reads of `gamification.referral_month_points` and the
-- duel tables still work, and with the switch off it pays, holds and
-- revokes no invitation and accepts no claim. Migration 0186 drops the
-- invitation and duel functions once that server is gone.
--
-- Safe to re-run.
-- ============================================================================

begin;

-- 0108's function without the invitation step.
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
               s.exact_count desc,
               s.outcome_count desc,
               p.joined_at asc
    ),
    s.total_points
  from leaderboard.season_fixture_standings s
  join competition.seasons cs
    on cs.id = s.season_id
   and cs.start_at <  ((p_captured_on + 1)::timestamp at time zone 'utc')
   and cs.end_at   >  (p_captured_on::timestamp at time zone 'utc')
  join competition.participants p
    on p.id = s.participant_id
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
  'leaderboard.season_rank_snapshots, ranked by points, then exact '
  'scorelines, then right outcomes, then the earlier join (0108; the '
  'month''s invitation points left the order in 0185). Idempotent per day. '
  'Returns the row count written.';

-- The latest snapshot of each season, re-ordered among players who were
-- level on its points. Its points stay as captured: only the order inside
-- a tie changes, by today's tie-break numbers, so a real move stays a move.
with latest as (
  select season_id, max(captured_on) as captured_on
  from leaderboard.season_rank_snapshots
  group by season_id
),
reranked as (
  select
    t.season_id,
    t.participant_id,
    t.captured_on,
    rank() over (
      partition by t.season_id
      order by t.total_points desc,
               coalesce(s.exact_count, 0) desc,
               coalesce(s.outcome_count, 0) desc,
               p.joined_at asc
    ) as new_rank
  from leaderboard.season_rank_snapshots t
  join latest l
    on l.season_id = t.season_id
   and l.captured_on = t.captured_on
  join competition.participants p
    on p.id = t.participant_id
  left join leaderboard.season_fixture_standings s
    on s.season_id = t.season_id
   and s.participant_id = t.participant_id
)
update leaderboard.season_rank_snapshots t
   set rank = r.new_rank
  from reranked r
 where t.season_id = r.season_id
   and t.participant_id = r.participant_id
   and t.captured_on = r.captured_on
   and t.rank is distinct from r.new_rank;

-- The invitations are off for good: no claim, payment or revocation from
-- whatever server still runs. Every point already paid stays stored.
update gamification.feature_flags
   set enabled = false
 where flag_key = 'referrals'
   and enabled;

insert into ops.applied_migrations (version)
values ('0185_invitations_off_the_boards')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0185_invitations_off_the_boards';                    -- 1 row
-- select enabled from gamification.feature_flags
--  where flag_key = 'referrals';                                          -- false
-- select position('referral' in pg_get_functiondef(
--   'leaderboard.capture_season_rank_snapshots(date)'::regprocedure));    -- 0
