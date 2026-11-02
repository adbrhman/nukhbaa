-- End-to-end test for migration 0196: the private bucket; a picture by
-- path is a message; bytes and a path together are refused; the move's
-- update (PostgresSupportChatRepository.movedImageSql) turns bytes into a
-- path; the readers find a picture either way. Rolled back at the end.
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

create function pg_temp.refused(stmt text) returns boolean
language plpgsql as $$
begin
  execute stmt;
  return false;
exception when check_violation then
  return true;
end $$;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-4000-8196-000000000001', 'p-196@t.io', now());
insert into identity.users (id, email, display_name, created_at) values
  ('00000000-0000-4000-8196-000000000001', 'p-196@t.io', 'P 196', now());
insert into support.conversations (id, player_id, created_at, updated_at) values
  ('c1960000-0000-4000-8000-000000000001', '00000000-0000-4000-8196-000000000001',
   now(), now());

select pg_temp.check(
  (select not public and file_size_limit = 524288 from storage.buckets
    where id = 'support-images'),
  'the bucket support-images is private, 512 KB');

insert into support.messages
  (conversation_id, sender_id, sender_role, body, image_path, image_mime, created_at)
values ('c1960000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8196-000000000001', 'player', '',
        'p/00000000-0000-4000-8196-000000000001/ab.jpg', 'image/jpeg', now());
select pg_temp.check(
  (select count(*) = 1 from support.messages
    where conversation_id = 'c1960000-0000-4000-8000-000000000001'
      and image_path is not null and image_bytes is null),
  'a picture by path, with no text, is a message');

select pg_temp.check(pg_temp.refused($s$
  insert into support.messages
    (conversation_id, sender_id, sender_role, body, image_bytes, image_path,
     image_mime, created_at)
  values ('c1960000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8196-000000000001', 'player', '',
          '\xffd8ff'::bytea, 'p/x.jpg', 'image/jpeg', now())
$s$), 'bytes and a path together are refused');

select pg_temp.check(pg_temp.refused($s$
  insert into support.messages
    (conversation_id, sender_id, sender_role, body, image_path, image_mime,
     created_at)
  values ('c1960000-0000-4000-8000-000000000001',
          '00000000-0000-4000-8196-000000000001', 'player', '',
          'p/x.gif', 'image/gif', now())
$s$), 'a path with another type is refused');

-- A picture kept in the row (0188), then moved by the server.
insert into support.messages
  (conversation_id, sender_id, sender_role, body, image_bytes, image_mime, created_at)
values ('c1960000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8196-000000000001', 'player', '',
        '\xffd8ffe0'::bytea, 'image/jpeg', now());

create temp table kept as
SELECT m.id, m.conversation_id::text AS conversation_id, m.image_bytes,
       m.image_mime
FROM support.messages m
WHERE m.image_bytes IS NOT NULL
ORDER BY m.id
LIMIT 20;
select pg_temp.check((select count(*) = 1 from kept),
  'the move finds the one picture still kept in the database');

UPDATE support.messages
SET image_path = 'legacy/c1960000-0000-4000-8000-000000000001/' || (select id from kept) || '.jpg',
    image_bytes = NULL
WHERE id = (select id from kept) AND image_bytes IS NOT NULL;
select pg_temp.check(
  (select image_bytes is null and image_path like 'legacy/%' from support.messages
    where id = (select id from kept)),
  'the move turns the bytes into a path');

-- PostgresSupportChatRepository.playerImageSql.
select pg_temp.check(
  (select count(*) = 1 from (
     SELECT m.image_bytes, m.image_path, m.image_mime
     FROM support.messages m
     JOIN support.conversations c ON c.id = m.conversation_id
     WHERE m.id = (select id from kept)
       AND c.player_id = '00000000-0000-4000-8196-000000000001'::uuid
       AND (m.image_bytes IS NOT NULL OR m.image_path IS NOT NULL)) r),
  'the player reads a moved picture by its path');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0196_support_images_storage'),
  '0196 recorded in ops.applied_migrations');

rollback;
