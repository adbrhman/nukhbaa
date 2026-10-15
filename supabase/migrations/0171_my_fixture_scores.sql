-- ============================================================================
-- Migration 0171: a player's own points in one read (script 75, 2026-10-15)
--
-- ADDITIVE ONLY. One read-only function; no row is touched. Safe to re-run.
--
-- Why: the app asked GET /seasons/{id}/fixtures/{fixtureId}/scores once per
-- finished match card and once per row of "my predictions" -- again every
-- 2 minutes while a score was pending -- for every player at once when a
-- match ended. Each request ran four queries and returned every
-- participant's score, all to show one line: my grade, my points and the
-- final score. On the night of 2026-10-14/15 that route timed out 389
-- times. GET /me/fixture-scores now reads them all with one call of this
-- function.
--
-- One row per prediction of the user that has a score or a recorded result;
-- a result not scored yet comes with a null grade and null points, and a
-- prediction with neither is left out. Every season the user joined: the
-- app matches a row to its card by (participant_id, fixture_id). Only that
-- user's rows -- the server passes the verified caller's id.
--
-- Numbered in the web speed and quality series (0170-0179, scripts 71 on).
-- ============================================================================

begin;

create or replace function scoring.my_fixture_scores(p_user_id uuid)
returns table (
  participant_id    uuid,
  fixture_id        uuid,
  grade             text,
  points            integer,
  result_home_goals integer,
  result_away_goals integer
)
language sql
stable
set search_path = ''
as $$
  select fp.participant_id,
         fp.fixture_id,
         s.grade,
         s.points,
         r.home_goals,
         r.away_goals
    from competition.participants pa
    join prediction.fixture_predictions fp
      on fp.participant_id = pa.id
    left join scoring.fixture_scores s
      on s.fixture_id = fp.fixture_id
     and s.participant_id = fp.participant_id
    left join scoring.fixture_results r
      on r.fixture_id = fp.fixture_id
   where pa.user_id = p_user_id
     and (s.fixture_id is not null or r.fixture_id is not null)
   order by fp.fixture_id, fp.participant_id;
$$;

comment on function scoring.my_fixture_scores(uuid) is
  'The user''s own predictions that have a score or a recorded result: '
  'grade and points (null until scored) and the final score (null until '
  'recorded), one row per (participant, fixture) (0171). Read by '
  'GET /me/fixture-scores.';

revoke all on function scoring.my_fixture_scores(uuid)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0171_my_fixture_scores')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0171_my_fixture_scores';                        -- 1 row
-- select count(*) from scoring.my_fixture_scores(
--   '00000000-0000-0000-0000-000000000000');                        -- 0
