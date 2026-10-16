-- End-to-end test of PostgresProviderSyncStore._pendingSql (parameters
-- inlined as function arguments; keep the body identical to the adapter's
-- constant): the fixtures a provider is still asked about for a result are
-- its own, in the window, without a result, and shown. A hidden fixture
-- (0098) was usually postponed or called off and is never scored, so it is
-- not asked about and spends none of the provider's daily requests
-- (script 90). No migration: the query reads 0004, 0012, 0027, 0098 and
-- the identity map.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- PostgresProviderSyncStore._pendingSql
create function pg_temp.pending(
  p_source text, p_from timestamptz, p_before timestamptz)
returns table (fixture_id text, external_id text, kickoff_at timestamptz,
               league_id text, game text)
language sql as $q$
SELECT m.canonical_id::text AS fixture_id,
       m.external_id,
       s.kickoff_at,
       s.league_id::text AS league_id,
       s.home_team || ' - ' || s.away_team AS game
FROM football_data.external_identity_map m
JOIN competition.fixture_schedules s
  ON s.fixture_id = m.canonical_id
LEFT JOIN scoring.fixture_results r
  ON r.fixture_id = m.canonical_id
WHERE m.external_source = p_source
  AND m.canonical_table = 'fixture'
  AND r.fixture_id IS NULL
  AND s.hidden_at IS NULL
  AND s.kickoff_at >= p_from
  AND s.kickoff_at < p_before
ORDER BY s.kickoff_at
LIMIT 200
$q$;

-- f1 waits; f2 is hidden; f3 has its result; f4 belongs to another
-- provider; f5 kicked off before the window.
insert into competition.fixture_schedules (fixture_id, home_team, away_team, kickoff_at) values
  ('c9000000-0000-4000-8000-0000000000f1', 'A', 'B', '2099-06-01 18:00Z'),
  ('c9000000-0000-4000-8000-0000000000f2', 'C', 'D', '2099-06-01 18:30Z'),
  ('c9000000-0000-4000-8000-0000000000f3', 'E', 'F', '2099-06-01 19:00Z'),
  ('c9000000-0000-4000-8000-0000000000f4', 'G', 'H', '2099-06-01 19:30Z'),
  ('c9000000-0000-4000-8000-0000000000f5', 'I', 'J', '2099-05-30 18:00Z');
update competition.fixture_schedules
   set hidden_at = now()
 where fixture_id = 'c9000000-0000-4000-8000-0000000000f2';
insert into football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id) values
  ('highlightly',   'm1', 'fixture', 'c9000000-0000-4000-8000-0000000000f1'),
  ('highlightly',   'm2', 'fixture', 'c9000000-0000-4000-8000-0000000000f2'),
  ('highlightly',   'm3', 'fixture', 'c9000000-0000-4000-8000-0000000000f3'),
  ('football-data', 'm4', 'fixture', 'c9000000-0000-4000-8000-0000000000f4'),
  ('highlightly',   'm5', 'fixture', 'c9000000-0000-4000-8000-0000000000f5');
insert into scoring.fixture_results (fixture_id, home_goals, away_goals, recorded_at) values
  ('c9000000-0000-4000-8000-0000000000f3', 2, 1, now());

do $$
declare
  v_ids text[];
begin
  select array_agg(external_id order by kickoff_at) into v_ids
    from pg_temp.pending('highlightly', '2099-05-31 21:00Z', '2099-06-02 00:00Z');

  perform pg_temp.check(v_ids = array['m1'],
    'only the shown, unresulted fixture of this provider in the window waits');

  perform pg_temp.check(
    (select game from pg_temp.pending('highlightly', '2099-05-31 21:00Z', '2099-06-02 00:00Z')) = 'A - B',
    'the match is named for the admins');

  update competition.fixture_schedules
     set hidden_at = null
   where fixture_id = 'c9000000-0000-4000-8000-0000000000f2';
  select array_agg(external_id order by kickoff_at) into v_ids
    from pg_temp.pending('highlightly', '2099-05-31 21:00Z', '2099-06-02 00:00Z');
  perform pg_temp.check(v_ids = array['m1', 'm2'],
    'shown again, the fixture is asked about again');
end $$;

rollback;
