-- ============================================================================
-- Migration 0192: league tables kept for the daily selection (script 189)
--
-- ADDITIVE ONLY. One new table. No row of any existing table is changed or
-- removed.
--
-- Why: the owner decided on 2026-11-01 that the matches of the seven
-- leagues besides the Premier League and the Champions League are chosen
-- each day by how strong they are, from their clubs' places in the league
-- table (script 190 chooses; this one keeps the tables).
--
-- * football_data.league_standings: one row per club of the last table read
--   for a provider league (source + league_ref: 'football-data' + 'PD',
--   'highlightly' + '262041'). team_external_id is the provider's team id;
--   football_data.external_identity_map turns it into the catalog club.
-- * A table is read at most about once a day and kept, so a failed read
--   still has the last one. A save writes the new rows with their read time,
--   then deletes the rows of the table before it (a cache, not user data);
--   a read takes only the rows of the latest read time.
-- * Read only to choose matches: nothing scores or ranks players from it.
-- * Backend-only: RLS on, nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that reads it. Safe to re-run.
-- ============================================================================

begin;

create table if not exists football_data.league_standings (
  source           text        not null,
  league_ref       text        not null,
  team_external_id text        not null,
  position         integer     not null,
  points           integer,
  played           integer,
  fetched_at       timestamptz not null,
  primary key (source, league_ref, team_external_id),
  constraint league_standings_position_positive check (position > 0),
  constraint league_standings_keys_not_blank
    check (btrim(source) <> '' and btrim(league_ref) <> ''
           and btrim(team_external_id) <> '')
);

comment on table football_data.league_standings is
  'The last league table read for each provider league (0192): one row per '
  'club, with its place, for choosing the strongest matches of a day. '
  'A cache: a new read replaces the rows of the one before.';

alter table football_data.league_standings enable row level security;
revoke all on football_data.league_standings from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0192_league_standings')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0192_league_standings';                     -- 1 row
-- select count(*) from football_data.league_standings;          -- 0
