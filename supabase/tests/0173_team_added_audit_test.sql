-- End-to-end test for migration 0173: the audit trail takes the token of a
-- club an admin adds to the catalog (script 91). Rolled back at the end.
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
  admin_id uuid := '00000000-0000-4000-8173-000000000001';
  team_id uuid;
begin
  perform pg_temp.check(
    exists (
      select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
       join pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'admin' and t.typname = 'audit_action'
         and e.enumlabel = 'team_added'),
    'admin.audit_action has team_added');

  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0173_team_added_audit'),
    '0173 records itself');

  insert into auth.users (id, email, email_confirmed_at)
  values (admin_id, 'adm173@t.io', now());
  insert into identity.users (id, email, display_name, role, created_at)
  values (admin_id, 'adm173@t.io', 'Admin 173', 'admin', now());

  insert into football_data.teams (name) values ('نادي التجربة 173')
  returning id into team_id;

  insert into admin.audit_log (id, actor_id, action, target_ref, reason)
  values (gen_random_uuid(), admin_id, 'team_added', team_id::text,
          'نادي التجربة 173');

  perform pg_temp.check(
    (select count(*) from admin.audit_log
      where action = 'team_added' and target_ref = team_id::text) = 1,
    'a club added is recorded in the audit trail by its id');
end $$;

rollback;
