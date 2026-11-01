-- ============================================================================
-- Migration 0193: what the daily selection chose, and why (script 190)
--
-- ADDITIVE ONLY. Two new tables. No row of any existing table is changed or
-- removed.
--
-- Why: the owner decided on 2026-11-01 that the matches of the seven
-- leagues besides the Premier League and the Champions League are chosen
-- each day by their strength, with a trial week first (nothing added, the
-- choice only kept), so the choices can be read back and the weights tuned.
--
-- * football_data.daily_selection_days: one row per Riyadh day: the count
--   before the selection, the target (15, or 20 on a busy day), how many it
--   chose, the count after, and a note (an alert sent or due).
-- * football_data.daily_selection_candidates: one row per match it looked
--   at: league, clubs, kickoff, score, how the score was made, decision.
-- * Each run of a day replaces that day's rows (a log, not user data).
-- * Read by nothing that scores or ranks players.
-- * Backend-only: RLS on, nothing granted to anon or authenticated.
--
-- Apply BEFORE deploying the server that writes it. Safe to re-run.
-- ============================================================================

begin;

create table if not exists football_data.daily_selection_days (
  riyadh_day  date        primary key,
  mode        text        not null,
  base_count  integer     not null,
  target      integer     not null,
  busy        boolean     not null,
  chosen      integer     not null,
  final_count integer     not null,
  note        text        not null default '',
  updated_at  timestamptz not null default now(),
  constraint daily_selection_days_mode check (mode in ('shadow', 'on'))
);

create table if not exists football_data.daily_selection_candidates (
  riyadh_day  date        not null
              references football_data.daily_selection_days (riyadh_day)
              on delete cascade,
  source      text        not null,
  external_id text        not null,
  league_name text        not null,
  home_team   text        not null,
  away_team   text        not null,
  kickoff_at  timestamptz not null,
  score       integer,
  reasons     text        not null default '',
  decision    text        not null,
  primary key (riyadh_day, source, external_id)
);

comment on table football_data.daily_selection_days is
  'The daily selection of each Riyadh day (0193): counts before and after, '
  'target, busy day, alert note. Replaced by every run of the day.';
comment on table football_data.daily_selection_candidates is
  'Every match the daily selection looked at (0193), with its score, how it '
  'was made and the decision. Replaced by every run of the day.';

alter table football_data.daily_selection_days enable row level security;
alter table football_data.daily_selection_candidates
  enable row level security;
revoke all on football_data.daily_selection_days from anon, authenticated;
revoke all on football_data.daily_selection_candidates
  from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0193_daily_selection_log')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0193_daily_selection_log';                  -- 1 row
-- select count(*) from football_data.daily_selection_days;      -- 0
