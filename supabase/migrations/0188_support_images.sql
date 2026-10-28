-- ============================================================================
-- Migration 0188: pictures in the support chat (script 168, 2026-10-28)
--
-- A player can send support a screenshot of a problem, and an admin can
-- answer with one. The picture lives in the message row, as the avatars do
-- (0033): at this size a storage bucket would cost a secret, an adapter and
-- an outbound call for no gain, and the server serves the bytes behind the
-- same sign-in as every other read.
--
--   support.messages.image_bytes  the picture, 1 byte to 512 KB
--   support.messages.image_mime   image/jpeg, image/png or image/webp
--
-- Both set or both null. A message with a picture may have no text: the
-- body check now allows an empty body when a picture is there (it stays
-- trimmed and at most 2000 characters).
--
-- The server checks size, type and the file's own signature before
-- storing; these checks are the backstop. A deleted account's pictures go
-- with its conversation (0187's trigger, on delete cascade).
--
-- ADDITIVE: two nullable columns; one check is replaced by a wider one.
-- No row is touched. Safe to re-run.
-- ============================================================================

begin;

alter table support.messages
  add column if not exists image_bytes bytea,
  add column if not exists image_mime  text;

alter table support.messages
  drop constraint if exists messages_image_check;
alter table support.messages
  add constraint messages_image_check
    check (
      (image_bytes is null and image_mime is null)
      or (image_bytes is not null
          and octet_length(image_bytes) between 1 and 524288
          and image_mime in ('image/jpeg', 'image/png', 'image/webp'))
    );

alter table support.messages
  drop constraint if exists messages_body_check;
alter table support.messages
  add constraint messages_body_check
    check (
      length(body) <= 2000
      and body = btrim(body)
      and (length(body) >= 1 or image_bytes is not null)
    );

comment on column support.messages.image_bytes is
  'A picture sent with the message (0188), at most 512 KB; null for text.';

insert into ops.applied_migrations (version)
values ('0188_support_images')
on conflict (version) do nothing;

commit;
