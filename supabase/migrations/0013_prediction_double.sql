-- Migration 0013 — The prediction "double": one fixture per prediction may be
-- marked to score double points, restored from the legacy platform at the
-- user's explicit request (2026-08 decision). Two additive changes, both
-- forward-only / expand-only (Platform ADR), both safe to re-run:
--
--   1. `prediction.prediction_scores.is_double` — a per-fixture-score flag.
--      The domain enforces "at most one per prediction"
--      (`Prediction._validateScores` -> `prediction.multiple_doubles`); this
--      partial unique index is the physical backstop (Axiom 6): even a rogue
--      or buggy writer can never persist two doubles on the same prediction.
--
--   2. `scoring.round_score_fixtures.grade` gains a fourth allowed token,
--      `missed` — a fixture that kicked off before the participant ever
--      predicted it (per-fixture kickoff lock, `SubmitPrediction` rule 3) is
--      graded `missed` rather than rejected, always worth zero points
--      (`domain.Scoring._gradeFixture` never applies the double multiplier to
--      it — there is no forecast to double). The existing
--      `round_score_fixtures_points_nonneg` check already covers zero.
--
-- Neither change touches `prediction.predictions`, `scoring.fixture_results`,
-- or `scoring.round_scores` — the aggregate roots and their RLS policies are
-- untouched; only a child table's schema and a check constraint widen.

-- ---------------------------------------------------------------------------
-- 1. prediction.prediction_scores.is_double
-- ---------------------------------------------------------------------------
alter table prediction.prediction_scores
  add column if not exists is_double boolean not null default false;

comment on column prediction.prediction_scores.is_double is
  'Whether the participant marked this fixture as their round double '
  '(at most one true per prediction_id — see '
  'prediction_scores_one_double_uniq). Scoring multiplies this fixture''s '
  'points by the frozen ruleset''s double_multiplier (Axiom 5: read from the '
  'snapshot at scoring time, never baked into code).';

-- EXACTLY ZERO OR ONE double per prediction — the physical backstop for the
-- domain's "at most one" invariant (Axiom 4/6). A partial unique index (rather
-- than a table-level constraint) so it applies only to the `true` rows; any
-- number of `is_double = false` rows coexist freely.
drop index if exists prediction_scores_one_double_uniq;
create unique index prediction_scores_one_double_uniq
  on prediction.prediction_scores (prediction_id)
  where is_double;

-- ---------------------------------------------------------------------------
-- 2. scoring.round_score_fixtures.grade — widen to allow 'missed'
-- ---------------------------------------------------------------------------
alter table scoring.round_score_fixtures
  drop constraint if exists round_score_fixtures_grade_valid;
alter table scoring.round_score_fixtures
  add constraint round_score_fixtures_grade_valid
    check (
      grade in ('exact_scoreline', 'correct_outcome', 'incorrect', 'missed')
    );

comment on table scoring.round_score_fixtures is
  'Per-fixture grade + points of a round score (Axiom 3, the football seam). '
  'Child of scoring.round_scores; cascades on parent delete. Rewritten in '
  'place on re-score. fixture_id is opaque (no FK). Server-computed (Axioms '
  '2/5). grade = ''missed'' means the fixture kicked off before the '
  'participant ever predicted it (per-fixture kickoff lock); always 0 points.';
