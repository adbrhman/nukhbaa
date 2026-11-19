-- End-to-end test for migration 0219: the owners' audit log. The row the
-- server appends (PostgresOwnerAuditLog) is kept; only writes under /owner
-- answered below 400; never changed or deleted. Rolled back at the end.
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

-- The SQLSTATE and constraint name [stmt] raises, or 'none'.
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

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0219-4000-8219-000000000001', 'oa1@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0219-4000-8219-000000000001', 'oa1@t.io', 'OA One', 'admin');

-- The adapter's own statement.
insert into admin.owner_audit_log (actor_id, method, path, status)
values ('00000000-0219-4000-8219-000000000001', 'POST',
        '/owner/hidden-accounts/00000000-0219-4000-8219-0000000000aa', 200);

select pg_temp.check(
  (select count(*) = 1 and min(occurred_at) is not null
     from admin.owner_audit_log
    where actor_id = '00000000-0219-4000-8219-000000000001'),
  'an owner change is kept with its time');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.owner_audit_log (actor_id, method, path, status)
    values ('00000000-0219-4000-8219-000000000001', 'GET', '/owner/crests', 200)$q$)
    = '23514/owner_audit_log_method_check',
  'a read is not kept');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.owner_audit_log (actor_id, method, path, status)
    values ('00000000-0219-4000-8219-000000000001', 'POST', '/admin/users', 200)$q$)
    = '23514/owner_audit_log_path_check',
  'only paths under /owner are kept');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.owner_audit_log (actor_id, method, path, status)
    values ('00000000-0219-4000-8219-000000000001', 'PUT', '/owner/crests', 409)$q$)
    = '23514/owner_audit_log_status_check',
  'a refused request is not kept');

select pg_temp.check(
  pg_temp.refusal($q$update admin.owner_audit_log set status = 201$q$) like '23514/%',
  'a kept row is never changed');

select pg_temp.check(
  pg_temp.refusal($q$delete from admin.owner_audit_log$q$) like '23514/%',
  'a kept row is never deleted');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.owner_audit_log (actor_id, method, path, status)
    values ('00000000-0219-4000-8219-0000000000ff', 'POST', '/owner/crests', 200)$q$)
    = '23503/owner_audit_log_actor_id_fkey',
  'an actor is an existing account');

rollback;
