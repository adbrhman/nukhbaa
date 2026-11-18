-- End-to-end test for migration 0216: the chat of each head-to-head group.
-- Only a seated member who accepted the rules writes in a group; the body
-- is 1 to 500 trimmed characters; a muted player cannot write; a player
-- seated in a later month can no longer write in the old group; the unread
-- marker, the listing a player gets (hidden messages left out), and a
-- deleted account taking its chat data with it. Rolled back at the end.
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
  ('00000000-0216-4000-8216-000000000001', 'gc1@t.io', now()),
  ('00000000-0216-4000-8216-000000000002', 'gc2@t.io', now()),
  ('00000000-0216-4000-8216-000000000003', 'gc3@t.io', now()),
  ('00000000-0216-4000-8216-000000000004', 'gc4@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0216-4000-8216-000000000001', 'gc1@t.io', 'GC One'),
  ('00000000-0216-4000-8216-000000000002', 'gc2@t.io', 'GC Two'),
  ('00000000-0216-4000-8216-000000000003', 'gc3@t.io', 'GC Three'),
  ('00000000-0216-4000-8216-000000000004', 'gc4@t.io', 'GC Four');

do $$
declare
  u1 uuid := '00000000-0216-4000-8216-000000000001';
  u2 uuid := '00000000-0216-4000-8216-000000000002';
  u3 uuid := '00000000-0216-4000-8216-000000000003';
  u4 uuid := '00000000-0216-4000-8216-000000000004';
  g1 uuid := '00000000-0216-4000-8216-000000000011';
  g2 uuid := '00000000-0216-4000-8216-000000000012';
  g3 uuid := '00000000-0216-4000-8216-000000000013';
  m1 bigint;
  m2 bigint;
  n  int;
begin
  insert into gamification.h2h_months (month_start, seated_count)
  values ('2099-11-01', 4);
  insert into gamification.h2h_leagues
    (id, month_start, division, group_index, capacity)
  values (g1, '2099-11-01', 1, 0, 20),
         (g2, '2099-11-01', 4, 0, 4);
  insert into gamification.h2h_league_members
    (league_id, month_start, user_id, slot)
  values (g1, '2099-11-01', u1, 0),
         (g1, '2099-11-01', u2, 1),
         (g1, '2099-11-01', u3, 2),
         (g2, '2099-11-01', u4, 0);

  -- The rules come first.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, 'hello'))
      = '23514/h2h_messages_rules_not_accepted',
    'a player who has not accepted the rules cannot write');
  insert into chat.rules_acceptances (user_id)
  values (u1), (u2), (u3), (u4);

  -- A member writes.
  insert into chat.h2h_messages (league_id, sender_id, body)
  values (g1, u1, 'hello group')
  returning id into m1;
  insert into chat.h2h_messages (league_id, sender_id, body)
  values (g1, u2, 'hi')
  returning id into m2;
  select count(*) into n from chat.h2h_messages where league_id = g1;
  perform pg_temp.check(n = 2, 'two members wrote in their group');

  -- Only the members of the group.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u4, 'let me in'))
      = '23514/h2h_messages_member_only',
    'a player of another group cannot write here');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)',
      '00000000-0216-4000-8216-0000000000ff', u1, 'nowhere'))
      = '23514/h2h_messages_member_only',
    'nor in a group that does not exist');

  -- The text: 1 to 500 trimmed characters.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, ''))
      = '23514/h2h_messages_body_check',
    'an empty message is refused');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, ' padded'))
      = '23514/h2h_messages_body_check',
    'a message with a leading space is refused');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, repeat('x', 501)))
      = '23514/h2h_messages_body_check',
    'a message of 501 characters is refused');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, repeat('x', 500))) = 'none',
    'a message of 500 characters is accepted');

  -- A muted player cannot write; the others still can.
  insert into chat.muted_users (user_id) values (u3);
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u3, 'muted'))
      = '23514/h2h_messages_sender_muted',
    'a muted player cannot write');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u2, 'still here')) = 'none',
    'the others still can');
  delete from chat.muted_users where user_id = u3;
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u3, 'back')) = 'none',
    'an unmuted player writes again');

  -- The listing a player gets: hidden messages left out.
  update chat.h2h_messages set hidden_at = now() where id = m2;
  select count(*) into n
    from chat.h2h_messages m
   where m.league_id = g1 and m.hidden_at is null;
  perform pg_temp.check(n = 4,
    'a message an admin hid is no longer listed');

  -- The unread marker.
  insert into chat.h2h_reads (league_id, user_id, last_read_id)
  values (g1, u3, m1)
  on conflict (league_id, user_id)
  do update set last_read_id = greatest(chat.h2h_reads.last_read_id,
                                        excluded.last_read_id);
  select count(*) into n
    from chat.h2h_messages m
   where m.league_id = g1 and m.hidden_at is null
     and m.id > (select r.last_read_id from chat.h2h_reads r
                  where r.league_id = g1 and r.user_id = u3);
  perform pg_temp.check(n = 3, 'unread messages are counted after the marker');

  -- Next month seats u1 elsewhere: the old group is closed to him only.
  insert into gamification.h2h_months (month_start, seated_count)
  values ('2099-12-01', 1);
  insert into gamification.h2h_leagues
    (id, month_start, division, group_index, capacity)
  values (g3, '2099-12-01', 1, 0, 20);
  insert into gamification.h2h_league_members
    (league_id, month_start, user_id, slot)
  values (g3, '2099-12-01', u1, 0);
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u1, 'old group')
    ) = '23514/h2h_messages_group_closed',
    'a player seated in a later month cannot write in the old group');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g3, u1, 'new group')) = 'none',
    'but writes in his new group');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into chat.h2h_messages (league_id, sender_id, body) '
      'values (%L, %L, %L)', g1, u2, 'old group still open')) = 'none',
    'the old group stays open to those not yet seated again');

  -- A deleted account takes its chat data with it, and nobody else's.
  update identity.users set deleted_at = now(), email = null where id = u1;
  perform pg_temp.check(
    not exists (select 1 from chat.h2h_messages where sender_id = u1),
    'a deleted account''s messages are gone');
  perform pg_temp.check(
    not exists (select 1 from chat.rules_acceptances where user_id = u1),
    'with his rules acceptance');
  perform pg_temp.check(
    exists (select 1 from chat.h2h_messages where sender_id = u2),
    'but not the messages of the others');

  -- Server-only: RLS on every table, nothing granted to the app roles.
  select count(*) into n from pg_class
   where relnamespace = 'chat'::regnamespace and relkind = 'r'
     and relrowsecurity;
  perform pg_temp.check(n = 4, 'RLS is on for the four chat tables');
  perform pg_temp.check(
    not has_table_privilege('anon', 'chat.h2h_messages', 'select')
    and not has_table_privilege('authenticated', 'chat.h2h_messages',
                                'select'),
    'the app roles can read nothing of the chat');
end $$;

rollback;
