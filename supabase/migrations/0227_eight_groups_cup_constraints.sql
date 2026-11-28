-- ============================================================================
-- Migration 0227: the Elite Cup widened for eight groups
--
-- ADDITIVE ONLY. Three check constraints are widened; no row is written,
-- changed or removed, and no table, column, index or trigger is added or
-- dropped.
--
-- Owner decision 2026-11-28 (scripts 353 and 354): from the draw of December
-- 2026 the 160 most committed players are dealt into EIGHT equal groups, and
-- those eight groups carry the Elite Cup (the groups after them are the
-- catch-all and have no cup path that month). The first three places of each
-- of the eight groups qualify, so each of the three paths has eight players
-- and needs a quarter-final (four pairs) before the semi-final and the final.
--
--   h2h_cup_entries_group_range  group_number  1..4            -> 1..8
--   h2h_cup_stages_stage_known   stage          semi, final     -> quarter,
--                                                                  semi, final
--   h2h_cup_pairs_slot_range     slot           1..2            -> 1..4
--
-- Each new check admits everything 0190 admitted, so every stored row still
-- satisfies it. The place range (1..3), the path range (1..3), the order
-- trigger and the append-only triggers are untouched.
--
-- Nothing in the server writes a quarter-final yet: this migration only
-- makes the database accept it. Apply it in the SQL Editor BEFORE the server
-- that writes eight-group qualifiers is deployed.
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table gamification.h2h_cup_entries
  drop constraint if exists h2h_cup_entries_group_range;
alter table gamification.h2h_cup_entries
  add constraint h2h_cup_entries_group_range
  check (group_number between 1 and 8);

alter table gamification.h2h_cup_stages
  drop constraint if exists h2h_cup_stages_stage_known;
alter table gamification.h2h_cup_stages
  add constraint h2h_cup_stages_stage_known
  check (stage in ('quarter', 'semi', 'final'));

alter table gamification.h2h_cup_pairs
  drop constraint if exists h2h_cup_pairs_slot_range;
alter table gamification.h2h_cup_pairs
  add constraint h2h_cup_pairs_slot_range
  check (slot between 1 and 4);

comment on table gamification.h2h_cup_entries is
  'The Elite Cup''s qualifiers of a month (0190, widened in 0227): the first '
  'three places of each of the eight cup groups once the 19 rounds were '
  'judged. Append-only.';

insert into ops.applied_migrations (version)
values ('0227_eight_groups_cup_constraints')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0227_eight_groups_cup_constraints';             -- 1 row
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conname in ('h2h_cup_entries_group_range',
--                    'h2h_cup_stages_stage_known',
--                    'h2h_cup_pairs_slot_range');                   -- 3 rows
--   group_number 1..8, stage in (quarter, semi, final), slot 1..4
