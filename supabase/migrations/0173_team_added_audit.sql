-- ============================================================================
-- Migration 0173: an admin adds a club to the catalog (script 91)
--
-- ADDITIVE ONLY. One value added to an enum. No row of any table is written,
-- changed or removed.
--
-- Why: on 2026-10-15 an admin added "هوفنهايم - بيشتكاش" by hand while the
-- fixtures sync had already added "هوفنهايم - بشكتاش": the add form took any
-- name, and a name the catalog does not know carries no team id, so neither
-- the server's check (batch 138) nor the schedule's trigger (0110) saw the
-- same match. Decided by the owner on 2026-10-16: a match is added with both
-- clubs picked from the list, and a club the list lacks is added to it from
-- the admin panel (POST /admin/teams, AdminAddTeam), never typed into a match.
--
-- * admin.audit_action gains 'team_added': the audit row of every club an
--   admin adds, its target the new team's id and its reason the name.
--
-- The club itself goes into football_data.teams (0013, league_id 0048) as
-- the seed migrations put theirs; a name whose spelling key
-- (competition.team_name_key, 0110) is already there is refused, so the list
-- never holds one club twice under two spellings of one name.
--
-- Apply BEFORE deploying the server that writes 'team_added'.
-- Safe to re-run.
-- ============================================================================

begin;

alter type admin.audit_action
  add value if not exists 'team_added';

insert into ops.applied_migrations (version)
values ('0173_team_added_audit')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0173_team_added_audit';                       -- 1 row
-- select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
--  where t.typname = 'audit_action' and e.enumlabel = 'team_added'; -- 1 row
