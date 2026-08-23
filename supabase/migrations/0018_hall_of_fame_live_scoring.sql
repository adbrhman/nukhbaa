-- Migration 0018 — Hall of Fame: switch the source from the ledger to the
-- LIVE scoring read model (`scoring.round_scores`), so a user's all-time
-- total updates the instant an admin scores a fixture (احتساب فوري),
-- without waiting for the round to be locked/scored and manually posted to
-- the ledger.
--
-- Decision (2026-08-23, approved): the ledger-only-source rule for the Hall
-- of Fame (migrations 0011/0016) is superseded for THIS board specifically.
-- `scoring.round_scores` already upserts a participant's running total per
-- round on every scoring pass (live/partial grading, migration
-- 0017_scoring_live_grading.sql) — including while a round is still `open`
-- and some fixtures are still `pending`. Summing directly over it, instead
-- of over the ledger (which is only populated once a round reaches `scored`
-- and an admin explicitly posts it), makes the board reflect every finished
-- fixture's points immediately and cumulatively as more results land.
--
-- Column set/order is UNCHANGED from 0016 (user_id, display_name,
-- total_points, seasons_played), so `CREATE OR REPLACE VIEW` is valid here
-- (no drop+recreate needed) and no application code changes.
--
-- The season board (`leaderboard.season_standings`, migration 0006) is NOT
-- touched by this migration — it still reads the ledger, unchanged.
--
-- Forward-only, expand-only (Platform ADR). Safe to re-run.

create or replace view leaderboard.hall_of_fame_standings as
  select
    p.user_id                                as user_id,
    max(u.display_name)                      as display_name,
    coalesce(sum(s.total_points), 0)::bigint as total_points,
    count(distinct p.season_id)::bigint      as seasons_played
  from competition.participants p
  join identity.users u
    on u.id = p.user_id
  left join scoring.round_scores s
    on s.participant_id = p.id
  group by p.user_id;

comment on view leaderboard.hall_of_fame_standings is
  'All-time, cross-season standings projection. One row per user with at '
  'least one participant row; display_name is the platform-owned name from '
  'identity.users. total_points is now the LIVE sum of scoring.round_scores '
  '(not the ledger, migration 0018) — it updates the instant a fixture is '
  'scored, before a round locks or is posted to the ledger. seasons_played '
  'counts distinct seasons the user has a participant row in. Ranks are '
  'assigned by the pure domain HallOfFame.rank, not stored here.';

-- Re-apply the same access controls as 0011/0016 (idempotent; unaffected by
-- CREATE OR REPLACE, but restated here so this migration is self-contained).
do $$
begin
  begin
    execute
      'alter view leaderboard.hall_of_fame_standings set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.hall_of_fame_standings from anon;
grant select on leaderboard.hall_of_fame_standings to authenticated;
