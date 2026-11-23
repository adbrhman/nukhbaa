-- ============================================================================
-- Migration 0225: the owners' switches for the head-to-head league
--
-- ADDITIVE ONLY. One check constraint widened by three values and three rows
-- added, all on; no other row is written, changed or removed.
--
-- Script 304: beside the crowning (0218), the predictions and the chat
-- (0221), three stops in the owners' hands, read by the server on every run:
--   h2h_rounds         off: no new round is approved, by the scheduler or an
--                      admin. Rounds already approved still lock and settle.
--   h2h_cup            off: the Elite Cup keeps nothing (no entries, stage,
--                      result or title); what is stored stays.
--   h2h_cup_crowning   off: the cup still runs, but no path is crowned.
-- They are turned from the owners' page («المفاتيح» and «المواجهات»).
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table ops.owner_switches
  drop constraint if exists owner_switches_key_check;
alter table ops.owner_switches
  add constraint owner_switches_key_check
  check (switch_key in (
    'crowning', 'predictions', 'chat',
    'h2h_rounds', 'h2h_cup', 'h2h_cup_crowning'
  ));

insert into ops.owner_switches (switch_key, is_on)
values ('h2h_rounds', true), ('h2h_cup', true), ('h2h_cup_crowning', true)
on conflict (switch_key) do nothing;

insert into ops.applied_migrations (version)
values ('0225_owner_switches_h2h')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select switch_key, is_on from ops.owner_switches order by switch_key;
--   chat, crowning, h2h_cup, h2h_cup_crowning, h2h_rounds, predictions
