-- Migration 0022 -- Phase 7.7 step 3: prevent overlapping seasons within the
-- same competition.
--
-- Context: Phase 7.7 steps 1-2 introduced a "current season" computed purely
-- from `Clock.nowUtc()` against each season's `[start_at, end_at)` window
-- (`CompetitionSeason.isCurrentAt`, `findCurrentSeason`) -- never stored, the
-- same principle as `FixtureLock`. But nothing before this migration stopped
-- two seasons of the same competition from having overlapping windows: a data
-- entry mistake or a race could silently create two "current" seasons at
-- once. `findCurrentSeason`'s `ORDER BY start_at ASC, id ASC LIMIT 1` would
-- then pick one arbitrarily instead of surfacing the corruption -- this
-- migration closes that gap at the database, the last line of defence
-- (Database ADR §10, Ratified Axiom 6).
--
-- Forward-only, expand-only. Safe to re-run.

create extension if not exists btree_gist;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'seasons_no_overlap'
      and conrelid = 'competition.seasons'::regclass
  ) then
    alter table competition.seasons
      add constraint seasons_no_overlap
      exclude using gist (
        competition_id with =,
        tstzrange(start_at, end_at, '[)') with &&
      );
  end if;
end
$$;

comment on constraint seasons_no_overlap on competition.seasons is
  'No two seasons of the same competition may have overlapping windows '
  '(Phase 7.7 step 3). The range is half-open [start_at, end_at) -- matching '
  'CompetitionSeason.isCurrentAt -- so a season ending exactly when the next '
  'begins is not a conflict. Backstops the application-computed "current '
  'season" (Phase 7.7 steps 1-2, findCurrentSeason).';
