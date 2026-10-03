-- End-to-end test for migration 0089: a critical new error alerts once and
-- not again within the hour, a spike past 20 an hour alerts, a fixed error
-- that comes back alerts, an ignored one never does, and the hour window
-- resets. Rolled back at the end.
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

create function pg_temp.hit(fp text, sev text, b text, at timestamptz)
returns table (group_id bigint, occurrences bigint, status text, severity text,
               users_affected integer, is_new boolean, reopened boolean)
language sql as $$
  select * from ops.record_error(
    fp, 'K7Q2', 'server', 'StateError', null, 'boom', null, null, null,
    sev, b, at, null, null, 'GET /x', null, null, null, null, null)
$$;

do $$
declare
  r record;
  reason text;
  i int;
  t0 timestamptz := '2026-10-03 10:00+00';
begin
  -- A new critical error: one alert, then silence for the hour.
  select * into r from pg_temp.hit('0000000000000c01', 'critical', 'rel0001', t0);
  reason := ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0);
  perform pg_temp.check(reason = 'new_critical', 'a new critical error alerts');

  select * into r from pg_temp.hit('0000000000000c01', 'critical', 'rel0001', t0 + interval '5 minutes');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, true, false, t0 + interval '5 minutes') is null,
    'the same error does not alert again within the hour');

  -- A spike: more than 20 in one hour alerts (the hour after the first alert).
  for i in 1..25 loop
    select * into r from pg_temp.hit('0000000000000c02', 'medium', 'old0001', t0 + make_interval(mins => i));
  end loop;
  perform pg_temp.check(
    (select hour_count from ops.error_groups where id = r.group_id) = 25,
    'the hour window counts every occurrence');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, false, false, t0 + interval '30 minutes') = 'hourly_spike',
    'more than 20 an hour alerts');

  -- The window resets an hour after it opened.
  select * into r from pg_temp.hit('0000000000000c02', 'medium', 'old0001', t0 + interval '2 hours');
  perform pg_temp.check(
    (select hour_count from ops.error_groups where id = r.group_id) = 1,
    'a new hour starts a new count');

  -- A fixed error back in a new build alerts as reopened.
  update ops.error_groups set status = 'fixed' where fingerprint = '0000000000000c01';
  select * into r from pg_temp.hit('0000000000000c01', 'critical', 'rel0002', t0 + interval '3 hours');
  perform pg_temp.check(r.reopened, 'the error reopened');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0 + interval '3 hours') = 'reopened',
    'a fixed error that comes back alerts');

  -- An ignored error never alerts.
  update ops.error_groups set status = 'ignored' where fingerprint = '0000000000000c01';
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, true, true, t0 + interval '9 hours') is null,
    'an ignored error never alerts');

  -- A new low error is not an alert; a medium one in a fresh build is.
  select * into r from pg_temp.hit('0000000000000c03', 'low', 'rel0003', now());
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, now()) is null,
    'a new low error does not alert');
  select * into r from pg_temp.hit('0000000000000c04', 'medium', 'rel0003', now());
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, now()) = 'new_in_release',
    'a new error in a fresh release alerts');
end $$;

select pg_temp.check(
  not has_function_privilege('anon', 'ops.claim_error_alert(bigint, boolean, boolean, timestamptz)', 'execute'),
  'anon cannot claim alerts');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0089_error_log_alerts'),
  'the migration records itself');

rollback;
