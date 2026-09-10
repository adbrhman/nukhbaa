-- ============================================================================
-- Migration 0040 -- notification.reminder_sends: one row per user per day on
-- which the prediction reminder was sent.
--
-- The scheduler wakes every 15 minutes, so without this table a user inside
-- the 30-minute firing window would be reminded twice, and a container restart
-- would repeat the whole day. The primary key IS the idempotency: a second
-- attempt for the same (user, day) inserts nothing.
--
-- reminder_date is a DATE in the reminder's own zone (UTC+3), not a timestamp:
-- the unit of "already reminded" is the day, not the instant.
--
-- Tier-3 bookkeeping. Nothing on the points path reads it (Axiom 5).
-- Forward-only, expand-only. Safe to re-run.
-- ============================================================================

create table if not exists notification.reminder_sends (
  user_id       uuid        not null,
  reminder_date date        not null,
  sent_at       timestamptz not null default now(),
  constraint reminder_sends_pkey primary key (user_id, reminder_date),
  constraint reminder_sends_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade
);

comment on table notification.reminder_sends is
  'Which users have already received the prediction reminder on which day '
  '(zone UTC+3). The primary key is what makes a repeated scheduler tick a '
  'no-op rather than a second notification.';

-- ---------------------------------------------------------------------------
-- RLS: no client access. This is scheduler bookkeeping; the backend (service
-- role) bypasses RLS and owns every read and write.
-- ---------------------------------------------------------------------------
alter table notification.reminder_sends enable row level security;

revoke select, insert, update, delete, truncate
  on notification.reminder_sends from anon, authenticated;

drop policy if exists reminder_sends_no_client_access
  on notification.reminder_sends;
create policy reminder_sends_no_client_access
  on notification.reminder_sends
  for select
  to anon, authenticated
  using (false);
