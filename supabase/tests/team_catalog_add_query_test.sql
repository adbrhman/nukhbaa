-- End-to-end test of PostgresTeamCatalogWriter's three statements, run in
-- one transaction as the adapter runs them (parameters inlined as function
-- arguments; keep each body identical to the adapter's constant): an admin
-- adds a club to the catalog once, and a name whose spelling key
-- (competition.team_name_key, 0110) is already there answers the club on
-- file and writes nothing (script 91); a club whose matches never appear
-- is refused before anything else (migration 0174, script 92). Rolled
-- back at the end.
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

-- _lockSql
create function pg_temp.lock_name(p_name text) returns void
language sql as $q$
SELECT pg_advisory_xact_lock(
  hashtext('football_data.team:' || competition.team_name_key(p_name))
)
$q$;

-- _blockedSql
create function pg_temp.blocked(p_name text) returns boolean
language sql as $q$
SELECT football_data.is_blocked_club(p_name) AS blocked
$q$;

-- _existingSql
create function pg_temp.existing(p_name text)
returns table (id text, name text, short_name text, crest_url text, league_id text)
language sql as $q$
SELECT t.id::text AS id,
       t.name,
       t.short_name,
       t.crest_url,
       t.league_id::text AS league_id
FROM football_data.teams t
WHERE competition.team_name_key(t.name) = competition.team_name_key(p_name)
ORDER BY t.created_at, t.id
LIMIT 1
$q$;

-- _insertSql
create function pg_temp.insert_team(p_name text, p_league_id uuid)
returns table (id text, name text, short_name text, crest_url text, league_id text)
language sql as $q$
INSERT INTO football_data.teams (name, league_id)
VALUES (p_name, p_league_id)
RETURNING id::text AS id, name, short_name, crest_url, league_id::text AS league_id
$q$;

-- The adapter's transaction: lock, a blocked name refused (null id), the
-- club on file, else a new row.
create function pg_temp.add(p_name text, p_league_id uuid)
returns table (id text, name text, league_id text, existed boolean)
language plpgsql as $$
declare
  r record;
begin
  perform pg_temp.lock_name(p_name);
  if pg_temp.blocked(p_name) then
    return query select null::text, p_name, null::text, false;
    return;
  end if;
  select * into r from pg_temp.existing(p_name);
  if found then
    return query select r.id, r.name, r.league_id, true;
    return;
  end if;
  return query
    select i.id, i.name, i.league_id, false
      from pg_temp.insert_team(p_name, p_league_id) i;
end $$;

do $$
declare
  v_league uuid;
  v_first record;
  v_again record;
  v_seeded record;
  v_other record;
  v_blocked record;
  v_count bigint;
begin
  select l.id into v_league from football_data.leagues l order by l.name limit 1;
  perform pg_temp.check(v_league is not null, 'a seeded league to file under');

  select * into v_first from pg_temp.add('نادي التجربة 91', v_league);
  perform pg_temp.check(not v_first.existed, 'a new name is added');
  perform pg_temp.check(v_first.league_id = v_league::text,
    'under the league the admin picked');
  perform pg_temp.check(
    (select t.crest_url is null and t.short_name is null
       from football_data.teams t where t.id = v_first.id::uuid),
    'with no crest and no short name (initials until one is added)');

  select count(*) into v_count from football_data.teams;

  -- Spaces, hamza forms and taa marbuta fold into one key (0110).
  select * into v_again from pg_temp.add('  نادى  التجربه 91 ', null);
  perform pg_temp.check(v_again.existed, 'another spelling of one name is that club');
  perform pg_temp.check(v_again.id = v_first.id, 'answered by the club on file');
  perform pg_temp.check(
    (select count(*) from football_data.teams) = v_count,
    'and nothing is written');

  -- A club a seed migration put there (0104: غلطة سراي).
  select * into v_seeded from pg_temp.add('غلطه سراي', null);
  perform pg_temp.check(v_seeded.existed and v_seeded.name = 'غلطة سراي',
    'a seeded club typed with another taa is the seeded one');

  -- One letter apart is another name: the app shows it as a near name,
  -- the server does not refuse it.
  select * into v_other from pg_temp.add('نادي التجربة 92', null);
  perform pg_temp.check(not v_other.existed and v_other.league_id is null,
    'a different name is added, with no league when none is given');

  select count(*) into v_count from football_data.teams;
  select * into v_blocked from pg_temp.add('هبوعيل تل أبيب', null);
  perform pg_temp.check(v_blocked.id is null, 'a blocked club is refused (0174)');
  perform pg_temp.check(
    (select count(*) from football_data.teams) = v_count,
    'and nothing is written');
end $$;

rollback;
