-- End-to-end test for migration 0097: the statements
-- PostgresGroupInvitationRepository runs (parameters inlined) record one
-- invitation per league and player, read it with the league's name and the
-- inviter's, answer a pending one only, and find the player's push target;
-- the backstop refuses a self-invitation and an unknown status; and a
-- group_invited notification can be stored.
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

-- PostgresGroupInvitationRepository.createSql
create function pg_temp.invite(
  p_id uuid, p_group uuid, p_inviter uuid, p_invitee uuid, p_at timestamptz
) returns setof uuid
language sql as $$
INSERT INTO "group".group_invitations
  (id, group_id, inviter_user_id, invitee_user_id, status, created_at)
VALUES
  (p_id, p_group, p_inviter, p_invitee, 'pending', p_at)
ON CONFLICT ON CONSTRAINT group_invitations_once DO NOTHING
RETURNING id
$$;

-- PostgresGroupInvitationRepository.findSql / listSql
create function pg_temp.list(p_invitee uuid)
returns table (id text, group_id text, group_name text, inviter_user_id text,
               inviter_name text, invitee_user_id text, status text,
               created_at timestamptz)
language sql as $$
SELECT i.id::text AS id,
       i.group_id::text AS group_id,
       g.name AS group_name,
       i.inviter_user_id::text AS inviter_user_id,
       coalesce(u.display_name, '') AS inviter_name,
       i.invitee_user_id::text AS invitee_user_id,
       i.status AS status,
       i.created_at AS created_at
FROM "group".group_invitations i
JOIN "group".groups g ON g.id = i.group_id
JOIN identity.users u ON u.id = i.inviter_user_id
WHERE i.invitee_user_id = p_invitee ORDER BY i.created_at DESC LIMIT 50
$$;

-- PostgresGroupInvitationRepository.respondSql
create function pg_temp.answer(
  p_id uuid, p_invitee uuid, p_status text, p_at timestamptz
) returns setof uuid
language sql as $$
UPDATE "group".group_invitations
SET status = p_status, responded_at = p_at
WHERE id = p_id
  AND invitee_user_id = p_invitee
  AND status = 'pending'
RETURNING id
$$;

do $$
declare
  owner uuid := '00000000-0097-4000-8097-000000000001';
  friend uuid := '00000000-0097-4000-8097-000000000002';
  other uuid := '00000000-0097-4000-8097-000000000003';
  league uuid := '00000000-0097-4000-8097-000000000011';
  inv uuid := '00000000-0097-4000-8097-000000000021';
  inv2 uuid := '00000000-0097-4000-8097-000000000022';
  n int;
  r record;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (owner, 'g1@t.io', now()), (friend, 'g2@t.io', now()),
    (other, 'g3@t.io', now());
  insert into identity.users (id, email, display_name) values
    (owner, 'g1@t.io', 'Owner One'), (friend, 'g2@t.io', 'Friend Two'),
    (other, 'g3@t.io', 'Other Three');
  insert into "group".groups (id, owner_id, name, invite_code)
    values (league, owner, 'Office', 'ABCD23EFGH');
  insert into notification.device_tokens (user_id, token, platform)
    values (friend, 'tok-a', 'android'), (friend, 'tok-b', 'web');

  select count(*) into n from pg_temp.invite(inv, league, owner, friend, now());
  perform pg_temp.check(n = 1, 'an invitation is recorded');
  select count(*) into n from pg_temp.invite(inv2, league, owner, friend, now());
  perform pg_temp.check(n = 0, 'the same player is not invited to it twice');

  select * into r from pg_temp.list(friend);
  perform pg_temp.check(
    r.id = inv::text and r.group_name = 'Office'
      and r.inviter_name = 'Owner One' and r.status = 'pending',
    'the player reads it with the league and who invited');
  select count(*) into n from pg_temp.list(other);
  perform pg_temp.check(n = 0, 'nobody else reads it');

  select count(*) into n from pg_temp.answer(inv, other, 'accepted', now());
  perform pg_temp.check(n = 0, 'only the invited player answers');
  select count(*) into n from pg_temp.answer(inv, friend, 'declined', now());
  perform pg_temp.check(n = 1, 'the player declines');
  select count(*) into n from pg_temp.answer(inv, friend, 'accepted', now());
  perform pg_temp.check(n = 0, 'an answered invitation stays answered');
  perform pg_temp.check(
    (select status = 'declined' and responded_at is not null
       from "group".group_invitations where id = inv),
    'the answer and its time are kept');

  -- PostgresGroupInvitationRepository.pushTargetSql
  select coalesce((
           select string_agg(dt.token, ',')
           from notification.device_tokens dt
           where dt.user_id = u.id
         ), '') as tokens
    into r
    from identity.users u where u.id = friend;
  perform pg_temp.check(
    r.tokens in ('tok-a,tok-b', 'tok-b,tok-a'),
    'the push target joins the player tokens');

  begin
    perform pg_temp.invite(
      '00000000-0097-4000-8097-000000000023', league, owner, owner, now());
    perform pg_temp.check(false, 'a self-invitation is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'a self-invitation is refused');
  end;

  begin
    update "group".group_invitations set status = 'maybe' where id = inv;
    perform pg_temp.check(false, 'an unknown status is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'an unknown status is refused');
  end;

  insert into notification.notifications
    (id, recipient_id, kind, group_id, actor_user_id, subject_ref, created_at)
  values
    ('00000000-0097-4000-8097-000000000031', friend, 'group_invited', league,
     owner, 'group_invited:' || league || ':' || owner, now());
  perform pg_temp.check(true, 'a group_invited notification is stored');
end $$;

select pg_temp.check(
  not has_table_privilege('authenticated', '"group".group_invitations',
    'select'),
  'the table is server-only');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0097_group_invitations'),
  'migration records itself');

rollback;
