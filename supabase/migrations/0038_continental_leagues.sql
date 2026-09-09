-- ============================================================================
-- Migration 0038: mark the continental competitions
--
-- ADDITIVE ONLY. One new column with a safe default; no row is deleted and no
-- club is duplicated.
--
-- The seed files treated the Champions League, the Europa League and the
-- English League Cup as leagues with clubs of their own, and duplicated the
-- entrants: Barcelona exists once as a LaLiga row and again as a UCL row.
-- Ten such duplicates were seeded for the Champions League and fifteen for
-- the Europa League, out of thirty-six entrants each; the League Cup got
-- none. That is why those dropdowns look empty or half-filled.
--
-- Finishing the duplication is the wrong repair. Barcelona in the Champions
-- League is Barcelona: a second row is a second crest to keep correct, and
-- correcting one leaves the other wrong.
--
-- So the flag says where a competition's entrants come from. A continental
-- competition offers the whole catalog; a domestic league keeps its own
-- clubs. The twenty-five duplicate rows already seeded stay where they are --
-- fixtures may already reference them -- and the client de-duplicates by
-- name when it lists a continental competition's teams.
-- ============================================================================

begin;

alter table football_data.leagues
  add column if not exists is_continental boolean not null default false;

comment on column football_data.leagues.is_continental is
  'True when this competition draws its entrants from other leagues (a '
  'continental cup, a domestic cup) rather than owning a club list. Clients '
  'offering teams for such a competition must offer the whole catalog: '
  'tagging clubs to it would mean a duplicate row, and a duplicate crest.';

update football_data.leagues
set is_continental = true
where btrim(name) in (
  'دوري أبطال أوروبا',
  'الدوري الأوروبي',
  'كأس الرابطة الإنجليزية'
);

commit;

-- Verification:
-- select name, is_continental from football_data.leagues order by is_continental desc, name;
