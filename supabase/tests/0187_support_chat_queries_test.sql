-- End-to-end test of PostgresSupportChatRepository's statements (migrations
-- 0187 and 0188, scripts 165 and 168), each body identical to the adapter's constant
-- (parameters inlined as function arguments): a player's first message
-- opens his one conversation, the unread counters of both sides, the
-- admins' inbox (order, filters, name search), reads, pages, closing and
-- reopening, the player's phones, pictures (stored, read only within their
-- conversation, the checks behind them), and a deleted account taking its
-- conversation with it. Rolled back at the end.
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

-- ensureSql
create function pg_temp.ensure_conversation(p_player_id uuid, p_at timestamptz)
returns void
language sql as $q$
INSERT INTO support.conversations (player_id, created_at, updated_at)
VALUES (p_player_id::uuid, p_at::timestamptz, p_at::timestamptz)
ON CONFLICT (player_id) DO NOTHING
$q$;

-- playerMessageSql
create function pg_temp.player_message(p_player_id uuid, p_body text, p_preview text, p_image_bytes bytea, p_image_mime text, p_at timestamptz)
returns table (id bigint, conversation_id text, created_at timestamptz, unread_before bigint, player_name text)
language sql as $q$
WITH conv AS (
  SELECT c.id, c.support_unread
  FROM support.conversations c
  WHERE c.player_id = p_player_id::uuid
  FOR UPDATE
), msg AS (
  INSERT INTO support.messages (
    conversation_id, sender_id, sender_role, body,
    image_bytes, image_mime, created_at
  )
  SELECT conv.id, p_player_id::uuid, 'player', p_body::text,
         p_image_bytes::bytea, p_image_mime::text, p_at::timestamptz
  FROM conv
  RETURNING id, conversation_id, created_at
), touched AS (
  UPDATE support.conversations c
  SET support_unread = c.support_unread + 1,
      status = 'open',
      last_message_at = msg.created_at,
      last_message_preview = p_preview::text,
      last_sender_role = 'player',
      updated_at = msg.created_at
  FROM msg
  WHERE c.id = msg.conversation_id
  RETURNING c.id
)
SELECT msg.id,
       msg.conversation_id::text AS conversation_id,
       msg.created_at,
       conv.support_unread::bigint AS unread_before,
       coalesce(u.display_name, '') AS player_name
FROM msg
JOIN conv ON conv.id = msg.conversation_id
JOIN identity.users u ON u.id = p_player_id::uuid
$q$;

-- supportReplySql
create function pg_temp.support_reply(p_conversation_id uuid, p_admin_id uuid, p_body text, p_preview text, p_image_bytes bytea, p_image_mime text, p_at timestamptz)
returns table (id bigint, conversation_id text, created_at timestamptz, unread_before bigint, player_name text)
language sql as $q$
WITH conv AS (
  SELECT c.id, c.player_id, c.player_unread
  FROM support.conversations c
  WHERE c.id = p_conversation_id::uuid
  FOR UPDATE
), msg AS (
  INSERT INTO support.messages (
    conversation_id, sender_id, sender_role, body,
    image_bytes, image_mime, created_at
  )
  SELECT conv.id, p_admin_id::uuid, 'support', p_body::text,
         p_image_bytes::bytea, p_image_mime::text, p_at::timestamptz
  FROM conv
  RETURNING id, conversation_id, created_at
), touched AS (
  UPDATE support.conversations c
  SET player_unread = c.player_unread + 1,
      last_message_at = msg.created_at,
      last_message_preview = p_preview::text,
      last_sender_role = 'support',
      updated_at = msg.created_at
  FROM msg
  WHERE c.id = msg.conversation_id
  RETURNING c.id
)
SELECT msg.id,
       msg.conversation_id::text AS conversation_id,
       msg.created_at,
       conv.player_unread::bigint AS unread_before,
       coalesce(u.display_name, '') AS player_name
FROM msg
JOIN conv ON conv.id = msg.conversation_id
JOIN identity.users u ON u.id = conv.player_id
$q$;

-- playerHeadSql
create function pg_temp.player_head(p_player_id uuid)
returns table (id text, status text, unread bigint)
language sql as $q$
SELECT c.id::text AS id, c.status, c.player_unread::bigint AS unread
FROM support.conversations c
WHERE c.player_id = p_player_id::uuid
$q$;

-- messagesSql
create function pg_temp.messages(p_conversation_id uuid, p_before bigint, p_limit int)
returns table (id bigint, sender_role text, body text, created_at timestamptz, read_at timestamptz, has_image boolean)
language sql as $q$
SELECT m.id, m.sender_role, m.body, m.created_at, m.read_at,
       m.image_bytes IS NOT NULL AS has_image
