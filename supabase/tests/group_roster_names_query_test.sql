-- End-to-end test of PostgresGroupRepository._memberDisplayNamesSql
-- (parameters inlined; keep the body identical to the adapter's constant):
-- a league's roster names its members, and only its members. Batch 141.
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

-- PostgresGroupRepository._memberDisplayNamesSql
create function pg_temp.member_names(p_group_id uuid)
returns table (user_id text, display_name text)
language sql as $q$
SELECT gm.user_id::text AS user_id,
       u.display_name   AS display_name
FROM "group".group_memberships gm
JOIN identity.users u ON u.id = gm.user_id
WHERE gm.group_id = p_group_id
$q$;

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0141-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'p' || n || '@example.com', now()
  from generate_series(1, 3) n;
insert into identity.users (id, email, display_name)
select ('00000000-0141-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'p' || n || '@example.com', 'Player ' || n
  from generate_series(1, 3) n;

insert into "group".groups (id, owner_id, name, invite_code)
values ('00000000-0141-4000-8000-0000000000aa',
        '00000000-0141-4000-8000-000000000001', 'Friends', 'BBBBBBBBBB');
insert into "group".group_memberships (id, group_id, user_id, role) values
  (gen_random_uuid(), '00000000-0141-4000-8000-0000000000aa',
   '00000000-0141-4000-8000-000000000001', 'owner'),
  (gen_random_uuid(), '00000000-0141-4000-8000-0000000000aa',
   '00000000-0141-4000-8000-000000000002', 'member');

do $$
declare
  got text[];
begin
  select array_agg(m.user_id || '=' || m.display_name order by m.user_id) into got
    from pg_temp.member_names('00000000-0141-4000-8000-0000000000aa') m;
  perform pg_temp.check(got = array[
      '00000000-0141-4000-8000-000000000001=Player 1',
      '00000000-0141-4000-8000-000000000002=Player 2'],
    'the members by name, and no one else');
end $$;

rollback;
