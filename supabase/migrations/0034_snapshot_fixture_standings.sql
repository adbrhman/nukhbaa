-- ============================================================================
-- Migration 0034: the daily snapshot follows the points
--
-- Migration 0030 captured leaderboard.season_standings, which sums
-- ledger.point_entries. That table is not merely empty -- it is unreachable:
-- point_entries.round_id is NOT NULL with an FK to competition.rounds, and
-- competition.round_fixtures holds zero rows, because this project moved to
-- season-linked fixtures in migration 0019 and left rounds behind. Not one of
-- the 359 recorded grades can be posted there without inventing a round to
-- satisfy a column.
--
-- So every snapshot taken so far recorded a board where all 226 participants
-- were tied at zero, and every arrow derived from it would be meaningless.
-- The capture is repointed at scoring.fixture_scores -- the store that fills
-- the instant a result is recorded and backs every number users see.
--
-- Ranking still mirrors the pure domain rule (FixtureLeaderboard.rank):
-- standard competition ("1224") on total_points descending. SQL
-- rank() over (order by total_points desc) is exactly that.
--
-- Axioms 2 and 5 untouched: this reads already-awarded points and stores no
-- new ones. Nothing here writes to scoring or ledger.
--
-- Forward-only. Safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- The SQL twin of the in-memory fixture board.
--
-- Scoped through competition.participants, not season_fixtures: a participant
-- belongs to exactly one season, so this needs no fixture-to-season join and
-- a fixture linked to more than one season cannot double-count a grade.
-- ---------------------------------------------------------------------------
create or replace view leaderboard.season_fixture_standings as
  select
    p.season_id                     as season_id,
    fs.participant_id               as participant_id,
    sum(fs.points)::bigint          as total_points,
    count(*)::bigint                as fixtures_scored,
    count(*) filter (
      where fs.grade = 'exact_scoreline'
    )::bigint                       as exact_count,
    count(*) filter (
      where fs.grade in ('exact_scoreline', 'correct_outcome', 'incorrect')
    )::bigint                       as decided_count
  from scoring.fixture_scores fs
  join competition.participants p
    on p.id = fs.participant_id
  group by p.season_id, fs.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL. The Dart use-case '
  'GetSeasonFixtureLeaderboard computes the same aggregate in memory for the '
  'API; this view exists so the daily snapshot can rank the same board '
  'without going through the server. decided_count excludes missed and '
  'pending grades -- neither is a prediction that turned out wrong.';

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

-- ---------------------------------------------------------------------------
-- Discard the snapshots taken against the unreachable ledger. They record a
-- board on which everyone was tied at zero, so keeping them would produce
-- arrows that mean nothing on the first real comparison.
--
-- Safe to delete: this table is a re-derivable projection, not a point store.
-- Losing every row costs the arrows for one day and not a single point.
-- ---------------------------------------------------------------------------
delete from leaderboard.season_rank_snapshots;

-- ---------------------------------------------------------------------------
-- The capture, repointed. Same signature, same idempotence, same schedule --
-- the pg_cron job from 0030 keeps calling this without change.
-- ---------------------------------------------------------------------------
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
      order by s.total_points desc
    ),
    s.total_points
  from leaderboard.season_fixture_standings s
  join competition.seasons cs
    on cs.id = s.season_id
   and cs.start_at <  ((p_captured_on + 1)::timestamp at time zone 'utc')
   and cs.end_at   >  (p_captured_on::timestamp at time zone 'utc')
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
  'leaderboard.season_rank_snapshots. Idempotent per day. Returns the row '
  'count written.';
