-- ============================================================================
-- Migration 0072: streak bonuses count in the weekly league only
--
-- MODIFY-ONLY. One view is redefined; no table, row, column or ledger entry
-- is touched, and nothing is deleted. Every `streak_bonus` entry already in
-- `ledger.fixture_point_entries` stays exactly where it is (0005/0020:
-- append-only).
--
-- ## Why (decided 2026-09-27)
-- Gamification rewards belong to the weekly league, never to the monthly
-- board that carries the prize. 0058 folded `streak_bonus` into
-- `leaderboard.season_fixture_standings`; this migration takes it out again,
-- so the view returns scored fixture points only -- the same sum the Dart
-- `PostgresFixtureTotalsReader` and `PostgresSportingSeasonStandingsReader`
-- read after batch 57. The weekly league keeps counting the bonus through
-- `PostgresWeeklyLeagueStandingsReader`, which reads the ledger directly and
-- does not use this view.
--
-- ## Who reads this view
-- * `leaderboard.capture_season_rank_snapshots()` (0034): the daily rank
--   snapshot behind the movement arrows. The first snapshot after this
--   migration may show a one-day move for a player whose bonus left the
--   total; the next day is stable.
-- * `PostgresLeaderboardRepository` (the personal season record).
--
-- The column list, names, types and order are unchanged, so
-- `create or replace view` is enough and every reader keeps working.
-- ============================================================================

begin;

create or replace view leaderboard.season_fixture_standings as
  select
    p.season_id,
    fs.participant_id,
    sum(fs.points)::bigint as total_points,
    count(*)::bigint as fixtures_scored,
    count(*) filter (
      where fs.grade = 'exact_scoreline'
    )::bigint as exact_count,
    count(*) filter (
      where fs.grade in ('exact_scoreline', 'correct_outcome', 'incorrect')
    )::bigint as decided_count
  from scoring.fixture_scores fs
  join competition.participants p
    on p.id = fs.participant_id
  group by p.season_id, fs.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL: already-scored fixture points '
  'only. Streak bonuses are NOT included (0072): they count in the weekly '
  'league alone. No points are computed or stored here. decided_count '
  'excludes missed and pending grades.';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_fixture_standings '
      'set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_fixture_standings from anon;
grant select on leaderboard.season_fixture_standings to authenticated;

commit;

-- Verification:
-- A participant with one scored fixture (3 points) and one streak_bonus
-- entry (2 points) reads total_points = 3 here, and 5 in the weekly league.
