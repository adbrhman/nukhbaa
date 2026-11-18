-- End-to-end test of PostgresH2hChatRepository's statements (migration
-- 0216, script 281), each body identical to the adapter's constant
-- (parameters inlined as function arguments): the caller's group is the
-- newest month he sits in, the page (newest first, hidden messages left out,
-- after an id, limited), the unread count, a send (refused by the guard for
-- a muted player or one who has not accepted the rules), the read marker
-- and the rules (once). Rolled back at the end.
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

-- headSql
create function pg_temp.chat_head(p_player_id uuid)
returns table (league_id text, muted boolean, rules_accepted boolean, unread bigint)
language sql as $q$
SELECT g.league_id::text AS league_id,
       EXISTS (SELECT 1 FROM chat.muted_users mu
               WHERE mu.user_id = p_player_id::uuid) AS muted,
       EXISTS (SELECT 1 FROM chat.rules_acceptances ra
               WHERE ra.user_id = p_player_id::uuid) AS rules_accepted,
       (SELECT count(*)
        FROM chat.h2h_messages m
        WHERE m.league_id = g.league_id
          AND m.hidden_at IS NULL
          AND m.sender_id <> p_player_id::uuid
          AND m.id > coalesce(
                (SELECT r.last_read_id FROM chat.h2h_reads r
                 WHERE r.league_id = g.league_id
                   AND r.user_id = p_player_id::uuid), 0)
       )::bigint AS unread
FROM (SELECT lm.league_id
FROM gamification.h2h_league_members lm
WHERE lm.user_id = p_player_id::uuid
ORDER BY lm.month_start DESC
LIMIT 1) g
$q$;

-- messagesSql
create function pg_temp.chat_messages(p_league_id uuid, p_after bigint, p_limit int)
returns table (id bigint, sender_id text, sender_name text, body text, created_at timestamptz)
language sql as $q$
SELECT m.id, m.sender_id::text AS sender_id,
       coalesce(u.display_name, '') AS sender_name,
       m.body, m.created_at
FROM chat.h2h_messages m
JOIN identity.users u ON u.id = m.sender_id
WHERE m.league_id = p_league_id::uuid
  AND m.hidden_at IS NULL
  AND (p_after::bigint IS NULL OR m.id > p_after::bigint)
ORDER BY m.id DESC
LIMIT p_limit::int
$q$;

-- sendSql
create function pg_temp.chat_send(p_player_id uuid, p_body text, p_at timestamptz)
returns table (id bigint, created_at timestamptz, sender_name text)
language sql as $q$
WITH ins AS (
  INSERT INTO chat.h2h_messages (league_id, sender_id, body, created_at)
  SELECT g.league_id, p_player_id::uuid, p_body::text, p_at::timestamptz
  FROM (SELECT lm.league_id
FROM gamification.h2h_league_members lm
WHERE lm.user_id = p_player_id::uuid
ORDER BY lm.month_start DESC
LIMIT 1) g
  RETURNING id, created_at
)
SELECT ins.id, ins.created_at,
       coalesce(u.display_name, '') AS sender_name
FROM ins
JOIN identity.users u ON u.id = p_player_id::uuid
$q$;

-- markReadSql
create function pg_temp.chat_mark_read(p_player_id uuid, p_at timestamptz)
returns void
language sql as $q$
INSERT INTO chat.h2h_reads (league_id, user_id, last_read_id, updated_at)
SELECT g.league_id, p_player_id::uuid,
       coalesce((SELECT max(m.id) FROM chat.h2h_messages m
                 WHERE m.league_id = g.league_id), 0),
       p_at::timestamptz
FROM (SELECT lm.league_id
FROM gamification.h2h_league_members lm
WHERE lm.user_id = p_player_id::uuid
ORDER BY lm.month_start DESC
LIMIT 1) g
ON CONFLICT (league_id, user_id) DO UPDATE
SET last_read_id = greatest(chat.h2h_reads.last_read_id,
                            EXCLUDED.last_read_id),
    updated_at = EXCLUDED.updated_at
$q$;

-- acceptRulesSql
create function pg_temp.chat_accept_rules(p_player_id uuid, p_at timestamptz)
returns void
language sql as $q$
INSERT INTO chat.rules_acceptances (user_id, version, accepted_at)
VALUES (p_player_id::uuid, 1, p_at::timestamptz)
ON CONFLICT (user_id) DO NOTHING
$q$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0216-4000-8216-000000000101', 'cq1@t.io', now()),
  ('00000000-0216-4000-8216-000000000102', 'cq2@t.io', now()),
  ('00000000-0216-4000-8216-000000000103', 'cq3@t.io', now()),
  ('00000000-0216-4000-8216-000000000104', 'cq4@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0216-4000-8216-000000000101', 'cq1@t.io', 'CQ One'),
  ('00000000-0216-4000-8216-000000000102', 'cq2@t.io', 'CQ Two'),
  ('00000000-0216-4000-8216-000000000103', 'cq3@t.io', 'CQ Three'),
  ('00000000-0216-4000-8216-000000000104', 'cq4@t.io', 'CQ Four');

do $$
declare
  u1 uuid := '00000000-0216-4000-8216-000000000101';
  u2 uuid := '00000000-0216-4000-8216-000000000102';
  u3 uuid := '00000000-0216-4000-8216-000000000103';
  u4 uuid := '00000000-0216-4000-8216-000000000104';
  g1 uuid := '00000000-0216-4000-8216-000000000111';
  g3 uuid := '00000000-0216-4000-8216-000000000113';
  t0 timestamptz := '2099-11-05 10:00:00+00';
  m1 bigint;
  m2 bigint;
  m3 bigint;
  n  int;
  s  text;
