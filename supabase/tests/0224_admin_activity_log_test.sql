-- End-to-end test for migration 0224: the admins' activity log. The row the
-- server appends (PostgresAdminActivityLog) is kept; only writes answered
-- below 400; never changed or deleted; the owners' read names the admin
-- and the target. Rolled back at the end.
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

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0224-4000-8224-000000000001', 'aa1@t.io', now()),
  ('00000000-0224-4000-8224-000000000002', 'pp1@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0224-4000-8224-000000000001', 'aa1@t.io', 'Admin One', 'admin'),
  ('00000000-0224-4000-8224-000000000002', 'pp1@t.io', 'Player Two', 'user');

-- The adapter's own statement.
insert into admin.admin_activity_log (actor_id, method, path, status)
values ('00000000-0224-4000-8224-000000000001', 'POST',
        '/admin/users/00000000-0224-4000-8224-000000000002/display-name', 200);

select pg_temp.check(
  (select count(*) = 1 and min(occurred_at) is not null
     from admin.admin_activity_log
    where actor_id = '00000000-0224-4000-8224-000000000001'),
  'an admin change is kept with its time');

-- The owners' read (PostgresAdminActivityLog.latest), as the server runs it.
select pg_temp.check(
  (select actor_name = 'Admin One' and target = 'Player Two' and result is null
     from (SELECT l.id,
       coalesce(a.display_name, '') AS actor_name,
       l.method,
       l.path,
       l.occurred_at,
       coalesce(u.display_name, fs.home_team || ' × ' || fs.away_team) AS target,
       CASE WHEN fr.fixture_id IS NULL THEN NULL
            ELSE fr.home_goals::text || '-' || fr.away_goals::text END AS result
FROM admin.admin_activity_log l
JOIN identity.users a ON a.id = l.actor_id
LEFT JOIN LATERAL (
  SELECT (regexp_match(
    l.path,
    '.*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
  ))[1]::uuid AS id
) t ON true
LEFT JOIN identity.users u ON u.id = t.id
LEFT JOIN competition.fixture_schedules fs ON fs.fixture_id = t.id
LEFT JOIN scoring.fixture_results fr ON fr.fixture_id = t.id
ORDER BY l.occurred_at DESC, l.id DESC
LIMIT 10
) r
    limit 1),
  'the read names the admin and the player he changed');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.admin_activity_log (actor_id, method, path, status)
    values ('00000000-0224-4000-8224-000000000001', 'GET', '/admin/users', 200)$q$)
    = '23514/admin_activity_log_method_check',
  'a read is not kept');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.admin_activity_log (actor_id, method, path, status)
    values ('00000000-0224-4000-8224-000000000001', 'PUT', '/fixtures/x/result', 409)$q$)
    = '23514/admin_activity_log_status_check',
  'a refused request is not kept');

select pg_temp.check(
  pg_temp.refusal($q$update admin.admin_activity_log set status = 201$q$) like '23514/%',
  'a kept row is never changed');

select pg_temp.check(
  pg_temp.refusal($q$delete from admin.admin_activity_log$q$) like '23514/%',
  'a kept row is never deleted');

select pg_temp.check(
  pg_temp.refusal($q$insert into admin.admin_activity_log (actor_id, method, path, status)
    values ('00000000-0224-4000-8224-0000000000ff', 'POST', '/admin/teams', 200)$q$)
    = '23503/admin_activity_log_actor_id_fkey',
  'an actor is an existing account');

rollback;
