-- ============================================================================
-- Migration 0036: hide the empty league competitions
--
-- ADDITIVE/MODIFY ONLY. No DELETE, no DROP. Every competition, season,
-- participant, fixture, prediction and point entry stays exactly where it is.
-- The only thing this changes is one flag on competitions that have never
-- held a single fixture.
--
-- Why: the seed files created a competition per league, each with a season
-- whose window is the current month. The database confirms they were never
-- used -- 0 fixtures and 0 point entries in all seven, against 50 fixtures
-- and 15,750 points in "شهر 9" / 09/2026. What they DO have is participants,
-- because automatic enrolment used to join every season that was open by
-- date. That is why the app reports "9 مسابقات متاحة" and why the trophy
-- history opens on six "2026/27" rows at rank #1 with zero points.
--
-- Flipping visibility to 'private' takes them out of every public read (the
-- RLS policies in 0002 key off `visibility = 'public'`) without touching a
-- row anyone owns. It is one UPDATE away from being reversed.
--
-- The predicate is data-driven, not a hardcoded list of names: a public
-- competition with no fixture in any of its seasons. "شهر 9" has fifty, so
-- it is untouched. Safe to re-run.
-- ============================================================================

begin;

update competition.competitions c
set visibility = 'private',
    updated_at = now()
where c.visibility = 'public'
  and not exists (
    select 1
    from competition.seasons s
    join competition.season_fixtures sf on sf.season_id = s.id
    where s.competition_id = c.id
  );

commit;

-- Verification: this should now list only the monthly contest.
-- select name, visibility from competition.competitions order by visibility, name;
