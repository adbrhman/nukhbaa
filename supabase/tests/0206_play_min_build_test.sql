-- Test for migration 0206 and PostgresPlayUpdatePolicyStore's statements
-- (script 253): the Play minimum starts unset, an admin's write sets it and
-- is read back without touching the APK minimum, null clears it, and a
-- minimum below 1 is refused. Keep the two bodies identical to the
-- adapter's constants. Rolled back at the end.
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

-- PostgresPlayUpdatePolicyStore.readSql
create function pg_temp.read_play_min() returns integer
language sql as $q$
SELECT min_play_build_number AS min_build_number
FROM ops.app_update_policy
WHERE id
$q$;

-- PostgresPlayUpdatePolicyStore.writeSql
create function pg_temp.write_play_min(p_min integer, p_by text)
returns integer
language sql as $q$
INSERT INTO ops.app_update_policy (id, min_play_build_number, updated_by, updated_at)
VALUES (true, p_min::integer, p_by::uuid, now())
ON CONFLICT (id) DO UPDATE
SET min_play_build_number = excluded.min_play_build_number,
    updated_by            = excluded.updated_by,
    updated_at            = excluded.updated_at
RETURNING min_play_build_number AS min_build_number
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0253-4000-8000-000000000001', 'a253@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0253-4000-8000-000000000001', 'a253@t.io', 'Admin');

do $$
declare
  failed boolean;
begin
  update ops.app_update_policy set min_build_number = 900 where id;

  perform pg_temp.check(
    pg_temp.read_play_min() is null, 'no Play minimum at first');

  perform pg_temp.check(
    pg_temp.write_play_min(845, '00000000-0253-4000-8000-000000000001') = 845,
    'the write answers the stored Play minimum');
  perform pg_temp.check(pg_temp.read_play_min() = 845, 'and it reads back');
  perform pg_temp.check(
    (select min_build_number from ops.app_update_policy) = 900,
    'the APK minimum is left as it was');
  perform pg_temp.check(
    (select count(*) from ops.app_update_policy) = 1, 'still one row');

  perform pg_temp.check(
    pg_temp.write_play_min(null, '00000000-0253-4000-8000-000000000001')
      is null,
    'null clears it');
  perform pg_temp.check(
    pg_temp.read_play_min() is null, 'no Play player is asked again');

  failed := false;
  begin
    perform pg_temp.write_play_min(0, '00000000-0253-4000-8000-000000000001');
  exception when check_violation then
    failed := true;
  end;
  perform pg_temp.check(failed, 'a Play minimum below 1 is refused');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0206_play_min_build'),
    'the migration is recorded');
end $$;

rollback;
