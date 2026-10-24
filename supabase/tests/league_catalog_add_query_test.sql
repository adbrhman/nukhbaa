-- End-to-end test of PostgresLeagueCatalogWriter's three statements, run in
-- one transaction as the adapter runs them (parameters inlined as function
-- arguments; keep each body identical to the adapter's constant): an admin
-- adds a league to the catalog once, continental (its clubs come from the
-- whole catalog, as 0104's derbies), and a name whose spelling key
-- (competition.team_name_key, 0110) is already there answers the league
-- on file and writes nothing (script 139). Rolled back at the end.
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
  hashtext('football_data.league:' || competition.team_name_key(p_name))
)
$q$;

-- _existingSql
create function pg_temp.existing(p_name text)
returns table (id text, name text, short_name text, logo_url text, is_continental boolean)
language sql as $q$
SELECT l.id::text AS id,
       l.name,
       l.short_name,
       l.logo_url,
       l.is_continental
FROM football_data.leagues l
WHERE competition.team_name_key(l.name) = competition.team_name_key(p_name)
ORDER BY l.created_at, l.id
LIMIT 1
$q$;

-- _insertSql
create function pg_temp.insert_league(p_name text)
returns table (id text, name text, short_name text, logo_url text, is_continental boolean)
language sql as $q$
INSERT INTO football_data.leagues (name, is_continental)
VALUES (p_name, true)
RETURNING id::text AS id, name, short_name, logo_url, is_continental
$q$;

-- The adapter's transaction: lock, the league on file, else a new row.
create function pg_temp.add(p_name text)
returns table (id text, name text, is_continental boolean, existed boolean)
language plpgsql as $$
declare
  r record;
begin
  perform pg_temp.lock_name(p_name);
  select * into r from pg_temp.existing(p_name);
  if found then
    return query select r.id, r.name, r.is_continental, true;
    return;
  end if;
  return query
    select i.id, i.name, i.is_continental, false
      from pg_temp.insert_league(p_name) i;
end $$;

do $$
declare
  v_first record;
  v_again record;
  v_seeded record;
  v_count bigint;
begin
  select * into v_first from pg_temp.add('كأس التجربة 183');
  perform pg_temp.check(not v_first.existed, 'a new name is added');
  perform pg_temp.check(v_first.is_continental,
    'continental: its clubs come from the whole catalog');
  perform pg_temp.check(
    (select l.logo_url is null and l.short_name is null
       from football_data.leagues l where l.id = v_first.id::uuid),
    'with no logo and no short name');

  select count(*) into v_count from football_data.leagues;

  -- Spaces, hamza forms and taa marbuta fold into one key (0110).
  select * into v_again from pg_temp.add('  كاس  التجربه 183 ');
  perform pg_temp.check(v_again.existed, 'another spelling of one name is that league');
  perform pg_temp.check(v_again.id = v_first.id, 'answered by the league on file');
  perform pg_temp.check(
    (select count(*) from football_data.leagues) = v_count,
    'and nothing is written');

  -- A league a seed migration put there (0104).
  select * into v_seeded from pg_temp.add('ديربيات كبرى');
  perform pg_temp.check(v_seeded.existed and v_seeded.name = 'ديربيات كبرى',
    'a seeded league is the seeded one');
  perform pg_temp.check(
    (select count(*) from football_data.leagues) = v_count,
    'and nothing is written for it either');
end $$;

rollback;
