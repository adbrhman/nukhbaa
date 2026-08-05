-- ============================================================================
-- Migration 0012: fixture_schedule
-- Minimal admin-fed fixture IDENTITY (home team / away team / kickoff instant),
-- mirroring scoring.fixture_results (Next-Task decision 2026-07-11, option a).
-- ============================================================================

create table if not exists competition.fixture_schedules (
  fixture_id  uuid primary key,
  home_team   text not null,
  away_team   text not null,
  kickoff_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint fixture_schedules_home_len
    check (char_length(btrim(home_team)) between 1 and 120),
  constraint fixture_schedules_away_len
    check (char_length(btrim(away_team)) between 1 and 120),
  constraint fixture_schedules_teams_distinct
    check (btrim(lower(home_team)) <> btrim(lower(away_team)))
);

comment on table competition.fixture_schedules is
  'Minimal admin-fed fixture identity (home/away team names + kickoff instant), '
  'mirroring scoring.fixture_results (Next-Task option (a)). One row per opaque '
  'fixture id; no competition/round reference (Axiom 3). Ingested by an admin '
  'command only (Axioms 2/5).';

drop trigger if exists fixture_schedules_set_updated_at
  on competition.fixture_schedules;
create trigger fixture_schedules_set_updated_at
  before update on competition.fixture_schedules
  for each row execute function identity.set_updated_at();

alter table competition.fixture_schedules enable row level security;

revoke insert, update, delete, truncate
  on competition.fixture_schedules
  from anon, authenticated;

drop policy if exists fixture_schedules_select_authenticated
  on competition.fixture_schedules;
create policy fixture_schedules_select_authenticated
  on competition.fixture_schedules for select
  to authenticated using (true);

drop policy if exists fixture_schedules_anon_no_access
  on competition.fixture_schedules;
create policy fixture_schedules_anon_no_access
  on competition.fixture_schedules for select to anon using (false);
