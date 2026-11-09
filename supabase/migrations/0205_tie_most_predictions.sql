-- ============================================================================
-- Migration 0205: a tie on the boards is broken by the most predictions,
-- then by the oldest account (script 244, 2026-11-10)
--
-- MODIFY-ONLY. One function is redefined (same signature, same schedule)
-- and the ranks of each season's latest daily snapshot are re-ordered among
-- players who were level on its points. No point, score, prediction, user
-- or ledger row is written, changed or removed.
--
-- The order (decided by the owner, 2026-11-10), the same as the Dart
-- FixtureLeaderboard and the terms of the contest:
-- 1. points, most first;
-- 2. exact scorelines, most first;
-- 3. right outcomes with the wrong score, most first;
-- 4. predictions made and settled (`decided_count`), most first;
-- 5. the older account (`identity.users.created_at`), the earlier first.
-- Until now step 4 did not exist and step 5 was the earlier join of the
-- month's contest (`participants.joined_at`).
--
-- The daily snapshot behind the movement arrows must rank exactly as the
-- board does, or the arrows would show moves that never happened. So the
-- latest snapshot of every season is re-ordered once here among players who
-- were level on its points (as 0108 and 0185 did).
--
-- Safe to re-run.
-- ============================================================================

begin;

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
               s.decided_count desc,
               u.created_at asc
    ),
    s.total_points
  from leaderboard.season_fixture_standings s
  join competition.seasons cs
    on cs.id = s.season_id
   and cs.start_at <  ((p_captured_on + 1)::timestamp at time zone 'utc')
   and cs.end_at   >  (p_captured_on::timestamp at time zone 'utc')
  join competition.participants p
    on p.id = s.participant_id
  join identity.users u
    on u.id = p.user_id
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
  'scorelines, then right outcomes, then the most predictions made, then '
  'the oldest account (0205; 0185 had the earlier join of the month last). '
  'Idempotent per day. Returns the row count written.';

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
               coalesce(s.decided_count, 0) desc,
               u.created_at asc
    ) as new_rank
  from leaderboard.season_rank_snapshots t
  join latest l
    on l.season_id = t.season_id
   and l.captured_on = t.captured_on
  join competition.participants p
    on p.id = t.participant_id
  join identity.users u
    on u.id = p.user_id
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

insert into ops.applied_migrations (version)
values ('0205_tie_most_predictions')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0205_tie_most_predictions';                           -- 1 row
-- select position('decided_count' in pg_get_functiondef(
--   'leaderboard.capture_season_rank_snapshots(date)'::regprocedure));    -- > 0
