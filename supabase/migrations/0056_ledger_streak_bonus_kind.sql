-- ============================================================================
-- Migration 0056: ledger.entry_kind gains 'streak_bonus' (P1-4, step 1 of 3)
--
-- ADDITIVE ONLY. One enum value and nothing else in this file.
--
-- Why it is alone: PostgreSQL refuses to use an enum value inside the
-- transaction that added it (SQLSTATE 55P04) -- the same reason 0020 and 0028
-- are two files. The constraint and the unique index that use the value are
-- in 0057. Apply 0056 FIRST and let it commit, then apply 0057.
--
-- A streak bonus is an entry in ledger.fixture_point_entries, never a row in
-- a second points table (docs/gamification-audit.md sections 3 and 9).
-- ============================================================================

alter type ledger.entry_kind add value if not exists 'streak_bonus';