FROM support.messages m
WHERE m.conversation_id = p_conversation_id::uuid
  AND (p_before::bigint IS NULL OR m.id < p_before::bigint)
ORDER BY m.id DESC
LIMIT p_limit::int
$q$;

-- conversationSql
create function pg_temp.conversation(p_conversation_id uuid)
returns table (id text, player_id text, player_name text, status text, last_message_at timestamptz, last_message_preview text, last_sender_role text, support_unread bigint, player_unread bigint)
language sql as $q$
SELECT c.id::text AS id,
       c.player_id::text AS player_id,
       coalesce(u.display_name, '') AS player_name,
       c.status,
       coalesce(c.last_message_at, c.created_at) AS last_message_at,
       coalesce(c.last_message_preview, '') AS last_message_preview,
       coalesce(c.last_sender_role, 'player') AS last_sender_role,
       c.support_unread::bigint AS support_unread,
       c.player_unread::bigint AS player_unread
FROM support.conversations c
JOIN identity.users u ON u.id = c.player_id
WHERE c.id = p_conversation_id::uuid
$q$;

-- inboxSql
create function pg_temp.inbox(p_filter text, p_search text, p_limit int)
returns table (id text, player_id text, player_name text, status text, last_message_at timestamptz, last_message_preview text, last_sender_role text, support_unread bigint, player_unread bigint)
language sql as $q$
SELECT c.id::text AS id,
       c.player_id::text AS player_id,
       coalesce(u.display_name, '') AS player_name,
       c.status,
       coalesce(c.last_message_at, c.created_at) AS last_message_at,
       coalesce(c.last_message_preview, '') AS last_message_preview,
       coalesce(c.last_sender_role, 'player') AS last_sender_role,
       c.support_unread::bigint AS support_unread,
       c.player_unread::bigint AS player_unread
FROM support.conversations c
JOIN identity.users u ON u.id = c.player_id
WHERE c.last_message_at IS NOT NULL
  AND CASE p_filter::text
        WHEN 'unread' THEN c.support_unread > 0
        WHEN 'open' THEN c.status = 'open'
        WHEN 'closed' THEN c.status IN ('closed', 'archived')
        ELSE true
      END
  AND (p_search::text = ''
       OR strpos(lower(coalesce(u.display_name, '')),
                 lower(p_search::text)) > 0)
ORDER BY c.last_message_at DESC, c.id
LIMIT p_limit::int
$q$;

-- unreadConversationsSql
create function pg_temp.unread_conversations()
returns table (unread bigint)
language sql as $q$
SELECT count(*)::bigint AS unread
FROM support.conversations c
WHERE c.support_unread > 0
$q$;

-- markReadByPlayerSql
create function pg_temp.mark_read_by_player(p_player_id uuid, p_at timestamptz)
returns table (marked bigint, found bigint)
language sql as $q$
WITH conv AS (
  SELECT c.id
  FROM support.conversations c
  WHERE c.player_id = p_player_id::uuid
  FOR UPDATE
), marked AS (
  UPDATE support.messages m
  SET read_at = p_at::timestamptz
  FROM conv
  WHERE m.conversation_id = conv.id
    AND m.sender_role = 'support'
    AND m.read_at IS NULL
  RETURNING m.id
), reset AS (
  UPDATE support.conversations c
  SET player_unread = 0
  FROM conv
  WHERE c.id = conv.id AND c.player_unread <> 0
  RETURNING c.id
)
SELECT (SELECT count(*) FROM marked)::bigint AS marked,
       (SELECT count(*) FROM conv)::bigint AS found
$q$;

-- markReadBySupportSql
create function pg_temp.mark_read_by_support(p_conversation_id uuid, p_at timestamptz)
returns table (marked bigint, found bigint)
language sql as $q$
WITH conv AS (
  SELECT c.id
  FROM support.conversations c
  WHERE c.id = p_conversation_id::uuid
  FOR UPDATE
), marked AS (
  UPDATE support.messages m
  SET read_at = p_at::timestamptz
  FROM conv
  WHERE m.conversation_id = conv.id
    AND m.sender_role = 'player'
    AND m.read_at IS NULL
  RETURNING m.id
), reset AS (
  UPDATE support.conversations c
  SET support_unread = 0
  FROM conv
  WHERE c.id = conv.id AND c.support_unread <> 0
  RETURNING c.id
)
SELECT (SELECT count(*) FROM marked)::bigint AS marked,
       (SELECT count(*) FROM conv)::bigint AS found
