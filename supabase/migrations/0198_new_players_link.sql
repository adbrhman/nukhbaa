-- ============================================================================
-- Migration 0198: the new-player push opens its list (script 202)
--
-- ADDITIVE ONLY. No row is changed or removed.
--
-- The admins' push about a new player now names him and opens the list of
-- the players who joined recently. A tap on a push is recorded in
-- notification.push_opens (0069), whose check lists every link a push can
-- carry (0189 is the last to list them): one more, 'new_players'.
--
-- Apply BEFORE deploying the server. Safe to re-run.
-- ============================================================================

begin;

alter table notification.push_opens
  drop constraint if exists push_opens_link_check;
alter table notification.push_opens
  add constraint push_opens_link_check
    check (link in ('fixtures', 'league', 'inbox', 'duel',
                    'support', 'support_inbox', 'h2h', 'new_players'));

insert into ops.applied_migrations (version)
values ('0198_new_players_link')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0198_new_players_link';                     -- 1 row
