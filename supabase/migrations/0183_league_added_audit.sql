-- ============================================================================
-- Migration 0183: an admin adds a league to the catalog (script 139)
--
-- ADDITIVE ONLY. One value added to an enum. No row of any table is written,
-- changed or removed.
--
-- Why: some competitions play rarely but carry strong matches, and the
-- league list held only what the seed migrations put there (0027, 0038,
-- 0103, 0104, 0180): a match of any other competition had nowhere to be
-- filed but a league it does not belong to. Asked by the owner on
-- 2026-10-24: a "new league" entry in the add-match form's league list,
-- where the admin types the name, and the match is filed under it.
--
-- * admin.audit_action gains 'league_added': the audit row of every league
--   an admin adds (POST /admin/leagues, AdminAddLeague), its target the new
--   league's id and its reason the name.
--
-- The league itself goes into football_data.leagues (0027) with
-- is_continental = true (0038), as 0104 filed the big derbies: its clubs
-- come from the whole catalog, and no club is tagged to it. A name whose
-- spelling key (competition.team_name_key, 0110) is already there is
-- refused, so the list never holds one league twice under two spellings.
--
-- Apply BEFORE deploying the server that writes 'league_added'.
-- Safe to re-run.
-- ============================================================================

begin;

alter type admin.audit_action
  add value if not exists 'league_added';

insert into ops.applied_migrations (version)
values ('0183_league_added_audit')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0183_league_added_audit';                        -- 1 row
-- select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
--  where t.typname = 'audit_action' and e.enumlabel = 'league_added'; -- 1 row
