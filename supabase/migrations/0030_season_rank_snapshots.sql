-- ============================================================================
-- Migration 0030: season_rank_snapshots
--
-- Stores one ranked row per season participant per calendar day, so the
-- leaderboard can show movement (up/down/unchanged) against the previous
-- capture. Axiom 5 is untouched: this is a read-side projection of
-- leaderboard.season_standings, which is itself a SUM over the append-only
-- ledger. No points are created, edited or sourced here; deleting every row
-- in this table would lose only the arrows, never a point.
--
-- Ranking mirrors the pure domain rule (SeasonLeaderboard.rank): standard
-- competition ("1224") ranking on total_points descending — equal totals
-- share a rank and the next distinct total skips by the size of the tied
-- group. SQL rank() over (order by total_points desc) is exactly that. The
-- domain's joinedAt / participant_id tie-breaks affect display order only,
-- not the rank number, so they are not needed here.
--
-- The daily capture is scheduled with pg_cron. That extension exists on the
-- hosted Supabase project but NOT on a plain Postgres container, so both the
-- CREATE EXTENSION and the cron.schedule call are guarded: a clean-database
-- rebuild (the CI migration gate) creates the table, the function and the
-- view and simply skips the schedule. Same reasoning as migration 0026's
-- storage.objects guard.
--
-- Forward-only, expand-only. Every statement is guarded — safe to re-run.
-- ============================================================================

create table if not exists leaderboard.season_rank_snapshots (
  season_id      uuid        not null,
  participant_id uuid        not null,
  captured_on    date        not null,
  rank           integer     not null,
  total_points   bigint      not null,
  captured_at    timestamptz not null default now(),
  primary key (season_id, participant_id, captured_on)
);

comment on table leaderboard.season_rank_snapshots is
  'Daily rank/points capture per season participant (read-side only, Axiom '
  '5). Written by leaderboard.capture_season_rank_snapshots(), scheduled '
  'via pg_cron. Consumed by leaderboard.season_standings_with_movement to '
  'derive the movement arrows. Never a source of points.';

create index if not exists season_rank_snapshots_season_day_idx
  on leaderboard.season_rank_snapshots (season_id, captured_on desc);

revoke all on leaderboard.season_rank_snapshots from anon;
grant select on leaderboard.season_rank_snapshots to authenticated;

-- ---------------------------------------------------------------------------
-- Capture function. Idempotent for a given day: re-running overwrites that
-- day's rows rather than duplicating them, so a manual re-run after a failed
-- cron tick is safe. Captures every season whose calendar window is open at
-- p_captured_on; a closed season's last snapshot stays frozen.
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
  from leaderboard.season_standings s
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
  'Captures today''s standings for every open season into '
  'leaderboard.season_rank_snapshots. Idempotent per day. Returns the row '
  'count written.';

-- ---------------------------------------------------------------------------
-- Read-side projection: live standings joined to the most recent snapshot.
-- movement = previous_rank - current live rank, so a positive number means
-- the participant climbed. NULL previous_rank (no snapshot yet, or a
-- participant who joined after the last capture) yields a NULL movement,
-- which the client renders as "new" rather than as an arrow.
-- ---------------------------------------------------------------------------
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
    latest.captured_on                   as compared_to
  from live
  left join latest
    on latest.season_id = live.season_id
  left join leaderboard.season_rank_snapshots snap
    on snap.season_id      = live.season_id
   and snap.participant_id = live.participant_id
   and snap.captured_on    = latest.captured_on;

comment on view leaderboard.season_standings_with_movement is
  'season_standings plus the live 1224 rank and its delta against the most '
  'recent daily snapshot. movement > 0 means climbed; NULL means no '
  'comparable snapshot (new participant or first day).';

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

-- ---------------------------------------------------------------------------
-- Daily schedule, 00:05 UTC. The capture therefore records the standings as
-- they closed the previous day, and movement read during the day is measured
-- against that close.
--
-- Guarded twice over: pg_cron is absent from the CI container entirely, and
-- creating extensions requires privileges the local `postgres` role may not
-- hold. Skipping leaves the table, function and view fully usable — only the
-- automatic tick is missing, and the function can still be called by hand.
-- ---------------------------------------------------------------------------
do $$
begin
  execute 'create extension if not exists pg_cron';

  -- cron.schedule() upserts on jobname, so re-running this migration
  -- rewrites the existing job rather than creating a duplicate.
  perform cron.schedule(
    'nukhbaa_season_rank_snapshot',
    '5 0 * * *',
    'select leaderboard.capture_season_rank_snapshots()'
  );
exception
  when others then
    raise notice
      'pg_cron schedule skipped (%): capture_season_rank_snapshots() must be '
      'invoked manually in this environment', sqlerrm;
end;
$$;
