-- Migration 0016 — Live/partial scoring (Phase: احتساب فوري). Widens the
-- Scoring schema so a round can be (re-)scored while it is still `open` or
-- `locked` with an incomplete result set, instead of only after every
-- fixture's result is in and the round is `locked`. Forward-only,
-- expand-only (Platform ADR). Safe to re-run.
--
--   1. scoring.round_score_fixtures.grade — widen to allow 'pending': a
--      predicted fixture whose actual result hasn't been recorded yet
--      (domain: FixtureScoreGrade.pending). Always worth zero points; a later
--      re-score, once the result lands, overwrites it with the real grade.
--   2. scoring.reject_score_before_lock() — the database backstop that
--      rejected any round_scores write unless the round was `locked` or
--      `scored`. The application no longer requires a round to be locked
--      before scoring it (ScoreRound now scores `open` rounds too, live), so
--      the backstop is widened to allow `open` as well. It still rejects
--      anything else (there is no fourth round status), keeping the
--      trigger's role as a genuine backstop rather than a no-op.
do $$
begin
  alter table scoring.round_score_fixtures
    drop constraint if exists round_score_fixtures_grade_valid;

  alter table scoring.round_score_fixtures
    add constraint round_score_fixtures_grade_valid
    check (
      grade in (
        'exact_scoreline', 'correct_outcome', 'incorrect', 'missed', 'pending'
      )
    );
end $$;

comment on constraint round_score_fixtures_grade_valid
  on scoring.round_score_fixtures is
  'The five stable FixtureScoreGrade wire tokens (Axiom 3). ''pending'' means '
  'a prediction exists but the fixture''s actual result has not been '
  'recorded yet — live/partial scoring (Phase: احتساب فوري), always zero '
  'points, overwritten by a later re-score.';

create or replace function scoring.reject_score_before_lock()
returns trigger
language plpgsql
as $$
declare
  round_state competition.round_status;
begin
  select status into round_state
  from competition.rounds
  where id = new.round_id;

  -- Live/partial scoring (Phase: احتساب فوري): an `open` round may now be
  -- scored too, so every fixture without a result yet shows a live `pending`
  -- grade. `locked` and `scored` remain allowed as before; anything else
  -- (a missing/foreign round) is still rejected.
  if round_state not in ('open', 'locked', 'scored') then
    raise exception
      'a round can only be scored once it exists '
      '(round % is %)',
      new.round_id, coalesce(round_state::text, 'missing')
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
