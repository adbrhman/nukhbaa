-- End-to-end test for migration 0112: six errors alert in an hour, the
-- seventh is kept without an alert, a new critical error still alerts, and
-- the hour makes room again. Rolled back at the end.
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
  i int;
  reason text;
  t0 timestamptz := '2026-10-15 10:00+00';
begin
  -- Six new errors in a fresh build: six alerts.
  for i in 1..6 loop
    select * into r from pg_temp.hit('00000000000b0' || lpad(i::text, 3, '0'), 'medium', 'rel0112', t0 + make_interval(mins => i));
    reason := ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0 + make_interval(mins => i));
    perform pg_temp.check(reason = 'new_in_release', 'new error ' || i || ' alerts');
  end loop;

  -- The seventh within the hour is kept and claimed by nobody.
  select * into r from pg_temp.hit('00000000000b0007', 'medium', 'rel0112', t0 + interval '7 minutes');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0 + interval '7 minutes') is null,
    'a seventh error in the hour does not alert');
  perform pg_temp.check(
    (select last_alert_at from ops.error_groups where id = r.group_id) is null,
    'the held-back error is not marked as alerted');

  -- A new critical error is never held back.
  select * into r from pg_temp.hit('00000000000b0c08', 'critical', 'rel0112', t0 + interval '8 minutes');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0 + interval '8 minutes') = 'new_critical',
    'a new critical error alerts over the budget');

  -- Over an hour after the six, there is room again.
  select * into r from pg_temp.hit('00000000000b0009', 'medium', 'rel0112', t0 + interval '70 minutes');
  perform pg_temp.check(
    ops.claim_error_alert(r.group_id, r.is_new, r.reopened, t0 + interval '70 minutes') = 'new_in_release',
    'the next hour has room again');
end $$;

select pg_temp.check(
  not has_function_privilege('anon', 'ops.claim_error_alert(bigint, boolean, boolean, timestamptz)', 'execute'),
  'anon cannot claim alerts');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0112_error_alert_budget'),
  'the migration records itself');

rollback;
