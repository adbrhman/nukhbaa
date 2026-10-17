-- Test for migration 0177: the upsert PostgresDeviceTokenRepository runs
-- (copied below with its parameters as function arguments) keeps every
-- account a token was registered for, through a rebind and through a
-- sign-out (script 102). Rolled back at the end.
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

create function pg_temp.register(p_user uuid, p_token text, p_platform text)
returns void
language sql as $f$
WITH native AS (
  SELECT EXISTS (
    SELECT 1
    FROM notification.device_tokens
    WHERE user_id = p_user
      AND platform <> 'web'
      AND token <> p_token
  ) AS present
),
retired_web AS (
  DELETE FROM notification.device_tokens
  WHERE p_platform <> 'web'
    AND user_id = p_user
    AND platform = 'web'
    AND token <> p_token
),
skipped_web AS (
  DELETE FROM notification.device_tokens
  WHERE p_platform = 'web'
    AND token = p_token
    AND (SELECT present FROM native)
),
owners AS (
  INSERT INTO notification.device_token_owners (token_key, user_id, platform)
  VALUES (md5(p_token), p_user, p_platform)
  ON CONFLICT (token_key, user_id) DO NOTHING
)
INSERT INTO notification.device_tokens (token, user_id, platform, updated_at)
SELECT p_token, p_user, p_platform, now()
WHERE p_platform <> 'web' OR NOT (SELECT present FROM native)
ON CONFLICT (token) DO UPDATE
  SET user_id = excluded.user_id,
      platform = excluded.platform,
      updated_at = now()
$f$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0177_device_token_owners'),
  'migration records itself');

select pg_temp.check(
  (select relrowsecurity from pg_class
    where oid = 'notification.device_token_owners'::regclass),
  'row level security is on');

do $$
declare
  a uuid := '00000000-0177-4000-8177-000000000001';
  b uuid := '00000000-0177-4000-8177-000000000002';
  c uuid := '00000000-0177-4000-8177-000000000003';
  k text := md5('tok-177');
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (a, 'a177@t.io', now()), (b, 'b177@t.io', now()), (c, 'c177@t.io', now());
  insert into identity.users (id, email, display_name) values
    (a, 'a177@t.io', 'A 177'), (b, 'b177@t.io', 'B 177'),
    (c, 'c177@t.io', 'C 177');

  perform pg_temp.register(a, 'tok-177', 'android');
  perform pg_temp.check(
    (select count(*) from notification.device_token_owners
      where token_key = k) = 1,
    'the first account is kept');

  perform pg_temp.register(b, 'tok-177', 'android');
  perform pg_temp.check(
    (select user_id from notification.device_tokens
      where token = 'tok-177') = b,
    'the token is rebound to the second account');
  perform pg_temp.check(
    (select count(*) from notification.device_token_owners
      where token_key = k) = 2,
    'both accounts are kept after the rebind');

  perform pg_temp.register(b, 'tok-177', 'android');
  perform pg_temp.check(
    (select count(*) from notification.device_token_owners
      where token_key = k) = 2,
    'a repeat registration adds nothing');

  delete from notification.device_tokens
   where token = 'tok-177' and user_id = b;
  perform pg_temp.register(c, 'tok-177', 'android');
  perform pg_temp.check(
    (select count(distinct user_id) from notification.device_token_owners
      where token_key = k) = 3,
    'a sign-in after a sign-out is kept too');

  perform pg_temp.check(
    not exists (select 1 from notification.device_token_owners
                 where token_key = 'tok-177'),
    'the token itself is never stored');
end $$;

rollback;
