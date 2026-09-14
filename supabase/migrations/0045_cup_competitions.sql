-- ============================================================================
-- Migration 0045: cup competitions
--
-- ADDITIVE ONLY. Ten new rows in `football_data.leagues` (migration 0027).
-- No row is updated, no row is deleted, no column is added, no club is
-- duplicated. Safe to re-run: the insert skips any name already present.
--
-- ## Why is_continental = true for all ten
-- Migration 0038 established the rule: a competition that draws its entrants
-- from other leagues does NOT own a club list, and tagging clubs to it would
-- mean a duplicate row and a duplicate crest. Every competition added here is
-- of that kind --
--   * the domestic cups (كأس السوبر الإسباني، كأس فرنسا، كأس الاتحاد
--     الإنجليزي، كأس ألمانيا، كأس خادم الحرمين الشريفين) enter clubs that
--     already sit under their domestic league;
--   * كأس العالم للأندية enters clubs from every confederation;
--   * the national-team competitions (كأس الخليج، كأس آسيا، كأس أمم
--     إفريقيا، تصفيات كأس أمم إفريقيا 2027) enter no club at all.
-- So each one offers the whole catalog in the admin picker, exactly as the
-- Champions League already does, and no `football_data.teams` row changes.
--
-- ## Known gap (deliberate, not an oversight)
-- `football_data.teams` holds clubs only. The four national-team
-- competitions therefore have no national side to pick yet; their entry in
-- the catalog is real and selectable, but a fixture under them cannot be
-- registered until national teams are seeded. That seeding is a separate,
-- equally additive batch.
--
-- logo_url stays NULL, as it is for the six leagues already seeded: the
-- fixture card falls back to the name alone (migration 0027's contract).
-- ============================================================================

begin;

insert into football_data.leagues (name, is_continental)
select v.name, true
from (values
  ('كأس السوبر الإسباني'),
  ('كأس فرنسا'),
  ('كأس الاتحاد الإنجليزي'),
  ('كأس ألمانيا'),
  ('كأس الخليج'),
  ('كأس آسيا'),
  ('كأس أمم إفريقيا'),
  ('كأس خادم الحرمين الشريفين'),
  ('كأس العالم للأندية'),
  ('تصفيات كأس أمم إفريقيا 2027')
) as v (name)
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = v.name
);

commit;

-- Verification:
-- select name, is_continental from football_data.leagues order by is_continental, name;
