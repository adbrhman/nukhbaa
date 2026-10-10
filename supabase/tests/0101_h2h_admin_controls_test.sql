-- End-to-end test for migration 0101: one settings row with its ranges and
-- no way to delete it; exclusions that can be added and lifted; the admin
-- log append-only and limited to known actions. Rolled back at the end.
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
  ('00000000-0101-4000-8999-000000000001', 'admin101@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0101-4000-8999-000000000001', 'admin101@t.io', 'Admin');

do $$
begin
  perform pg_temp.check(
    (select count(*) = 1 and bool_and(auto_approve)
            and bool_and(auto_approve_lead_hours = 24)
            and bool_and(min_active_days = 5)
       from gamification.h2h_settings),
    'one settings row, with the rules of 0100 as its defaults');
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_settings (id) values (false)$q$)
      = '23514/h2h_settings_single_row',
    'a second settings row is refused');
  perform pg_temp.check(
    pg_temp.refusal($q$update gamification.h2h_settings set auto_approve_lead_hours = 48$q$)
      = '23514/h2h_settings_lead_range',
    'the lead cannot go past the 24 hours the system looks ahead');
  perform pg_temp.check(
    pg_temp.refusal($q$update gamification.h2h_settings set min_active_days = 0$q$)
      = '23514/h2h_settings_active_days_range',
    'the active days stay between 1 and 28');
  perform pg_temp.check(
    pg_temp.refusal($q$delete from gamification.h2h_settings$q$) like '23514/%',
    'the settings row cannot be deleted');
end $$;

update gamification.h2h_settings
   set auto_approve = false, auto_approve_lead_hours = 6, min_active_days = 3,
       updated_by = '00000000-0101-4000-8999-000000000001', updated_at = now();

insert into gamification.h2h_day_exclusions (day, excluded_by) values
  ('2099-11-05', '00000000-0101-4000-8999-000000000001');
do $$
begin
  perform pg_temp.check(
    (select not auto_approve and auto_approve_lead_hours = 6
            and min_active_days = 3 from gamification.h2h_settings),
    'the settings change in place');
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_day_exclusions (day) values ('2099-11-05')$q$)
      = '23505/h2h_day_exclusions_pkey',
    'a day is excluded once');
end $$;
delete from gamification.h2h_day_exclusions where day = '2099-11-05';
do $$
begin
  perform pg_temp.check(
    not exists (select 1 from gamification.h2h_day_exclusions),
    'an exclusion is lifted by deleting it');
end $$;

insert into gamification.h2h_admin_actions (id, action, actor, detail) values
  ('00000000-0101-4000-8999-0000000000a1', 'day_excluded',
   '00000000-0101-4000-8999-000000000001', '{"day":"2099-11-05"}');
do $$
begin
  perform pg_temp.check(
    pg_temp.refusal($q$update gamification.h2h_admin_actions set action = 'jobs_run'$q$) like '23514/%',
    'the admin log refuses UPDATE');
  perform pg_temp.check(
    pg_temp.refusal($q$delete from gamification.h2h_admin_actions$q$) like '23514/%',
    'the admin log refuses DELETE');
  perform pg_temp.check(
    pg_temp.refusal($q$insert into gamification.h2h_admin_actions (id, action) values (gen_random_uuid(), 'points_changed')$q$)
      = '23514/h2h_admin_actions_action_known',
    'only known actions are logged');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations where version = '0101_h2h_admin_controls'),
    'the migration records itself');
end $$;

rollback;
