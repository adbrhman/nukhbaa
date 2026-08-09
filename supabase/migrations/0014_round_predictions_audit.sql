-- 0014_round_predictions_audit.sql
-- Extends `admin.audit_action` with the new admin round-report capability
-- (forward-only `alter type … add value`, exactly as 0010_admin.sql documents).

alter type admin.audit_action add value if not exists 'round_predictions_viewed';
