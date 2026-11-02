-- Test for migration 0197 (script 200): the statements the server runs,
-- copied below with their parameters as function arguments:
-- PostgresInstallFixtureClaims (one account per match on one phone),
-- PostgresDeviceSightings.record (GET /me) and .sharedDevices (the admin
-- list). Rolled back at the end.
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

create function pg_temp.claim(p_install text, p_fixture uuid, p_user uuid)
returns text
language sql as $f$
WITH seen AS (
  INSERT INTO identity.install_accounts (install_key, user_id)
  VALUES (md5(p_install), p_user)
  ON CONFLICT (install_key, user_id) DO UPDATE
    SET last_seen = now()
),
claimed AS (
  INSERT INTO prediction.install_claims (install_key, fixture_id, user_id)
  VALUES (md5(p_install), p_fixture, p_user)
  ON CONFLICT (install_key, fixture_id) DO NOTHING
  RETURNING user_id
)
SELECT user_id::text AS user_id FROM claimed
UNION ALL
SELECT user_id::text
FROM prediction.install_claims
WHERE install_key = md5(p_install)
  AND fixture_id = p_fixture
LIMIT 1
$f$;

create function pg_temp.record(p_install text, p_user uuid)
returns void
language sql as $f$
INSERT INTO identity.install_accounts (install_key, user_id)
VALUES (md5(p_install), p_user)
ON CONFLICT (install_key, user_id) DO UPDATE
  SET last_seen = now()
$f$;

create function pg_temp.shared(p_limit int)
returns table (phone_key text, last_seen timestamptz, id text, email text,
               role text, status text, display_name text)
language sql as $f$
WITH sightings AS (
  SELECT 'i:' || install_key AS device_key, user_id, last_seen AS seen
  FROM identity.install_accounts
  UNION ALL
  SELECT 't:' || token_key, user_id, first_seen
  FROM notification.device_token_owners
),
devices AS (
  SELECT array_agg(DISTINCT user_id ORDER BY user_id) AS members,
         max(seen) AS last_seen
  FROM sightings
  GROUP BY device_key
  HAVING count(DISTINCT user_id) > 1
),
merged AS (
  SELECT members, max(last_seen) AS last_seen
  FROM devices
  GROUP BY members
),
phones AS (
  SELECT m.members, m.last_seen
  FROM merged m
  WHERE NOT EXISTS (
    SELECT 1
    FROM merged o
    WHERE o.members @> m.members
      AND o.members <> m.members
  )
  ORDER BY cardinality(m.members) DESC, m.last_seen DESC, m.members
  LIMIT p_limit
)
SELECT p.members::text AS phone_key,
       p.last_seen,
       u.id::text AS id,
       u.email,
       u.role::text AS role,
       u.status::text AS status,
       u.display_name
FROM phones p
JOIN identity.users u
  ON u.id = ANY (p.members)
ORDER BY cardinality(p.members) DESC, p.last_seen DESC, p.members,
         u.created_at ASC, u.id
$f$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0197_shared_devices'),
  'migration records itself');

select pg_temp.check(
  (select relrowsecurity from pg_class
    where oid = 'identity.install_accounts'::regclass)
  and (select relrowsecurity from pg_class
    where oid = 'prediction.install_claims'::regclass),
  'row level security is on for both tables');

select pg_temp.check(
  not has_table_privilege('authenticated', 'prediction.install_claims',
                          'select')
  and not has_table_privilege('anon', 'identity.install_accounts', 'select'),
  'no client role reads them');

