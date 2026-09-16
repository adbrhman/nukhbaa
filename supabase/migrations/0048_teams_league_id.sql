-- 0048: football_data.teams.league_id, in the repository.
--
-- Production already has this column (the team picker and
-- PostgresTeamRepository read it), but no migration in this repository
-- created it, so a database rebuilt from supabase/migrations lacked it.
-- `add column if not exists` makes this a no-op in production and brings a
-- clean database (CI, a restore into a new project) to the same shape.
--
-- Nullable: national sides belong to no league (0046).

alter table football_data.teams
  add column if not exists league_id uuid
    references football_data.leagues (id) on delete set null;

comment on column football_data.teams.league_id is
  'The league a club is listed under in the team picker; null for national '
  'sides and for clubs outside any listed league.';
