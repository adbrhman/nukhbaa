-- End-to-end test for migration 0106: the "N matches still to predict"
-- record keeps one row per user per day, follows the user's deletion, and
-- stays out of reach of the client roles. Rolled back at the end.
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

insert into auth.users (id, email, email_confirmed_at)
values ('a1060000-0000-4000-8000-000000000001', 'incomplete-day@t.io', now());
insert into identity.users (id, email)
values ('a1060000-0000-4000-8000-000000000001', 'incomplete-day@t.io');

insert into notification.incomplete_day_sends (user_id, send_date)
values ('a1060000-0000-4000-8000-000000000001', date '2030-01-15');

insert into notification.incomplete_day_sends (user_id, send_date)
values ('a1060000-0000-4000-8000-000000000001', date '2030-01-15')
on conflict on constraint incomplete_day_sends_pkey do nothing;

insert into notification.incomplete_day_sends (user_id, send_date)
values ('a1060000-0000-4000-8000-000000000001', date '2030-01-16');

do $$
begin
  perform pg_temp.check(
    (select count(*) from notification.incomplete_day_sends
      where user_id = 'a1060000-0000-4000-8000-000000000001') = 2,
    'one row per user per day');
  perform pg_temp.check(
    (select relrowsecurity from pg_class
      where oid = 'notification.incomplete_day_sends'::regclass),
    'row level security is on');
  perform pg_temp.check(
    not has_table_privilege('authenticated', 'notification.incomplete_day_sends', 'select'),
    'the client cannot read it');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0106_incomplete_day_sends'),
    'the migration records itself');
end $$;

delete from identity.users where id = 'a1060000-0000-4000-8000-000000000001';

do $$
begin
  perform pg_temp.check(
    not exists (select 1 from notification.incomplete_day_sends
                 where user_id = 'a1060000-0000-4000-8000-000000000001'),
    'a deleted user takes their rows along');
end $$;

rollback;
