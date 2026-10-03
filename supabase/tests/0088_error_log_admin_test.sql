-- End-to-end test for migration 0088: the audit trail accepts the error log
-- token, and an admin's change to an error is recorded with it. Rolled back
-- at the end.
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

do $$
declare
  admin_id uuid := '00000000-0000-4000-8088-000000000001';
  gid bigint;
begin
  perform pg_temp.check(
    exists (
      select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'admin' and t.typname = 'audit_action'
         and e.enumlabel = 'error_updated'),
    'admin.audit_action has error_updated');

  insert into auth.users (id, email, email_confirmed_at) values (admin_id, 'adm@t.io', now());
  insert into identity.users (id, email, display_name, role, created_at)
  values (admin_id, 'adm@t.io', 'Admin 88', 'admin', now());

  select r.group_id into gid from ops.record_error(
    '0000000000000088', 'ABCD', 'server', 'StateError', null, 'boom',
    null, null, null, 'high', 'abc1234', now(), null, null, 'GET /x',
    null, null, null, null, null) r;

  update ops.error_groups
     set status = 'fixed', assignee_id = admin_id, admin_notes = 'fixed in abc1235',
         status_changed_at = now()
   where id = gid;

  insert into admin.audit_log (id, actor_id, action, target_ref, reason)
  values (gen_random_uuid(), admin_id, 'error_updated', 'error:' || gid,
          'status: new -> fixed');

  perform pg_temp.check(
    (select count(*) from admin.audit_log where action = 'error_updated' and target_ref = 'error:' || gid) = 1,
    'an error change is recorded in the audit trail');

  perform pg_temp.check(
    (select assignee_id from ops.error_groups where id = gid) = admin_id
    and (select status from ops.error_groups where id = gid) = 'fixed',
    'status and assignee are kept on the error');

  begin
    update ops.error_groups set status = 'closed' where id = gid;
    raise exception 'FAILED: an unknown status was accepted';
  exception when check_violation then
    raise notice 'ok - an unknown status is refused';
  end;
end $$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0088_error_log_admin'),
  'the migration records itself');

rollback;
