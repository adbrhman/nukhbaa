-- End-to-end test for migration 0192 (script 189): the statements
-- PostgresLeagueStandingsStore runs keep one table per provider league; a
-- new read replaces the one before; a read takes only the rows of the latest
-- read time, so a save cut off between its two statements never mixes two
-- tables; a place below 1 and a blank key are refused.
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

-- PostgresLeagueStandingsStore._saveSql with its parameters inlined.
create function pg_temp.save(
  p_source text, p_league text, p_at timestamptz, p_teams text[],
  p_places int[], p_points text[], p_played text[]
) returns void
language sql as $$
INSERT INTO football_data.league_standings
  (source, league_ref, team_external_id, position, points, played,
   fetched_at)
SELECT p_source, p_league, r.team, r.place,
       nullif(r.points, '')::integer, nullif(r.played, '')::integer,
       p_at
FROM unnest(p_teams, p_places, p_points, p_played)
  AS r(team, place, points, played)
ON CONFLICT (source, league_ref, team_external_id) DO UPDATE
SET position = EXCLUDED.position,
    points = EXCLUDED.points,
    played = EXCLUDED.played,
    fetched_at = EXCLUDED.fetched_at
$$;

-- PostgresLeagueStandingsStore._pruneSql.
create function pg_temp.prune(p_source text, p_league text, p_at timestamptz)
returns void
language sql as $$
DELETE FROM football_data.league_standings
WHERE source = p_source
  AND league_ref = p_league
  AND fetched_at < p_at
$$;

-- PostgresLeagueStandingsStore._latestSql.
create function pg_temp.latest(p_source text, p_league text)
returns table (team text, place integer, points integer, fetched timestamptz)
language sql as $$
SELECT s.team_external_id, s.position, s.points, s.fetched_at
FROM football_data.league_standings s
WHERE s.source = p_source
  AND s.league_ref = p_league
  AND s.fetched_at = (SELECT max(m.fetched_at)
                        FROM football_data.league_standings m
                       WHERE m.source = p_source
                         AND m.league_ref = p_league)
ORDER BY s.position, s.team_external_id
$$;

do $$
declare
  t1 timestamptz := '2030-01-07 21:05+00';
  t2 timestamptz := '2030-01-08 21:05+00';
  t3 timestamptz := '2030-01-09 21:05+00';
  refused boolean;
begin
  perform pg_temp.save('highlightly', '262041', t1,
    array['hil', 'nas'], array[1, 2], array['25', ''], array['9', '9']);
  perform pg_temp.prune('highlightly', '262041', t1);
  perform pg_temp.check(
    (select array_agg(team order by place) from pg_temp.latest('highlightly', '262041'))
      = array['hil', 'nas'],
    'a table is kept leader first');
  perform pg_temp.check(
    (select points from pg_temp.latest('highlightly', '262041') where team = 'nas') is null,
    'points the provider did not send are null');

  -- Another league of the same provider is apart.
  perform pg_temp.save('football-data', 'PD', t1,
    array['86'], array[1], array[''], array['']);

  perform pg_temp.save('highlightly', '262041', t2,
    array['nas', 'itt'], array[1, 2], array['28', '26'], array['10', '10']);
  perform pg_temp.prune('highlightly', '262041', t2);
  perform pg_temp.check(
    (select array_agg(team order by place) from pg_temp.latest('highlightly', '262041'))
      = array['nas', 'itt'],
    'a new read replaces the table before');
  perform pg_temp.check(
    (select count(*) from football_data.league_standings
      where source = 'highlightly' and league_ref = '262041') = 2,
    'the club gone from the table is removed');
  perform pg_temp.check(
    (select count(*) from pg_temp.latest('football-data', 'PD')) = 1,
    'another league is untouched');

  -- A save cut off before its prune: only the latest read is read back.
  perform pg_temp.save('highlightly', '262041', t3,
    array['tah'], array[1], array[''], array['']);
  perform pg_temp.check(
    (select array_agg(team) from pg_temp.latest('highlightly', '262041'))
      = array['tah'],
    'two reads are never mixed');

  begin
    perform pg_temp.save('highlightly', '3337', t1,
      array['x'], array[0], array[''], array['']);
    refused := false;
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'a place below 1 is refused');

  begin
    perform pg_temp.save('highlightly', ' ', t1,
      array['x'], array[1], array[''], array['']);
    refused := false;
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'a blank league is refused');

  perform pg_temp.check(
    (select relrowsecurity from pg_class
      where oid = 'football_data.league_standings'::regclass),
    'row level security is on');
end $$;

rollback;
