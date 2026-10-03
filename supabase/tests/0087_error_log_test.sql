-- End-to-end test for migration 0087: one error reported 100 times is one
-- row counting 100 with 5 samples (the newest), distinct players are
-- counted once, a fixed error comes back as new only in a build that never
-- had it, and malformed input is refused. Rolled back at the end.
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

create function pg_temp.mk_user(n int) returns uuid
language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8087-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, 'e' || n || '@t.io', now());
  insert into identity.users (id, email, display_name, created_at)
  values (v, 'e' || n || '@t.io', 'Err ' || n, now());
  return v;
end $$;

-- One occurrence of the error with fingerprint fp, from build b, by user u.
create function pg_temp.hit(fp text, b text, u uuid, req text, at timestamptz)
returns table (group_id bigint, occurrences bigint, status text, severity text,
               users_affected integer, is_new boolean, reopened boolean)
language sql as $$
  select * from ops.record_error(
    fp, 'K7Q2', 'server', 'StateError', 'server.unexpected',
    'Bad state: no element', 'routes/me/index.dart', 12, 'onRequest',
    'high', b, at, u, req, 'GET /me', null, null, null,
    '#0 onRequest (routes/me/index.dart)', '{"query": {"page": "2"}}'::jsonb)
$$;

do $$
declare
  a uuid := pg_temp.mk_user(1);
  b uuid := pg_temp.mk_user(2);
  r record;
  i int;
  first_id bigint;
begin
  select * into r from pg_temp.hit('00000000000000aa', 'abc1234', a, 'req-00000001', '2026-10-03 10:00+00');
  first_id := r.group_id;
  perform pg_temp.check(r.is_new and r.occurrences = 1 and r.status = 'new',
    'the first occurrence opens a new error');

  select * into r from pg_temp.hit('00000000000000aa', 'abc1234', a, 'req-00000002', '2026-10-03 10:01+00');
  perform pg_temp.check(not r.is_new and r.group_id = first_id and r.occurrences = 2,
    'two identical errors are one row counting 2');

  for i in 3..100 loop
    select * into r from pg_temp.hit('00000000000000aa', 'abc1234',
      case when i % 2 = 0 then a else null end,
      'req-' || lpad(i::text, 8, '0'), '2026-10-03 10:00+00'::timestamptz + make_interval(mins => i));
  end loop;

  perform pg_temp.check(
    (select count(*) from ops.error_groups where fingerprint = '00000000000000aa') = 1
    and r.occurrences = 100,
    'the same error 100 times is one row counting 100');

  perform pg_temp.check(
    (select count(*) from ops.error_samples where group_id = first_id) = 5,
    'and keeps exactly 5 samples');

  perform pg_temp.check(
    (select array_agg(request_id order by request_id) from ops.error_samples where group_id = first_id)
      = array['req-00000096', 'req-00000097', 'req-00000098', 'req-00000099', 'req-00000100'],
    'the 5 samples are the newest; the oldest were replaced');

  perform pg_temp.check(r.users_affected = 1,
    'one player hit 50 times and anonymous reports count as one player');

  select * into r from pg_temp.hit('00000000000000aa', 'abc1234', b, 'req-00000101', '2026-10-03 12:00+00');
  perform pg_temp.check(r.users_affected = 2, 'a second player raises the count to 2');

  perform pg_temp.check(
    (select last_build from ops.error_groups where id = first_id) = 'abc1234'
    and (select occurrences from ops.error_group_builds where group_id = first_id and build = 'abc1234') = 101,
    'the build tally follows every occurrence');

  -- An admin marks it fixed; an old install of the same build still reports it.
  update ops.error_groups set status = 'fixed', status_changed_at = '2026-10-03 13:00+00' where id = first_id;
  select * into r from pg_temp.hit('00000000000000aa', 'abc1234', a, 'req-00000102', '2026-10-03 14:00+00');
  perform pg_temp.check(r.status = 'fixed' and not r.reopened,
    'a fixed error from a build that already had it stays fixed');

  select * into r from pg_temp.hit('00000000000000aa', 'def5678', a, 'req-00000103', '2026-10-03 15:00+00');
  perform pg_temp.check(r.status = 'new' and r.reopened
    and (select reopened_count from ops.error_groups where id = first_id) = 1
    and (select last_build from ops.error_groups where id = first_id) = 'def5678',
    'a fixed error in a newer build comes back as new');

  select * into r from pg_temp.hit('00000000000000aa', 'def5678', a, 'req-00000104', '2026-10-03 15:01+00');
  perform pg_temp.check(r.status = 'new' and not r.reopened,
    'it reopens once, not on every occurrence');

  update ops.error_groups set status = 'verified' where id = first_id;
  select * into r from pg_temp.hit('00000000000000aa', 'fff0001', null, 'req-00000105', '2026-10-03 16:00+00');
  perform pg_temp.check(r.status = 'new' and r.reopened, 'a verified error reopens too');

  update ops.error_groups set status = 'ignored' where id = first_id;
  select * into r from pg_temp.hit('00000000000000aa', 'fff0002', null, 'req-00000106', '2026-10-03 17:00+00');
  perform pg_temp.check(r.status = 'ignored' and not r.reopened, 'an ignored error stays ignored');

  select * into r from pg_temp.hit('00000000000000bb', 'abc1234',
    '00000000-0000-4000-8087-999999999999', 'req-00000107', '2026-10-03 17:00+00');
  perform pg_temp.check(r.is_new and r.users_affected = 0
    and (select user_id from ops.error_samples where group_id = r.group_id) is null,
    'an unknown player id is dropped, not a failure');

  perform pg_temp.check(
    (select count(*) from ops.error_groups) = 2,
    'two fingerprints are two rows');
end $$;

do $$
begin
  begin
    perform pg_temp.hit('NOT-A-FINGERPRINT', 'abc1234', null, 'req-00000200', now());
    raise exception 'FAILED: a malformed fingerprint was accepted';
  exception when check_violation then
    raise notice 'ok - a malformed fingerprint is refused';
  end;
  begin
    perform pg_temp.hit('00000000000000cc', 'bad build!', null, 'req-00000201', now());
    raise exception 'FAILED: a malformed build was accepted';
  exception when check_violation then
    raise notice 'ok - a malformed build is refused';
  end;
end $$;

select pg_temp.check(
  not has_function_privilege('anon', 'ops.record_error(text, text, text, text, text, text, text, integer, text, text, text, timestamptz, uuid, text, text, text, text, text, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'ops.record_error(text, text, text, text, text, text, text, integer, text, text, text, timestamptz, uuid, text, text, text, text, text, text, jsonb)', 'execute')
  and not has_table_privilege('anon', 'ops.error_samples', 'select')
  and not has_table_privilege('authenticated', 'ops.error_groups', 'select'),
  'nothing is reachable by anon or authenticated');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations where version = '0087_error_log'),
  'the migration records itself');

rollback;
