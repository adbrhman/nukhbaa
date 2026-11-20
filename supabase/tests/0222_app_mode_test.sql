-- End-to-end test for migration 0222: the app's mode. One row, normal;
-- the adapter's upsert; the checks; app_mode_normal.sql. Rolled back at
-- the end.
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

create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_state text;
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate,
                          v_constraint = constraint_name;
  return v_state || '/' || coalesce(v_constraint, '');
end $$;

select pg_temp.check(
  (select count(*) = 1 and bool_and(mode = 'normal') from ops.app_mode),
  'one row, normal');

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0222-4000-8222-000000000001', 'am1@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0222-4000-8222-000000000001', 'am1@t.io', 'AM', 'admin');

-- The adapter's statement (PostgresAppModeStore.set).
insert into ops.app_mode (id, mode, reason, changed_by, changed_at)
values (true, 'read_only', 'خطأ في النقاط',
        '00000000-0222-4000-8222-000000000001'::uuid, now())
on conflict (id) do update
set mode = excluded.mode,
    reason = excluded.reason,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at;

select pg_temp.check(
  (select mode from ops.app_mode) = 'read_only', 'read only, by the adapter');
select pg_temp.check(
  pg_temp.refusal($q$update ops.app_mode set mode = 'off'$q$)
  = '23514/app_mode_mode_check', 'an unknown mode is refused');
select pg_temp.check(
  pg_temp.refusal($q$insert into ops.app_mode (id) values (false)$q$)
  = '23514/app_mode_single_row', 'a second row is refused');

\i supabase/queries/app_mode_normal.sql
select pg_temp.check(
  (select mode = 'normal' and changed_by is null from ops.app_mode),
  'app_mode_normal.sql brings it back');
select pg_temp.check(
  (select version from ops.applied_migrations
    where version = '0222_app_mode') is not null,
  'the migration recorded itself');

rollback;
