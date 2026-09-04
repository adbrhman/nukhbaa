-- Migration 0025 — display_name projected through the season leaderboard
-- VIEW, exactly mirroring migration 0016's identical fix for
-- leaderboard.hall_of_fame_standings (Axiom 5: still no new points source;
-- this only threads the existing identity.users.display_name column
-- through this second read-side projection). Without this, the season
-- leaderboard shows a raw participant_id UUID instead of the participant's
-- name.
--
-- Forward-only, expand-only. Safe to re-run.
-- NOTE: the VIEW is dropped + recreated (not CREATE OR REPLACE) because
-- Postgres forbids inserting a new column ahead of existing ones via
-- REPLACE — same reasoning as migration 0016.

drop view if exists leaderboard.season_standings;

create view leaderboard.season_standings as
  select
    p.season_id                          as season_id,
    p.id                                  as participant_id,
    max(u.display_name)                  as display_name,
    coalesce(sum(e.amount), 0)::bigint   as total_points,
    count(e.id)::bigint                  as entry_count,
    p.joined_at                          as joined_at
  from competition.participants p
  join identity.users u
    on u.id = p.user_id
  left join ledger.point_entries e
    on e.participant_id = p.id
   and e.round_id in (
         select r.id
         from competition.rounds r
         where r.season_id = p.season_id
       )
  group by p.season_id, p.id, p.joined_at;

comment on view leaderboard.season_standings is
  'Season-scoped standings projection (Axiom 5). One row per season '
  'participant (ACTIVE or WITHDRAWN); display_name is the platform-owned '
  'name from identity.users; total_points/entry_count/joined_at as before. '
  'Ranks are assigned by the pure domain SeasonLeaderboard.rank, not stored '
  'here.';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_standings set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_standings from anon;
grant select on leaderboard.season_standings to authenticated;
