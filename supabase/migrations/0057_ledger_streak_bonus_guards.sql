-- ============================================================================
-- Migration 0057: guards for ledger 'streak_bonus' entries (P1-4, step 1 of 3)
--
-- Requires 0056 to be applied AND committed first (SQLSTATE 55P04 otherwise).
--
-- 1. A bonus is never negative (mirrors 0028 for fixture_score).
-- 2. A bonus is granted at most once per participant per threshold. The
--    source_ref names the threshold ('streak:7'); participant_id already
--    scopes it to one season, so the pair is exactly "once per threshold per
--    season". The existing key (participant_id, fixture_id, entry_kind,
--    source_ref) cannot do this: the fixture that completes a day differs from
--    one streak to the next, so it would let a re-reached threshold pay twice.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fixture_point_entries_streak_bonus_nonneg'
      and conrelid = 'ledger.fixture_point_entries'::regclass
  ) then
    alter table ledger.fixture_point_entries
      add constraint fixture_point_entries_streak_bonus_nonneg
      check (entry_kind <> 'streak_bonus' or amount >= 0);
  end if;
end
$$;

create unique index if not exists fixture_point_entries_streak_bonus_once_idx
  on ledger.fixture_point_entries (participant_id, source_ref)
  where entry_kind = 'streak_bonus';
