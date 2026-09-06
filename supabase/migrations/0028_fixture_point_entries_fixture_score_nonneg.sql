-- Migration 0028 — the `fixture_score` non-negative CHECK on
-- ledger.fixture_point_entries, split out of migration 0020.
--
-- Why this is a separate file, not a line in 0020: 0020 adds the enum value
-- with `alter type ledger.entry_kind add value 'fixture_score'` and then
-- referenced that same new value in a CHECK constraint. PostgreSQL rejects
-- that with SQLSTATE 55P04 ("unsafe use of new value ... of enum type") when
-- the file runs as a single transaction, which is exactly what happens on any
-- clean-database rebuild (`supabase db reset`, the CI migration gate). The
-- production database was unaffected because its migrations were applied
-- statement by statement, so the enum value was already committed.
--
-- By the time this file runs, 0020's transaction has committed and the enum
-- value is usable. The constraint below is byte-identical in meaning to the
-- one 0020 used to declare inline, so the resulting schema is unchanged.
--
-- Forward-only, additive, and guarded: on the production database the
-- constraint already exists and this migration does nothing.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fixture_point_entries_fixture_score_nonneg'
      and conrelid = 'ledger.fixture_point_entries'::regclass
  ) then
    alter table ledger.fixture_point_entries
      add constraint fixture_point_entries_fixture_score_nonneg
      check (entry_kind <> 'fixture_score' or amount >= 0);
  end if;
end
$$;
