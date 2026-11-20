-- End-to-end test for migration 0223: the owners' hand on the admins. The
-- adapter's statements: promote, revoke, end the sessions, keep the log.
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

-- What the stubs lack and admin.end_user_sessions touches (rolled back).
create table if not exists auth.refresh_tokens (user_id text);
create table if not exists auth.sessions (user_id uuid);

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0223-4000-8223-000000000001', 'rc1@t.io', now()),
  ('00000000-0223-4000-8223-000000000002', 'rc2@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0223-4000-8223-000000000001', 'rc1@t.io', 'المالك', 'admin'),
  ('00000000-0223-4000-8223-000000000002', 'rc2@t.io', 'خالد', 'user');

-- promote: from user only (PostgresAdminRoster.setRole).
create temp table promoted as
with up as (
  update identity.users
     set role = 'admin', updated_at = now()
   where id = '00000000-0223-4000-8223-000000000002'::uuid
     and role = 'user' and deleted_at is null
  returning id
) select count(*) as n from up;
select pg_temp.check((select n from promoted) = 1, 'a player is promoted');

create temp table again as
with up as (
  update identity.users
     set role = 'admin', updated_at = now()
   where id = '00000000-0223-4000-8223-000000000002'::uuid
     and role = 'user' and deleted_at is null
  returning id
) select count(*) as n from up;
select pg_temp.check((select n from again) = 0, 'an admin is not promoted twice');

-- end the sessions.
insert into auth.sessions (user_id)
values ('00000000-0223-4000-8223-000000000002');
insert into auth.refresh_tokens (user_id)
values ('00000000-0223-4000-8223-000000000002');
select pg_temp.check(
  admin.end_user_sessions('00000000-0223-4000-8223-000000000002') = 1,
  'one session ended');
select pg_temp.check(
  (select count(*) from auth.sessions
    where user_id = '00000000-0223-4000-8223-000000000002') = 0,
  'no session left');

-- the log.
insert into admin.role_changes (user_id, action, reason, changed_by,
                                sessions_ended)
values ('00000000-0223-4000-8223-000000000002', 'revoke', 'سوء استخدام',
        '00000000-0223-4000-8223-000000000001', 1);
select pg_temp.check(
  pg_temp.refusal($q$update admin.role_changes set reason = 'x'$q$)
  like '23514/%', 'the log is never changed');
select pg_temp.check(
  pg_temp.refusal($q$insert into admin.role_changes (user_id, action, reason)
    values ('00000000-0223-4000-8223-000000000002', 'delete', 'x')$q$)
  = '23514/role_changes_action_check', 'an unknown action is refused');
select pg_temp.check(
  pg_temp.refusal($q$insert into admin.role_changes (user_id, action, reason)
    values ('00000000-0223-4000-8223-000000000002', 'revoke', '  ')$q$)
  = '23514/role_changes_reason_check', 'a blank reason is refused');
select pg_temp.check(
  (select version from ops.applied_migrations
    where version = '0223_admin_role_changes') is not null,
  'the migration recorded itself');

rollback;
