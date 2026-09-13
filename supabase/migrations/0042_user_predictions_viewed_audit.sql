-- Adds the append-only audit token for the admin single-user prediction history read.
alter type admin.audit_action
  add value if not exists 'user_predictions_viewed';
