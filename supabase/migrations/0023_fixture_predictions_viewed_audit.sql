-- 0023_fixture_predictions_viewed_audit.sql
-- Extends `admin.audit_action` with the new admin fixture-report capability
-- (forward-only `alter type … add value`, exactly as 0010_admin.sql /
-- 0015_round_predictions_audit.sql document).

alter type admin.audit_action add value if not exists 'fixture_predictions_viewed';
