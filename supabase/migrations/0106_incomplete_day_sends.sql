-- ============================================================================
-- Migration 0106: notification.incomplete_day_sends -- one row per user per
-- Riyadh day on which the "you still have N matches to predict" push went
-- out (batch 117).
--
-- The daily reminder (0040) reaches only a player who predicted NONE of the
-- day's matches. A player who predicted some and forgot the rest now gets
-- one push, an hour and a half before the first match they left open,
-- saying how many are still open (decided with the owner 2026-10-12).
--
-- Its own table, not proactive_sends (0066): the weekly budget counts
-- reminder_sends and proactive_sends, and the owner decided this push stays
-- outside it. The primary key is the "once a day": a second tick or a
-- restart inserts nothing.
--
-- send_date is a DATE in Riyadh time (UTC+3), like reminder_sends.
--
-- Server-only: RLS on, no policy and no grant for anon or authenticated.
--
-- ADDITIVE ONLY. One table. Nothing on the points path reads it. Safe to
-- re-run. MUST be on the live DB before the server that writes it is
-- deployed.
-- ============================================================================

begin;

create table if not exists notification.incomplete_day_sends (
  user_id   uuid        not null,
  send_date date        not null,
  sent_at   timestamptz not null default now(),
  constraint incomplete_day_sends_pkey primary key (user_id, send_date),
  constraint incomplete_day_sends_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade
);

comment on table notification.incomplete_day_sends is
  'Which users got the "N matches still to predict" push on which Riyadh '
  'day (batch 117). The key keeps it to one a day; the weekly push budget '
  'does not count it.';

alter table notification.incomplete_day_sends enable row level security;

revoke all on notification.incomplete_day_sends from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0106_incomplete_day_sends')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select count(*) from notification.incomplete_day_sends;              -- 0
-- select version from ops.applied_migrations
--  where version = '0106_incomplete_day_sends';                          -- 1 row