begin
  insert into gamification.h2h_months (month_start, seated_count)
  values ('2099-11-01', 3);
  insert into gamification.h2h_leagues
    (id, month_start, division, group_index, capacity)
  values (g1, '2099-11-01', 1, 0, 20);
  insert into gamification.h2h_league_members
    (league_id, month_start, user_id, slot)
  values (g1, '2099-11-01', u1, 0),
         (g1, '2099-11-01', u2, 1),
         (g1, '2099-11-01', u3, 2);

  -- headSql: no seat, no row; a seat shows the flags.
  select count(*) into n from pg_temp.chat_head(u4);
  perform pg_temp.check(n = 0, 'a player with no seat has no group');
  perform pg_temp.check(
    (select league_id = g1::text and not muted and not rules_accepted
            and unread = 0
       from pg_temp.chat_head(u1)),
    'a seated player: no rules yet, nothing unread');

  -- acceptRulesSql, once.
  perform pg_temp.chat_accept_rules(u1, t0);
  perform pg_temp.chat_accept_rules(u1, t0 + interval '1 hour');
  perform pg_temp.chat_accept_rules(u2, t0);
  select count(*) into n from chat.rules_acceptances where user_id = u1;
  perform pg_temp.check(n = 1, 'the rules are accepted once');

  -- sendSql: the guard refuses the muted and the unconfirmed; no seat, no row.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'select * from pg_temp.chat_send(%L, %L, %L)', u3, 'hi', t0))
      = '23514/h2h_messages_rules_not_accepted',
    'a player who has not accepted the rules cannot write');
  select count(*) into n from pg_temp.chat_send(u4, 'hi', t0);
  perform pg_temp.check(n = 0, 'a player with no seat writes nothing');
  select id into m1 from pg_temp.chat_send(u1, 'one', t0);
  select id into m2 from pg_temp.chat_send(u2, 'two', t0 + interval '1 minute');
  select id into m3 from pg_temp.chat_send(u2, 'three', t0 + interval '2 minutes');
  perform pg_temp.check(m1 < m2 and m2 < m3, 'messages get rising ids');
  perform pg_temp.check(
    (select sender_name from pg_temp.chat_send(u1, 'four', t0 + interval '3 minutes')) = 'CQ One',
    'a send answers the sender''s name');

  -- headSql: unread counts the messages of others after the marker.
  perform pg_temp.check(
    (select unread from pg_temp.chat_head(u1)) = 2,
    'u1 has two unread messages of others');
  perform pg_temp.check(
    (select unread from pg_temp.chat_head(u2)) = 2,
    'u2 has two unread messages of others (one and four)');

  -- messagesSql: newest first, after an id, limited.
  select count(*) into n from pg_temp.chat_messages(g1, null, 50);
  perform pg_temp.check(n = 4, 'the page holds the four messages');
  perform pg_temp.check(
    (select id from pg_temp.chat_messages(g1, null, 1)) > m3,
    'a page of one is the newest message');
  select count(*) into n from pg_temp.chat_messages(g1, m2, 50);
  perform pg_temp.check(n = 2, 'after an id: only the newer ones');
  select count(*) into n from pg_temp.chat_messages(g1, null, 1);
  perform pg_temp.check(n = 1, 'limited');

  -- markReadSql: the marker moves to the newest and never back.
  perform pg_temp.chat_mark_read(u1, t0 + interval '5 minutes');
  perform pg_temp.check(
    (select unread from pg_temp.chat_head(u1)) = 0,
    'after reading, nothing is unread');
  update chat.h2h_reads set last_read_id = 0 where user_id = u1;
  perform pg_temp.chat_mark_read(u1, t0 + interval '6 minutes');
  perform pg_temp.chat_mark_read(u1, t0 + interval '7 minutes');
  select count(*) into n from chat.h2h_reads where user_id = u1;
  perform pg_temp.check(n = 1, 'one marker per player and group');

  -- Hidden messages are left out of the page.
  update chat.h2h_messages set hidden_at = now() where id = m1;
  select count(*) into n from pg_temp.chat_messages(g1, null, 50);
  perform pg_temp.check(n = 3, 'a hidden message is not listed');

  -- A newer month: the caller's group is the newest he sits in.
  insert into gamification.h2h_months (month_start, seated_count)
  values ('2099-12-01', 1);
  insert into gamification.h2h_leagues
    (id, month_start, division, group_index, capacity)
  values (g3, '2099-12-01', 1, 0, 20);
  insert into gamification.h2h_league_members
    (league_id, month_start, user_id, slot)
  values (g3, '2099-12-01', u1, 0);
  perform pg_temp.check(
    (select league_id from pg_temp.chat_head(u1)) = g3::text,
    'the newest month is his group');
  select count(*) into n from pg_temp.chat_send(u1, 'new group', t0 + interval '1 day');
  perform pg_temp.check(n = 1, 'a send goes to the newest group');
  select count(*) into n from chat.h2h_messages where league_id = g3;
  perform pg_temp.check(n = 1, 'and lands there');
  perform pg_temp.check(
    (select league_id from pg_temp.chat_head(u2)) = g1::text,
    'a player not seated again keeps the old group');
end $$;

rollback;
