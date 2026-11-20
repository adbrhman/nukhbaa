-- End-to-end test for migration 0220: the admins' announcements held for
-- an owner seat. The adapter's own statements (PostgresAnnouncementRequest
-- Store): hold once, read with the author's name, decide once. Rolled back
-- at the end.
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
  ('00000000-0220-4000-8220-000000000001', 'ar1@t.io', now()),
  ('00000000-0220-4000-8220-000000000002', 'ar2@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0220-4000-8220-000000000001', 'ar1@t.io', 'مشرف', 'admin'),
  ('00000000-0220-4000-8220-000000000002', 'ar2@t.io', 'المالك', 'admin');

-- hold: the first call keeps it, the same id again changes nothing.
create temp table held as
with ins as (
  insert into notification.announcement_requests (id, author_id, title, body)
  values ('00000000-0220-4000-8220-0000000000a1'::uuid,
          '00000000-0220-4000-8220-000000000001'::uuid, 'تنبيه', 'نص')
  on conflict (id) do nothing
  returning id
) select count(*) as n from ins;
select pg_temp.check((select n from held) = 1, 'the first hold keeps it');

create temp table again as
with ins as (
  insert into notification.announcement_requests (id, author_id, title, body)
  values ('00000000-0220-4000-8220-0000000000a1'::uuid,
          '00000000-0220-4000-8220-000000000001'::uuid, 'آخر', 'آخر')
  on conflict (id) do nothing
  returning id
) select count(*) as n from ins;
select pg_temp.check((select n from again) = 0, 'the same id again is ignored');
select pg_temp.check(
  (select title from notification.announcement_requests
    where id = '00000000-0220-4000-8220-0000000000a1') = 'تنبيه',
  'the first text stays');

-- byId / latest read the author's name.
select pg_temp.check(
  (select coalesce(u.display_name, '')
     from notification.announcement_requests r
     join identity.users u on u.id = r.author_id
    where r.id = '00000000-0220-4000-8220-0000000000a1'::uuid) = 'مشرف',
  'the author''s name is read');
select pg_temp.check(
  (select status from notification.announcement_requests
    where id = '00000000-0220-4000-8220-0000000000a1') = 'pending',
  'a held request is pending');

-- decide: once only, from pending.
create temp table first_decision as
with up as (
  update notification.announcement_requests
     set status = 'published',
         decided_by = '00000000-0220-4000-8220-000000000002'::uuid,
         decided_at = now(),
         recipients = 12::int
   where id = '00000000-0220-4000-8220-0000000000a1'::uuid
     and status = 'pending'
  returning id
) select count(*) as n from up;
select pg_temp.check((select n from first_decision) = 1, 'published once');

create temp table second_decision as
with up as (
  update notification.announcement_requests
     set status = 'rejected',
         decided_by = '00000000-0220-4000-8220-000000000002'::uuid,
         decided_at = now(),
         recipients = null::int
   where id = '00000000-0220-4000-8220-0000000000a1'::uuid
     and status = 'pending'
  returning id
) select count(*) as n from up;
select pg_temp.check((select n from second_decision) = 0,
  'a decided request is not decided again');
select pg_temp.check(
  (select recipients from notification.announcement_requests
    where id = '00000000-0220-4000-8220-0000000000a1') = 12,
  'the recipients are kept');

-- The checks.
select pg_temp.check(
  pg_temp.refusal($q$insert into notification.announcement_requests
    (id, author_id, title, body) values (gen_random_uuid(),
    '00000000-0220-4000-8220-000000000001', '  ', 'x')$q$)
  = '23514/announcement_requests_title_check', 'a blank title is refused');
select pg_temp.check(
  pg_temp.refusal($q$insert into notification.announcement_requests
    (id, author_id, title, body, status, decided_at) values (gen_random_uuid(),
    '00000000-0220-4000-8220-000000000001', 'x', 'x', 'sent', now())$q$)
  = '23514/announcement_requests_status_check', 'an unknown status is refused');
select pg_temp.check(
  pg_temp.refusal($q$insert into notification.announcement_requests
    (id, author_id, title, body, status) values (gen_random_uuid(),
    '00000000-0220-4000-8220-000000000001', 'x', 'x', 'rejected')$q$)
  = '23514/announcement_requests_decided_check',
  'a decided request needs its time');

select pg_temp.check(
  (select version from ops.applied_migrations
    where version = '0220_announcement_requests') is not null,
  'the migration recorded itself');

rollback;
