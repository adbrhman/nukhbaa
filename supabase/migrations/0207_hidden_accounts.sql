-- ============================================================================
-- Migration 0207: accounts the owner admin hides from every board
--
-- ADDITIVE ONLY. One nullable column and one view redefined with the same
-- columns; no row of any table is written, changed or removed.
--
-- Decided by the owner on 2026-11-11 (script 258): the owner admin alone
-- (adbrhmanm@gmail.com) may hide an account -- first the account Google
-- Play's reviewers sign in with. A hidden account signs in, predicts and
-- receives its notifications like any player, but it is counted nowhere the
-- players look: no board (month, season, live, friends' leagues), no
-- head-to-head draw, sheet or Elite Cup, no crowning, and its exact call does
-- not take the sole-exact bonus from anyone. Showing it again brings back
-- the same points: nothing is deleted. The server reads the same filter
-- wherever it already leaves a suspended account out (0085).
--
-- 1. identity.users.hidden_at: when the owner hid the account; null = shown.
-- 2. leaderboard.season_fixture_standings: the 0108 definition, plus
--    `and u.hidden_at is null`. Same columns, names, types and order, so
--    `create or replace view` is enough.
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table identity.users
  add column if not exists hidden_at timestamptz;

comment on column identity.users.hidden_at is
  'When the owner admin hid this account from every board (script 258); null = shown. Never set for the owner himself.';

create index if not exists users_hidden_at_idx
  on identity.users (hidden_at)
  where hidden_at is not null;

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
    )::bigint as decided_count,
    count(*) filter (
      where fs.grade = 'correct_outcome'
    )::bigint as outcome_count
  from scoring.fixture_scores fs
  join competition.participants p
    on p.id = fs.participant_id
  join identity.users u
    on u.id = p.user_id
  where u.status <> 'suspended'
    and u.hidden_at is null
    and not exists (
      select 1
      from competition.fixture_schedules sch
      where sch.fixture_id = fs.fixture_id
        and (sch.hidden_at is not null or sch.is_test)
    )
  group by p.season_id, fs.participant_id;

insert into ops.applied_migrations (version)
values ('0207_hidden_accounts')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0207_hidden_accounts';                     -- one row
-- select count(*) from identity.users where hidden_at is not null;  -- 0
