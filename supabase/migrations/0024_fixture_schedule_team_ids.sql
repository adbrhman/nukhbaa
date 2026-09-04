-- ============================================================================
-- Migration 0024: fixture_schedule_team_ids
-- Wires competition.fixture_schedules to the previously-unwired
-- football_data.teams catalog (migration 0013), so a fixture's home/away
-- side can be resolved to a canonical team id (-> display name + crest) in
-- addition to the free-text names it already carries.
--
-- Additive/expand-only: both columns are nullable, so every already-stored
-- schedule row (and any client not yet sending a team id) stays valid. The
-- free-text home_team/away_team columns are untouched (Axiom 3: a fixture's
-- team identity travels as free text on the wire; the id is an enrichment,
-- not a replacement).
-- ============================================================================

alter table competition.fixture_schedules
  add column if not exists home_team_id uuid
    references football_data.teams (id) on delete set null,
  add column if not exists away_team_id uuid
    references football_data.teams (id) on delete set null;

comment on column competition.fixture_schedules.home_team_id is
  'Optional resolved home-team id into football_data.teams (migration 0024). '
  'Null for schedules registered before this migration, or for a client that '
  'has not yet been updated to send it.';

comment on column competition.fixture_schedules.away_team_id is
  'Optional resolved away-team id into football_data.teams (migration 0024). '
  'Same nullability rationale as home_team_id.';

create index if not exists fixture_schedules_home_team_id_idx
  on competition.fixture_schedules (home_team_id);
create index if not exists fixture_schedules_away_team_id_idx
  on competition.fixture_schedules (away_team_id);
