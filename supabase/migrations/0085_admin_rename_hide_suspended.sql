-- ============================================================================
-- Migration 0085: the rename audit token, and suspended accounts off the
-- live standings view
--
-- ADDITIVE ONLY. One enum value, one view redefined with the same columns;
-- no row of any table is written, changed or removed.
--
-- 1. admin.audit_action gains 'user_renamed' -- AdminRenameUser records the
--    old and new names in the reason.
--
-- 2. leaderboard.season_fixture_standings leaves out participants whose
--    account is suspended. Decided 2026-10-02 by the owner: suspending an
--    account takes it off every board and its points out of the standings,
--    and reinstating it brings both back unchanged -- nothing is deleted.
--    The Dart board readers apply the same filter. The view feeds the daily
--    rank snapshot (0034/0074) and the personal season record, so ranks stay
--    the same numbers the boards show.
--
-- The column list, names, types and order are unchanged, so
-- `create or replace view` is enough. Safe to re-run.
-- ============================================================================

-- ALTER TYPE ... ADD VALUE stays outside the transaction (as in 0044).
alter type admin.audit_action
  add value if not exists 'user_renamed';

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
  group by p.season_id, fs.participant_id;

comment on view leaderboard.season_fixture_standings is
  'The live per-fixture standings, in SQL: already-scored fixture points '
  'only. Streak bonuses are NOT included (0072): they count in the weekly '
  'league alone. Suspended accounts are left out (0085). No points are '
  'computed or stored here. decided_count excludes missed and pending grades.';

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
values ('0085_admin_rename_hide_suspended')
on conflict (version) do nothing;

commit;
