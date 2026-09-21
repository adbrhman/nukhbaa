-- ============================================================================
-- Migration 0066: proactive pushes -- per-type switches and one send record
-- (plan P3-3 / P3-4, batch 2)
--
-- ## Three new switches
-- One boolean per proactive type on notification_preferences (0063), each
-- defaulting to TRUE like the reminder: pre_match (a followed team plays
-- soon), streak_saver and overtaken (batch 3). An old client that never sends
-- a switch cannot turn it off by omission.
--
-- ## One record of what was sent
-- notification.proactive_sends holds one row per (user, kind, ref): the
-- fixture a pre-match push was about, the day a streak saver was about, the
-- week an overtaken push was about. The primary key is what stops a second
-- push for the same thing, and send_date (the Riyadh day) is what the weekly
-- budget counts, together with reminder_sends (0040).
--
-- Server-only: RLS on, no policy and no grant for anon or authenticated.
--
-- ADDITIVE ONLY. Three columns with defaults, one table, one index.
-- Safe to re-run. MUST be on the live DB before the server that reads it is
-- deployed: the reminder sweep's weekly budget counts this table.
-- ============================================================================

begin;

alter table notification.notification_preferences
  add column if not exists pre_match    boolean not null default true,
  add column if not exists streak_saver boolean not null default true,
  add column if not exists overtaken    boolean not null default true;

create table if not exists notification.proactive_sends (
  user_id   uuid        not null,
  kind      text        not null,
  ref_id    uuid        not null,
  send_date date        not null,
  sent_at   timestamptz not null default now(),
  constraint proactive_sends_pkey primary key (user_id, kind, ref_id),
  constraint proactive_sends_kind_check
    check (kind in ('pre_match', 'streak_saver', 'overtaken')),
  constraint proactive_sends_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade
);

comment on table notification.proactive_sends is
  'One row per proactive push sent (plan P3-4): the key stops a repeat for '
  'the same (user, kind, ref); send_date, a Riyadh day, is what the shared '
  'weekly budget counts together with reminder_sends.';

-- The weekly budget asks "how many since Monday" for a handful of users.
create index if not exists proactive_sends_user_date_idx
  on notification.proactive_sends (user_id, send_date);

alter table notification.proactive_sends enable row level security;

revoke all on notification.proactive_sends from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from notification.proactive_sends;                   -- 0
-- select pre_match, streak_saver, overtaken
--   from notification.notification_preferences limit 1;               -- t t t
