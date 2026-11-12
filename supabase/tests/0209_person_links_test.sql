-- Test for script 263 (migration 0209): the owner links one person's
-- accounts; the main and second account count, the others are hidden;
-- relinking and unlinking show again only what the link hid. Also the
-- statement PostgresPersonLinkStore lists with (copied below). Rolled back
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

create function pg_temp.hidden(p_id uuid) returns boolean
language sql as $f$
select hidden_at is not null from identity.users where id = p_id
$f$;

create function pg_temp.list(p_limit int)
returns table (person_id text, id text, email text, role text, status text,
               display_name text, counted boolean, hidden_at timestamptz)
language sql as $f$
SELECT l.person_id::text AS person_id, u.id::text AS id, u.email,
       u.role::text AS role, u.status::text AS status, u.display_name,
       l.counted, u.hidden_at
FROM identity.person_links l
JOIN identity.users u ON u.id = l.user_id
ORDER BY l.person_id, (l.user_id = l.person_id) DESC, l.counted DESC,
         u.display_name, u.id
LIMIT p_limit
$f$;

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-4000-8209-00000000000' || n)::uuid, 'p' || n || '@t.io', now()
  from generate_series(1, 6) n;
insert into identity.users (id, email, display_name)
select ('00000000-0000-4000-8209-00000000000' || n)::uuid, 'p' || n || '@t.io', 'Person ' || n
  from generate_series(1, 6) n;

do $$
declare
  a uuid := '00000000-0000-4000-8209-000000000001';
  b uuid := '00000000-0000-4000-8209-000000000002';
  c uuid := '00000000-0000-4000-8209-000000000003';
  d uuid := '00000000-0000-4000-8209-000000000004';
  e uuid := '00000000-0000-4000-8209-000000000005';
  x uuid := '00000000-0000-4000-8209-000000000006';
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0209_person_links'),
    '0209 records itself');
  perform pg_temp.check(identity.set_person(a, null, '{}', a) = 'too_few',
    'one account is no person');
  perform pg_temp.check(identity.set_person(a, b, array[b], a) = 'duplicate',
    'an account twice is refused');
  perform pg_temp.check(
    identity.set_person(a, b, array['00000000-0000-4000-8209-0000000000ff'::uuid], a)
      = 'unknown',
    'an unknown account is refused');
  perform pg_temp.check(
    (select count(*) from identity.person_links) = 0,
    'a refusal links nothing');

  -- e was hidden by the owner himself before.
  update identity.users set hidden_at = now() where id = e;

  perform pg_temp.check(identity.set_person(a, b, array[c, d, e], a) = 'ok',
    'a person of five accounts');
  perform pg_temp.check(
    not pg_temp.hidden(a) and not pg_temp.hidden(b),
    'the main and the second count');
  perform pg_temp.check(
    pg_temp.hidden(c) and pg_temp.hidden(d) and pg_temp.hidden(e),
    'the others are hidden');
  perform pg_temp.check(
    (select hidden_by_link from identity.person_links where user_id = e)
      is false,
    'the owner''s own hiding stays his');
  perform pg_temp.check(
    (select string_agg(id, ',' order by id) from pg_temp.list(500)
      where counted) = a::text || ',' || b::text,
    'the list marks the counted accounts');
  perform pg_temp.check(
    (select id from pg_temp.list(500) limit 1) = a::text,
    'the main account first');

  perform pg_temp.check(identity.set_person(x, a, '{}', a) = 'taken',
    'a linked account is not linked to another person');
  perform pg_temp.check(identity.set_person(x, null, array[a], a) = 'taken',
    'nor as another one''s other account');

  -- Relink: c becomes the second, b an other one, d leaves.
  perform pg_temp.check(identity.set_person(a, c, array[b, e], a) = 'ok',
    'the person set again');
  perform pg_temp.check(not pg_temp.hidden(c), 'c counted again is shown');
  perform pg_temp.check(pg_temp.hidden(b), 'b, now an other one, is hidden');
  perform pg_temp.check(not pg_temp.hidden(d), 'd, left out, is shown again');
  perform pg_temp.check(
    not exists (select 1 from identity.person_links where user_id = d),
    'd is no longer linked');

  perform pg_temp.check(identity.unlink_person(a) = 4,
    'unlinking answers how many were linked');
  perform pg_temp.check(
    not pg_temp.hidden(a) and not pg_temp.hidden(b) and not pg_temp.hidden(c),
    'unlinking shows what the link hid');
  perform pg_temp.check(pg_temp.hidden(e),
    'the owner''s own hiding is not undone');
  perform pg_temp.check(
    (select count(*) from identity.person_links) = 0, 'nothing is linked');
  perform pg_temp.check(identity.unlink_person(a) = 0,
    'unlinking again does nothing');

  -- The adapter's own parameters: text, '' for no second account.
  perform pg_temp.check(
    identity.set_person(a::text::uuid, nullif('', '')::uuid,
      string_to_array('', ',')::uuid[], a) = 'too_few',
    'no second and no other: too few');
  perform pg_temp.check(
    identity.set_person(a, nullif('', '')::uuid,
      string_to_array(b::text || ',' || c::text, ',')::uuid[], a) = 'ok',
    'the others as one comma-separated text');
  perform pg_temp.check(
    pg_temp.hidden(b) and pg_temp.hidden(c) and not pg_temp.hidden(a),
    'both others hidden, the main shown');
  perform identity.unlink_person(a);
end $$;

rollback;