do $$
declare
  a uuid := '00000000-0197-4000-8197-000000000001';
  b uuid := '00000000-0197-4000-8197-000000000002';
  c uuid := '00000000-0197-4000-8197-000000000003';
  d uuid := '00000000-0197-4000-8197-000000000004';
  e uuid := '00000000-0197-4000-8197-000000000005';
  f1 uuid := '00000000-0197-4000-8197-0000000000f1';
  f2 uuid := '00000000-0197-4000-8197-0000000000f2';
  phone text := '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  other text := 'ffffffff-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  n int;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (a, 'a197@t.io', now()), (b, 'b197@t.io', now()),
    (c, 'c197@t.io', now()), (d, 'd197@t.io', now()),
    (e, 'e197@t.io', now());
  insert into identity.users (id, email, display_name) values
    (a, 'a197@t.io', 'A 197'), (b, 'b197@t.io', 'B 197'),
    (c, 'c197@t.io', 'C 197'), (d, 'd197@t.io', 'D 197'),
    (e, 'e197@t.io', 'E 197');

  -- One account per match on one phone.
  perform pg_temp.check(pg_temp.claim(phone, f1, a) = a::text,
    'the first account claims the match on the phone');
  perform pg_temp.check(pg_temp.claim(phone, f1, a) = a::text,
    'the same account claims it again (an amend)');
  perform pg_temp.check(pg_temp.claim(phone, f1, b) = a::text,
    'a second account on the phone gets the holder back');
  perform pg_temp.check(pg_temp.claim(phone, f2, b) = b::text,
    'the second account claims another match on the phone');
  perform pg_temp.check(pg_temp.claim(other, f1, b) = b::text,
    'another phone claims the same match for itself');
  select count(*) into n from prediction.install_claims
   where fixture_id in (f1, f2);
  perform pg_temp.check(n = 3, 'three claims, one per (phone, match)');
  perform pg_temp.check(
    (select install_key from prediction.install_claims
      where fixture_id = f2) = md5(phone),
    'the install id is stored as md5 only');

  -- A claim records the account on the phone, as GET /me does.
  select count(*) into n from identity.install_accounts
   where install_key = md5(phone);
  perform pg_temp.check(n = 2, 'both accounts are seen on the phone');
  perform pg_temp.record(phone, a);
  select count(*) into n from identity.install_accounts
   where install_key = md5(phone);
  perform pg_temp.check(n = 2, 'a repeat sighting adds no row');

  -- The admin list: the phone with a and b; c and d share a push token
  -- (0177, before the install id); e is alone.
  insert into notification.device_token_owners (token_key, user_id, platform)
  values (md5('tok-197'), c, 'android'), (md5('tok-197'), d, 'android'),
         (md5('tok-197-e'), e, 'android');
  -- The phone of a and b also registered its push token: the same phone.
  insert into notification.device_token_owners (token_key, user_id, platform)
  values (md5('tok-197-ab'), a, 'android'), (md5('tok-197-ab'), b, 'android');
  update identity.users set status = 'suspended' where id = d;

  select count(distinct phone_key) into n from pg_temp.shared(100)
   where id in (a::text, b::text, c::text, d::text, e::text);
  perform pg_temp.check(n = 2,
    'two shared phones: install and token of one phone are one');
  perform pg_temp.check(
    not exists (select 1 from pg_temp.shared(100) where id = e::text),
    'an account alone on its phone is not listed');
  perform pg_temp.check(
    (select status from pg_temp.shared(100) where id = d::text) = 'suspended',
    'a suspended account is listed with its status');

  -- A third account on the a/b phone: the a/b token phone is a part of
  -- it and is left out.
  perform pg_temp.record(phone, c);
  perform pg_temp.check(
    (select count(*) from pg_temp.shared(100)
      where phone_key = (select phone_key from pg_temp.shared(100)
                          where id = a::text limit 1)) = 3,
    'the phone now lists its three accounts');
  perform pg_temp.check(
    (select count(distinct phone_key) from pg_temp.shared(100)
      where id = a::text) = 1,
    'the smaller list of the same accounts is left out');
  perform pg_temp.check(
    (select count(distinct phone_key) from pg_temp.shared(100)
      where id = c::text) = 2,
    'c is on two phones: the a/b/c install and the c/d token');
  perform pg_temp.check(
    (select phone_key from pg_temp.shared(100) limit 1)
      = (select phone_key from pg_temp.shared(100) where id = a::text limit 1),
    'the most crowded phone comes first');

  -- A removed account takes its rows with it.
  delete from identity.users where id = e;
  perform pg_temp.check(
    not exists (select 1 from notification.device_token_owners
                 where user_id = e),
    'a removed account leaves no row');
  delete from identity.users where id = b;
  perform pg_temp.check(
    not exists (select 1 from prediction.install_claims where user_id = b)
    and not exists (select 1 from identity.install_accounts where user_id = b),
    'the claims and sightings go with the account');
end $$;

rollback;
