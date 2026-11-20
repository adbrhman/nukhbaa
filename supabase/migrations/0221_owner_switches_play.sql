-- ============================================================================
-- Migration 0221: the owners' switches for the predictions and the chat
--
-- ADDITIVE ONLY. One check constraint widened by two values and two rows
-- added, both on; no other row is written, changed or removed.
--
-- Item 3 of the owner's report and the launch batch (script 291): beside
-- the crowning (0218), two stops in the owners' hands, read by the server
-- on every request. 'predictions' off refuses every new or changed
-- prediction; 'chat' off refuses every new message in the head-to-head
-- chat. Reading stays open, and nothing already saved is touched. They
-- are turned from the owners' page («المفاتيح»).
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table ops.owner_switches
  drop constraint if exists owner_switches_key_check;
alter table ops.owner_switches
  add constraint owner_switches_key_check
  check (switch_key in ('crowning', 'predictions', 'chat'));

insert into ops.owner_switches (switch_key, is_on)
values ('predictions', true), ('chat', true)
on conflict (switch_key) do nothing;

insert into ops.applied_migrations (version)
values ('0221_owner_switches_play')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select switch_key, is_on from ops.owner_switches order by switch_key;
--   chat | true, crowning | (as it was), predictions | true
