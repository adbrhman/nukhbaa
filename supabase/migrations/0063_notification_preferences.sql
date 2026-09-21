-- ============================================================================
-- Migration 0063: notification preferences (P3-1)
--
-- The daily prediction reminder (0039, 0040) goes to every participant who
-- has not predicted yet, and until now nobody could turn it off short of
-- revoking the OS permission -- which also silences everything else the app
-- will ever send. This table is the per-user switch.
--
-- ## One row per user, created on first change
-- A user with no row gets the defaults, and every default is TRUE: the
-- reminder keeps reaching exactly the people it reaches today. The row
-- appears only when a user changes something, so nothing is backfilled and
-- the table starts empty.
--
-- ## One column per kind, not a key/value list
-- Each kind is a boolean the server reads by name. A new kind (P3-2 onwards)
-- is an additive column with its own default, so an old client that never
-- sends it cannot switch it off by accident.
--
-- ## Server-only, like reminder_sends (0040)
-- The client reads and writes its own row through GET/PUT
-- /me/notification-preferences, where the owner comes from the verified
-- token. RLS is on and no policy is granted to anon or authenticated.
--
-- ADDITIVE ONLY. One table, no data written. Safe to re-run.
-- ============================================================================

begin;

create table if not exists notification.notification_preferences (
  user_id             uuid        primary key,
  prediction_reminder boolean     not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint notification_preferences_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade
);

comment on table notification.notification_preferences is
  'Per-user notification switches (P3-1). No row means every default, and '
  'every default is on. Written only through PUT '
  '/me/notification-preferences; server-only for everything else.';

comment on column notification.notification_preferences.prediction_reminder is
  'false = the daily prediction reminder skips this user. The sweep does not '
  'record a skipped user in reminder_sends, so switching it back on the same '
  'day still lets that day''s reminder through.';

drop trigger if exists notification_preferences_set_updated_at
  on notification.notification_preferences;
create trigger notification_preferences_set_updated_at
  before update on notification.notification_preferences
  for each row
  execute function identity.set_updated_at();

-- The sweep asks "who turned the reminder off", once per firing.
create index if not exists notification_preferences_reminder_off_idx
  on notification.notification_preferences (user_id)
  where prediction_reminder = false;

alter table notification.notification_preferences enable row level security;

revoke all on notification.notification_preferences from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from notification.notification_preferences;   -- 0
-- select relrowsecurity from pg_class
--  where oid = 'notification.notification_preferences'::regclass; -- t
