-- ============================================================================
-- Migration 0068: who passed a member, on their rank mark (plan P2-7)
--
-- The overtaken sweep (0067) already works out who passed whom. The league
-- screen shows it as a card ("X passed you"), so the answer is kept on the
-- victim's mark: passed_by is the member who passed them, passed_at when the
-- sweep saw it. A later sweep that finds no new pass leaves both as they
-- are; the server shows the card only while the passer still ranks above.
--
-- ADDITIVE ONLY. Two nullable columns. Safe to re-run.
-- ============================================================================

begin;

alter table gamification.weekly_league_rank_marks
  add column if not exists passed_by uuid
    references identity.users (id) on delete set null,
  add column if not exists passed_at timestamptz;

commit;

-- Verification (read-only):
-- select count(passed_by) from gamification.weekly_league_rank_marks;  -- 0
