-- ============================================================================
-- Migration 0088: the audit token for the admin error log (2026-10-03)
--
-- ADDITIVE ONLY. One enum value; no row of any table is written, changed or
-- removed.
--
-- admin.audit_action gains 'error_updated': AdminErrorLog records every
-- change an admin makes to an error in the error log (0087) -- its status,
-- severity, assignee or notes -- with the old and new values in the reason.
--
-- Safe to re-run.
-- ============================================================================

-- ALTER TYPE ... ADD VALUE stays outside the transaction (as in 0044, 0085).
alter type admin.audit_action
  add value if not exists 'error_updated';

begin;

insert into ops.applied_migrations (version) values ('0088_error_log_admin')
on conflict (version) do nothing;

commit;
