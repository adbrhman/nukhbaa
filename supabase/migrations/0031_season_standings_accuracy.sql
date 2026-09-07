-- ============================================================================
-- Migration 0031: accuracy counts on the season standings projection
--
-- Adds two counts per season participant to
-- leaderboard.season_standings_with_movement (migration 0030):
--
--   exact_count    settled fixtures the participant called EXACTLY right
--   settled_count  fixtures settled for them at all (grade <> 'pending')
--
-- Accuracy is defined as exact_scoreline alone -- the share of a
-- participant's settled predictions that named the precise scoreline.
-- A merely correct outcome is NOT accuracy: it earns points but it did not
-- get the score right, and a figure that counts it would stop tracking the
-- number printed beside it.
--
-- The two counts travel raw; the percentage itself is derived once, in the
-- pure domain, exactly as movement is derived from previous_rank. Sending a
-- pre-divided figure would let the ratio and its inputs drift apart, and a
-- participant with zero settled fixtures has no accuracy at all (0/0), which
-- a raw pair expresses honestly and a percentage cannot.
--
-- Axiom 5 untouched: scoring.fixture_scores is the already-ratified grading
-- record; this only counts rows that exist. Axiom 2 untouched: the client
-- receives counts it never computed.
--
-- Visibility note: the view stays security_invoker, and
-- scoring.fixture_scores carries an own-or-locked RLS policy. The server
-- reads this view over a direct Postgres connection as the table owner, so
-- RLS is bypassed and every participant's counts are complete -- which is
-- what the app gets (ADR-002: the mobile client never queries Supabase
-- directly). A future direct-from-client read of this view would see only
-- its own settled grades and must not be added without revisiting that
-- policy.
--
-- Forward-only, expand-only. The view is dropped and recreated (Postgres
-- forbids adding columns to an existing view via REPLACE) -- same reasoning
-- as migrations 0016 and 0025. Safe to re-run.
-- ============================================================================

drop view if exists leaderboard.season_standings_with_movement;

create view leaderboard.season_standings_with_movement as
  with live as (
    select
      s.season_id,
      s.participant_id,
      s.display_name,
      s.total_points,
      s.entry_count,
      s.joined_at,
      rank() over (
        partition by s.season_id
        order by s.total_points desc
      ) as current_rank
    from leaderboard.season_standings s
  ),
  latest as (
    select season_id, max(captured_on) as captured_on
    from leaderboard.season_rank_snapshots
    group by season_id
  ),
  -- A participant belongs to exactly one season, so joining through
  -- competition.participants is enough to scope the grades -- no round or
  -- fixture join is needed, and none is used, so a fixture linked to several
  -- rounds cannot double-count a grade.
  accuracy as (
    select
      fs.participant_id,
      count(*) filter (
        where fs.grade = 'exact_scoreline'
      )::bigint as exact_count,
      count(*) filter (
        where fs.grade <> 'pending'
      )::bigint as settled_count
    from scoring.fixture_scores fs
    group by fs.participant_id
  )
  select
    live.season_id,
    live.participant_id,
    live.display_name,
    live.total_points,
    live.entry_count,
    live.joined_at,
    live.current_rank,
    snap.rank                            as previous_rank,
    (snap.rank - live.current_rank)      as movement,
    latest.captured_on                   as compared_to,
    coalesce(acc.exact_count, 0)         as exact_count,
    coalesce(acc.settled_count, 0)       as settled_count
  from live
  left join latest
    on latest.season_id = live.season_id
  left join leaderboard.season_rank_snapshots snap
    on snap.season_id      = live.season_id
   and snap.participant_id = live.participant_id
   and snap.captured_on    = latest.captured_on
  left join accuracy acc
    on acc.participant_id = live.participant_id;

comment on view leaderboard.season_standings_with_movement is
  'season_standings plus the live 1224 rank, its delta against the most '
  'recent daily snapshot, and the exact/settled fixture counts behind the '
  'accuracy figure. movement > 0 means climbed; NULL means no comparable '
  'snapshot. settled_count = 0 means no accuracy exists yet.';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_standings_with_movement '
      'set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_standings_with_movement from anon;
grant select on leaderboard.season_standings_with_movement to authenticated;