$q$;

-- playerUnreadSql
create function pg_temp.player_unread(p_player_id uuid)
returns table (unread bigint)
language sql as $q$
SELECT coalesce((
  SELECT c.player_unread
  FROM support.conversations c
  WHERE c.player_id = p_player_id::uuid
), 0)::bigint AS unread
$q$;

-- setStatusSql
create function pg_temp.set_status(p_conversation_id uuid, p_status text, p_at timestamptz)
returns table (id text)
language sql as $q$
UPDATE support.conversations c
SET status = p_status::text, updated_at = p_at::timestamptz
WHERE c.id = p_conversation_id::uuid
RETURNING c.id::text AS id
$q$;

-- playerTokensSql
create function pg_temp.player_tokens(p_conversation_id uuid)
returns table (token text)
language sql as $q$
SELECT dt.token
FROM support.conversations c
JOIN identity.users u ON u.id = c.player_id
JOIN notification.device_tokens dt ON dt.user_id = u.id
WHERE c.id = p_conversation_id::uuid
  AND u.status = 'active'
ORDER BY dt.token
$q$;

-- playerImageSql
create function pg_temp.player_image(p_message_id bigint, p_player_id uuid)
returns table (image_bytes bytea, image_mime text)
language sql as $q$
SELECT m.image_bytes, m.image_mime
FROM support.messages m
JOIN support.conversations c ON c.id = m.conversation_id
WHERE m.id = p_message_id::bigint
  AND c.player_id = p_player_id::uuid
  AND m.image_bytes IS NOT NULL
$q$;

-- conversationImageSql
create function pg_temp.conversation_image(p_message_id bigint, p_conversation_id uuid)
returns table (image_bytes bytea, image_mime text)
language sql as $q$
SELECT m.image_bytes, m.image_mime
FROM support.messages m
WHERE m.id = p_message_id::bigint
  AND m.conversation_id = p_conversation_id::uuid
  AND m.image_bytes IS NOT NULL
$q$;

-- The adapter's transaction for a player's message: the conversation, then
-- the message.
create function pg_temp.send_player(p_player_id uuid, p_body text, p_at timestamptz)
returns table (id bigint, conversation_id text, created_at timestamptz,
               unread_before bigint, player_name text)
language plpgsql as $$
begin
  perform pg_temp.ensure_conversation(p_player_id, p_at);
  return query
    select * from pg_temp.player_message(p_player_id, p_body, left(p_body, 120), null, null, p_at);
end $$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8187-000000000001', 'sp1@t.io', now()),
  ('00000000-0000-4000-8187-000000000002', 'sp2@t.io', now()),
  ('00000000-0000-4000-8187-0000000000a1', 'sa1@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0000-4000-8187-000000000001', 'sp1@t.io', 'سامي الدعم', 'user'),
  ('00000000-0000-4000-8187-000000000002', 'sp2@t.io', 'خالد الدعم', 'user'),
  ('00000000-0000-4000-8187-0000000000a1', 'sa1@t.io', 'مشرف الدعم', 'admin');
insert into notification.device_tokens (token, user_id, platform) values
  ('support-test-token-1', '00000000-0000-4000-8187-000000000001', 'android');

do $$
declare
  p1 constant uuid := '00000000-0000-4000-8187-000000000001';
  p2 constant uuid := '00000000-0000-4000-8187-000000000002';
  adm constant uuid := '00000000-0000-4000-8187-0000000000a1';
  t0 constant timestamptz := '2026-10-28 10:00:00+00';
  r record;
  first_conv text;
  first_id bigint;
  n bigint;
