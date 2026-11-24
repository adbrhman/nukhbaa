-- ============================================================================
-- Migration 0226: the Elite Cup's pair outcome 'direction'
--
-- ADDITIVE ONLY. One check constraint widened by one value; no row is
-- written, changed or removed.
--
-- Script 319 (owner decision 2026-11-25): a cup pair level on points and on
-- exact scorelines is decided by the right directions on the stage's
-- fixtures before it goes to the league month. The pair's stored outcome
-- gets the new value 'direction' (0190 allowed points, exact, league,
-- walkover, both_absent).
--
-- Apply this BEFORE the server that carries script 319 is deployed: the
-- server writes 'direction' as soon as it judges a pair that way.
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table gamification.h2h_cup_results
  drop constraint if exists h2h_cup_results_outcome_known;
alter table gamification.h2h_cup_results
  add constraint h2h_cup_results_outcome_known check (outcome in (
    'points', 'exact', 'direction', 'league', 'walkover', 'both_absent'
  ));

insert into ops.applied_migrations (version)
values ('0226_h2h_cup_direction_outcome')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select pg_get_constraintdef(oid) from pg_constraint
-- where conname = 'h2h_cup_results_outcome_known';
--   CHECK (outcome = ANY (ARRAY['points', 'exact', 'direction', 'league',
--   'walkover', 'both_absent']))
