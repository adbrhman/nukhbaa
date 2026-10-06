-- Test for migration 0096: a browser token is stored as platform 'web'
-- with the same upsert PostgresDeviceTokenRepository runs, and any other
-- platform is still refused.
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

do $$
declare
  u uuid := '00000000-0096-4000-8096-000000000001';
  refused boolean := false;
begin
  insert into auth.users (id, email, email_confirmed_at)
    values (u, 'w1@t.io', now());
  insert into identity.users (id, email, display_name)
    values (u, 'w1@t.io', 'Web One');

  insert into notification.device_tokens (token, user_id, platform)
    values ('web-token-1', u, 'web')
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
  perform pg_temp.check(
    exists (select 1 from notification.device_tokens
             where token = 'web-token-1' and platform = 'web'),
    'a browser token is stored as web');

  begin
    insert into notification.device_tokens (token, user_id, platform)
      values ('other-token', u, 'windows');
  exception when check_violation then
    refused := true;
  end;
  perform pg_temp.check(refused, 'any other platform is still refused');
end $$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0096_web_push_tokens'),
  'migration records itself');

rollback;