begin
  -- A player who never wrote has no conversation and nothing unread.
  perform pg_temp.check(not exists (select 1 from pg_temp.player_head(p1)),
    'no conversation before the first message');
  perform pg_temp.check((select unread from pg_temp.player_unread(p1)) = 0,
    'nothing unread before the first message');

  -- His first message opens his one conversation.
  select * into r from pg_temp.send_player(p1, 'التطبيق لا يحفظ توقعي', t0);
  first_conv := r.conversation_id; first_id := r.id;
  perform pg_temp.check(r.unread_before = 0, 'the first message is the first waiting');
  perform pg_temp.check(r.player_name = 'سامي الدعم', 'it names the player');
  select * into r from pg_temp.send_player(p1, 'ما زالت المشكلة', t0 + interval '1 minute');
  perform pg_temp.check(r.conversation_id = first_conv, 'one conversation per player');
  perform pg_temp.check(r.unread_before = 1, 'the second waits behind the first');
  perform pg_temp.check(r.id > first_id, 'ids grow with time');
  perform pg_temp.check(
    (select count(*) from support.conversations c where c.player_id = p1) = 1,
    'a second message does not open a second conversation');

  select * into r from pg_temp.conversation(first_conv::uuid);
  perform pg_temp.check(r.support_unread = 2 and r.player_unread = 0,
    'two player messages wait for support');
  perform pg_temp.check(r.last_message_preview = 'ما زالت المشكلة'
    and r.last_sender_role = 'player' and r.status = 'open',
    'the inbox line is the last message');

  -- Another player cannot see it: his own reads are by his own id.
  perform pg_temp.check(not exists (select 1 from pg_temp.player_head(p2)),
    'another player has no conversation of his own');

  -- The inbox: newest first, filters and the name search.
  perform pg_temp.send_player(p2, 'سؤال عن النقاط', t0 + interval '2 minutes');
  perform pg_temp.check(
    (select array_agg(i.player_name) from pg_temp.inbox('all', '', 100) i)
      = array['خالد الدعم', 'سامي الدعم'],
    'the inbox lists the latest message first');
  perform pg_temp.check(
    (select count(*) from pg_temp.inbox('all', 'سامي', 100)) = 1,
    'the search finds a player by part of his name');
  perform pg_temp.check(
    (select count(*) from pg_temp.inbox('all', '%', 100)) = 0,
    'a percent sign is a letter, not a wildcard');
  perform pg_temp.check((select unread from pg_temp.unread_conversations()) = 2,
    'two conversations wait');

  -- Support reads, then answers.
  select * into r from pg_temp.mark_read_by_support(first_conv::uuid, t0 + interval '3 minutes');
  perform pg_temp.check(r.marked = 2 and r.found = 1, 'support reads both messages');
  perform pg_temp.check(
    (select support_unread from pg_temp.conversation(first_conv::uuid)) = 0,
    'nothing waits for support in that conversation');
  perform pg_temp.check(
    (select count(*) from pg_temp.inbox('unread', '', 100)) = 1,
    'the unread filter keeps only the other one');

  select * into r from pg_temp.support_reply(first_conv::uuid, adm, 'تم إصلاحها، حدّث التطبيق', 'تم إصلاحها، حدّث التطبيق', null, null, t0 + interval '4 minutes');
  perform pg_temp.check(r.unread_before = 0, 'the first answer is the first waiting for the player');
  perform pg_temp.check((select unread from pg_temp.player_unread(p1)) = 1,
    'the player has one answer to read');
  perform pg_temp.check(
    (select m.sender_role from pg_temp.messages(first_conv::uuid, null, 31) m order by m.id desc limit 1) = 'support',
    'the answer is support''s');
  perform pg_temp.check(
    (select sender_id from support.messages where id = r.id) = adm,
    'which admin answered is kept for the record');

  -- A reply to a conversation that is not on file writes nothing.
  perform pg_temp.check(not exists (
    select 1 from pg_temp.support_reply('00000000-0000-4000-8187-00000000ffff', adm, 'x', 'x', null, null, t0)),
    'no reply to a conversation not on file');
  select * into r from pg_temp.mark_read_by_support('00000000-0000-4000-8187-00000000ffff', t0);
  perform pg_temp.check(r.found = 0, 'mark read finds no such conversation');

  -- Pages: newest first, one more than the page says older ones are left.
  perform pg_temp.check((select count(*) from pg_temp.messages(first_conv::uuid, null, 2)) = 2,
    'a page holds at most its limit, newest first');
  perform pg_temp.check(
    (select count(*) from pg_temp.messages(first_conv::uuid, first_id + 1, 31)) = 1,
    'before an id reads only the older ones');

  -- The player reads the answer.
  select * into r from pg_temp.mark_read_by_player(p1, t0 + interval '5 minutes');
  perform pg_temp.check(r.marked = 1 and r.found = 1, 'the player reads the answer');
  perform pg_temp.check((select unread from pg_temp.player_unread(p1)) = 0,
    'nothing left to read');
  select * into r from pg_temp.mark_read_by_player(p1, t0 + interval '6 minutes');
  perform pg_temp.check(r.marked = 0, 'reading again marks nothing');
  select * into r from pg_temp.mark_read_by_player(p2, t0);
  perform pg_temp.check(r.marked = 0, 'support''s messages to someone else are not his to read');

  -- The player's phones, while his account is active.
  perform pg_temp.check(
    (select array_agg(token) from pg_temp.player_tokens(first_conv::uuid)) = array['support-test-token-1'],
    'the answer rings the player''s phone');

  -- Close; a new message from the player reopens it.
  perform pg_temp.check(exists (select 1 from pg_temp.set_status(first_conv::uuid, 'closed', t0 + interval '7 minutes')),
    'support closes the conversation');
  perform pg_temp.check((select count(*) from pg_temp.inbox('closed', '', 100)) = 1,
    'it is under closed');
  perform pg_temp.check(not exists (select 1 from pg_temp.set_status('00000000-0000-4000-8187-00000000ffff', 'closed', t0)),
    'no status for a conversation not on file');
  perform pg_temp.send_player(p1, 'عادت المشكلة', t0 + interval '8 minutes');
  perform pg_temp.check((select status from pg_temp.player_head(p1)) = 'open',
    'the player''s new message reopens it');

  -- The table refuses what the app never sends.
  begin
    insert into support.messages (conversation_id, sender_role, body)
    values (first_conv::uuid, 'player', '  ');
    perform pg_temp.check(false, 'a blank message is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'a blank message is refused');
  end;
  begin
    insert into support.messages (conversation_id, sender_role, body)
    values (first_conv::uuid, 'player', repeat('x', 2001));
    perform pg_temp.check(false, 'a message over 2000 characters is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'a message over 2000 characters is refused');
  end;

  -- Pictures (0188): a message of its own, no text, served only within
  -- its conversation.
  perform pg_temp.ensure_conversation(p1, t0);
  select * into r from pg_temp.player_message(p1, '', '📷 صورة',
    '\xffd8ffe000104a464946'::bytea, 'image/jpeg', t0 + interval '9 minutes');
  perform pg_temp.check(r.id is not null, 'a picture is stored with no text');
  perform pg_temp.check(
    (select m.has_image and m.body = '' from pg_temp.messages(first_conv::uuid, null, 1) m),
    'the page says a picture came with it');
  perform pg_temp.check(
    (select last_message_preview from pg_temp.conversation(first_conv::uuid)) = '📷 صورة',
    'the inbox line says it is a picture');
  perform pg_temp.check(
    (select image_mime from pg_temp.player_image(r.id, p1)) = 'image/jpeg',
    'the player reads his own picture');
  perform pg_temp.check(not exists (select 1 from pg_temp.player_image(r.id, p2)),
    'another player cannot read it');
  perform pg_temp.check(
    exists (select 1 from pg_temp.conversation_image(r.id, first_conv::uuid)),
    'support reads it in its conversation');
  perform pg_temp.check(
    not exists (select 1 from pg_temp.conversation_image(r.id,
      (select c.id from support.conversations c where c.player_id = p2))),
    'and not through another conversation');
  perform pg_temp.check(not exists (select 1 from pg_temp.player_image(first_id, p1)),
    'a text message has no picture');
  begin
    insert into support.messages (conversation_id, sender_role, body, image_bytes, image_mime)
    values (first_conv::uuid, 'player', '', '\x00'::bytea, 'image/gif');
    perform pg_temp.check(false, 'a picture of another type is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'a picture of another type is refused');
  end;
  begin
    insert into support.messages (conversation_id, sender_role, body)
    values (first_conv::uuid, 'player', '');
    perform pg_temp.check(false, 'no text and no picture is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'no text and no picture is refused');
  end;
  begin
    insert into support.messages (conversation_id, sender_role, body, image_bytes, image_mime)
    values (first_conv::uuid, 'player', '', decode(repeat('00', 524289), 'hex'), 'image/png');
    perform pg_temp.check(false, 'a picture over 512 KB is refused');
  exception when check_violation then
    perform pg_temp.check(true, 'a picture over 512 KB is refused');
  end;

  -- A suspended player is not rung.
  update identity.users set status = 'suspended' where id = p1;
  perform pg_temp.check(not exists (select 1 from pg_temp.player_tokens(first_conv::uuid)),
    'a suspended account''s phone is not rung');

  -- A deleted account (0178) takes its conversation with it.
  update identity.users set deleted_at = now(), email = null where id = p1;
  perform pg_temp.check(not exists (select 1 from support.conversations c where c.player_id = p1),
    'a deleted account''s conversation is gone');
  perform pg_temp.check(not exists (select 1 from support.messages m where m.conversation_id = first_conv::uuid),
    'with its messages');
  perform pg_temp.check(exists (select 1 from support.conversations c where c.player_id = p2),
    'and nobody else''s');

  -- The two new push links are accepted.
  insert into notification.push_opens (user_id, link) values (p2, 'support'), (p2, 'support_inbox');
  perform pg_temp.check(true, 'the support push links are accepted');
end $$;

rollback;
