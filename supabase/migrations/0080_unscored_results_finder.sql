-- ============================================================================
-- Migration 0080: find recorded results whose scoring was left unfinished
--
-- ADDITIVE ONLY. One read-only function; no row is touched.
--
-- Why: recording a result and scoring it are two separate writes. When the
-- scoring write fails after the result was stored (a statement timeout, a
-- lost connection, a restart in between), the result stands and nothing asks
-- again -- the provider sync only looks at fixtures WITHOUT a result -- so the
-- monthly board, which sums scoring.fixture_scores, silently shows no points
-- for that match. The server's rescore sweep (RescoreUnscoredResults) calls
-- this function every quarter hour and scores whatever it returns.
--
-- A fixture qualifies when its result was recorded inside the window and at
-- least one prediction for it has no fixture_scores row. Oldest result first,
-- so a backlog drains in order.
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
     and exists (
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
   order by r.recorded_at, r.fixture_id
   limit greatest(p_limit, 0);
$$;

comment on function scoring.fixtures_with_unscored_predictions(timestamptz, timestamptz, integer) is
  'Fixtures whose result was recorded in [from, before) and that still hold a '
  'prediction with no fixture_scores row (0080). Read by the rescore sweep.';

commit;
