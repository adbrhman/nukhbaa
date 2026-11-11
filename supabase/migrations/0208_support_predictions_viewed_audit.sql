-- ============================================================================
-- Migration 0208: support reads a player's open predictions (script 261)
--
-- ADDITIVE ONLY. One value added to an enum. No row of any table is written,
-- changed or removed.
--
-- Why: decided by the owner on 2026-11-11, before the Google Play release.
-- The admins play like any player, so nobody, an admin included, reads
-- another player's prediction before its match kicks off. The one
-- exception is support: from a player's own support conversation an admin
-- may read that player's predictions of the matches not yet started, to
-- answer him, with a reason. The player is told in the conversation, and
-- the reading is kept in the audit trail:
--
-- * admin.audit_action gains 'support_predictions_viewed': its target the
--   player's id, its reason the one the admin typed.
--
-- Apply BEFORE deploying the server that writes 'support_predictions_viewed'.
-- Safe to re-run.
-- ============================================================================

begin;

alter type admin.audit_action
  add value if not exists 'support_predictions_viewed';

insert into ops.applied_migrations (version)
values ('0208_support_predictions_viewed_audit')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0208_support_predictions_viewed_audit';           -- 1 row
-- select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
--  where t.typname = 'audit_action'
--    and e.enumlabel = 'support_predictions_viewed';                    -- 1 row
