-- ============================================================================
-- Migration 0107: a hidden fixture's points leave the standings view
--
-- ADDITIVE ONLY. One view redefined with the same columns; no row of any
-- table is written, changed or removed.
--
-- An admin hides a fixture (0098) to pull it out of sight at once -- a wrong
-- team, a duplicate. Its predictions, result, scores and ledger entries stay
-- as they are, and it was already left out of the head-to-head rounds, the
-- streak and the daily challenge; but its points stayed in the monthly,
-- weekly and season boards and the crown, so a board could be decided by a
-- fixture nobody could see any more (audit M-23). Decided 2026-10-13: hiding
-- is a cancellation for as long as it lasts -- the points leave every board,
-- and showing the fixture again brings them back unchanged. Test fixtures
-- (0098) are never scored; they are left out here too, for certainty.
--
-- This view feeds the daily rank snapshot (0034/0074), the season tab, a
-- group's season board and the personal season record. The Dart board
-- readers apply the same filter (batch 125).
--
-- The column list, names, types and order are unchanged, so
-- `create or replace view` is enough. Safe to re-run.
-- ============================================================================

begin;

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
    )::bigint as decided_count
  from scoring.fixture_scores fs
  join competition.participants p
    on p.id = fs.participant_id
  join identity.users u
    on u.id = p.user_id
  where u.status <> 'suspended'
    and not exists (
      select 1
      from competition.fixture_schedules sch
      where sch.fixture_id = fs.fixture_id
        and (sch.hidden_at is not null or sch.is_test)
    )
  group by p.season_id, fs.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL: already-scored fixture points '
  'only. Streak bonuses are NOT included (0072): they count in the weekly '
  'league alone. Suspended accounts are left out (0085), and so are hidden '
  'and test fixtures (0107). No points are computed or stored here. '
  'decided_count excludes missed and pending grades.';

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

insert into ops.applied_migrations (version)
values ('0107_hidden_fixtures_off_boards')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0107_hidden_fixtures_off_boards';                    -- 1 row
-- select pg_get_viewdef('leaderboard.season_fixture_standings'::regclass)
--   like '%hidden_at%';                                                 -- true
