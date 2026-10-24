-- End-to-end test for migration 0183: the audit trail takes the token of a
-- league an admin adds to the catalog (script 139). Rolled back at the end.
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
  admin_id uuid := '00000000-0000-4000-8183-000000000001';
  league_id uuid;
begin
  perform pg_temp.check(
    exists (
      select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'admin' and t.typname = 'audit_action'
         and e.enumlabel = 'league_added'),
    'admin.audit_action has league_added');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0183_league_added_audit'),
    '0183 records itself');

  insert into auth.users (id, email, email_confirmed_at)
  values (admin_id, 'adm183@t.io', now());
  insert into identity.users (id, email, display_name, role, created_at)
  values (admin_id, 'adm183@t.io', 'Admin 183', 'admin', now());

  insert into football_data.leagues (name, is_continental)
  values ('دوري التجربة 183', true)
  returning id into league_id;

  insert into admin.audit_log (id, actor_id, action, target_ref, reason)
  values (gen_random_uuid(), admin_id, 'league_added', league_id::text,
          'دوري التجربة 183');

  perform pg_temp.check(
    (select count(*) from admin.audit_log
      where action = 'league_added' and target_ref = league_id::text) = 1,
    'a league added is recorded in the audit trail by its id');
end $$;

rollback;
