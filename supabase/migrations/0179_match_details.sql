-- ============================================================================
-- Migration 0179: the story of each finished match (script 118)
--
-- ADDITIVE ONLY. One new table. No row of any existing table is changed or
-- removed.
--
-- Why: the owner wants a match details page like Sports Mole's: the goals
-- with their minutes, the cards, the half-time score, the ground
-- (2026-10-19). Highlightly's free plan has all of it per match, and the
-- probe of 2026-10-19 (script 117) read Paris FC 4-3 Rennes FC with its 26
-- events, the VAR goal ruled out at 51' among them.
--
-- * football_data.match_details: one row per fixture, read once after its
--   result is recorded (SyncMatchDetails). found = false keeps a fixture the
--   provider has no match for from being asked about again.
-- * events is the list the details page shows, already mapped to the app's
--   kinds: [{"minute":"45+4","kind":"goal","home":true,"player":"...",
--   "assist":"...","detail":"Goal"}, ...].
-- * Display only: nothing reads it to score or rank.
-- * A fixture removed takes its row with it (on delete cascade).
-- * Backend-only: RLS on, nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that reads it. Safe to re-run.
-- ============================================================================

begin;

create table if not exists football_data.match_details (
  fixture_id        uuid primary key
                    references competition.fixture_schedules (fixture_id)
                    on delete cascade,
  source            text not null,
  external_match_id text,
  found             boolean not null,
  half_time_home    integer,
  half_time_away    integer,
  venue             text,
  round             text,
  referee           text,
  events            jsonb not null default '[]'::jsonb,
  fetched_at        timestamptz not null default now(),
  constraint match_details_events_array
    check (jsonb_typeof(events) = 'array'),
  constraint match_details_half_time_pair
    check ((half_time_home is null) = (half_time_away is null)),
  constraint match_details_half_time_range
    check (half_time_home is null
           or (half_time_home between 0 and 99
               and half_time_away between 0 and 99))
);

comment on table football_data.match_details is
  'The story of a finished match for its details page (0179): events with '
  'their minutes, half-time score, ground, read once from the provider. '
  'Display only.';

alter table football_data.match_details enable row level security;
revoke all on football_data.match_details from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0179_match_details')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0179_match_details';                        -- 1 row
-- select count(*) from football_data.match_details;             -- 0
