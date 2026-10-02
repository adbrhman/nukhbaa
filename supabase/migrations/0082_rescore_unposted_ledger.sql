-- ============================================================================
-- Migration 0082: the rescore sweep also finishes unposted ledger entries
--
-- ADDITIVE ONLY. One function replaced (same name, arguments and result);
-- no row is touched.
--
-- Why: settling a result is three writes -- record it, score it
-- (scoring.fixture_scores), post it (ledger.fixture_point_entries). Since
-- 0080 the sweep found fixtures whose SCORING was left unfinished, but not
-- those whose scores were written while the ledger post failed (a timeout or
-- a restart between the two steps). The boards read fixture_scores and stay
-- right; the ledger -- the points history and balances -- silently missed
-- those points and nothing ever asked again.
--
-- A fixture now also qualifies when one of its scores differs from the
-- participant's ledger total for it (fixture_score + correction entries; a
-- streak bonus is not part of a fixture's score), including no entry at all.
-- The sweep runs ScoreFixture then PostFixtureToLedger, both idempotent, so
-- a fixture found here converges and is not found again.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function scoring.fixtures_with_unscored_predictions(
  p_recorded_from   timestamptz,
  p_recorded_before timestamptz,
  p_limit           integer
)
returns table (fixture_id uuid)
language sql
stable
set search_path = ''
as $$
  select r.fixture_id
    from scoring.fixture_results r
   where r.recorded_at >= p_recorded_from
     and r.recorded_at < p_recorded_before
     and (
       exists (
         select 1
           from prediction.fixture_predictions fp
          where fp.fixture_id = r.fixture_id
            and not exists (
              select 1
                from scoring.fixture_scores s
               where s.fixture_id = fp.fixture_id
                 and s.participant_id = fp.participant_id
            )
       )
       or exists (
         select 1
           from scoring.fixture_scores s
          where s.fixture_id = r.fixture_id
            and s.points is distinct from (
              select sum(e.amount)
                from ledger.fixture_point_entries e
               where e.fixture_id = s.fixture_id
                 and e.participant_id = s.participant_id
                 and e.entry_kind in ('fixture_score', 'correction')
            )
       )
     )
   order by r.recorded_at, r.fixture_id
   limit greatest(p_limit, 0);
$$;

comment on function scoring.fixtures_with_unscored_predictions(timestamptz, timestamptz, integer) is
  'Fixtures whose result was recorded in [from, before) and that still hold '
  'a prediction with no fixture_scores row (0080), or a score the ledger '
  'does not match (0082). Read by the rescore sweep.';

insert into ops.applied_migrations (version)
values ('0082_rescore_unposted_ledger')
on conflict (version) do nothing;

commit;
