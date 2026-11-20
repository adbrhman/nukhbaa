-- End-to-end test for migration 0221: the predictions and chat switches.
-- Both rows are there and on; the adapter's upsert turns one off; an
-- unknown key is still refused. Rolled back at the end.
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
  (select count(*) from ops.owner_switches
    where switch_key in ('predictions', 'chat') and is_on) = 2,
  'the two new switches are there, on');

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0221-4000-8221-000000000001', 'sw1@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0221-4000-8221-000000000001', 'sw1@t.io', 'SW', 'admin');

-- The adapter's upsert (PostgresOwnerSwitches.set).
insert into ops.owner_switches (switch_key, is_on, reason, changed_by, changed_at)
values ('predictions', false, 'خطأ في النقاط',
        '00000000-0221-4000-8221-000000000001'::uuid, now())
on conflict (switch_key) do update
set is_on = excluded.is_on,
    reason = excluded.reason,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at;

select pg_temp.check(
  (select not is_on from ops.owner_switches where switch_key = 'predictions'),
  'predictions turned off');
select pg_temp.check(
  (select is_on from ops.owner_switches where switch_key = 'chat'),
  'chat untouched');
select pg_temp.check(
  pg_temp.refusal($q$insert into ops.owner_switches (switch_key) values
    ('groups')$q$) = '23514/owner_switches_key_check',
  'an unknown switch is refused');
select pg_temp.check(
  (select version from ops.applied_migrations
    where version = '0221_owner_switches_play') is not null,
  'the migration recorded itself');

rollback;
