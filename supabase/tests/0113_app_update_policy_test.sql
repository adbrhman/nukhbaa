-- Test for migration 0113 and PostgresAppUpdatePolicyStore's statements
-- (batch 147): the one row starts with no minimum, an admin's write sets
-- it and is read back, null clears it, a second row and a minimum below 1
-- are refused. Keep the two bodies identical to the adapter's constants.
-- Rolled back at the end.
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

-- PostgresAppUpdatePolicyStore.readSql
create function pg_temp.read_min() returns integer
language sql as $q$
SELECT min_build_number AS min_build_number
FROM ops.app_update_policy
WHERE id
$q$;

-- PostgresAppUpdatePolicyStore.writeSql
create function pg_temp.write_min(p_min integer, p_by text) returns integer
language sql as $q$
INSERT INTO ops.app_update_policy (id, min_build_number, updated_by, updated_at)
VALUES (true, p_min::integer, p_by::uuid, now())
ON CONFLICT (id) DO UPDATE
SET min_build_number = excluded.min_build_number,
    updated_by       = excluded.updated_by,
    updated_at       = excluded.updated_at
RETURNING min_build_number AS min_build_number
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0147-4000-8000-000000000001', 'a147@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0147-4000-8000-000000000001', 'a147@t.io', 'Admin');

do $$
declare
  failed boolean;
begin
  perform pg_temp.check(
    (select count(*) from ops.app_update_policy) = 1, 'exactly one row');
  perform pg_temp.check(pg_temp.read_min() is null, 'no minimum at first');

  perform pg_temp.check(
    pg_temp.write_min(212, '00000000-0147-4000-8000-000000000001') = 212,
    'the write answers the stored minimum');
  perform pg_temp.check(pg_temp.read_min() = 212, 'and it reads back');
  perform pg_temp.check(
    (select updated_by::text from ops.app_update_policy)
      = '00000000-0147-4000-8000-000000000001',
    'who set it is kept');

  perform pg_temp.check(
    pg_temp.write_min(null, '00000000-0147-4000-8000-000000000001') is null,
    'null clears it');
  perform pg_temp.check(pg_temp.read_min() is null, 'nobody is asked again');

  failed := false;
  begin
    perform pg_temp.write_min(0, '00000000-0147-4000-8000-000000000001');
  exception when check_violation then
    failed := true;
  end;
  perform pg_temp.check(failed, 'a minimum below 1 is refused');

  failed := false;
  begin
    insert into ops.app_update_policy (id) values (false);
  exception when check_violation then
    failed := true;
  end;
  perform pg_temp.check(failed, 'a second row is refused');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0113_app_update_policy'),
    'the migration is recorded');
end $$;

rollback;
