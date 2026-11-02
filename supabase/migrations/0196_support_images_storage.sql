-- ============================================================================
-- Migration 0196: support pictures in Storage (script 199, review L-5)
--
-- ADDITIVE ONLY. One private bucket, one nullable column, two checks
-- widened. No row is written, changed or removed by the migration; the
-- server moves the pictures afterwards, each cleared from the row only once
-- Storage holds it.
--
-- Why: the support chat kept its pictures in support.messages (0188), in the
-- database the free plan caps at 500 MB. Decided by the owner on 2026-11-02:
-- move them to Storage now, not when the database fills.
--
-- * storage.buckets: support-images, private (the server reads and answers
--   every picture itself, checking whose it is), 512 KB, JPEG/PNG/WEBP.
-- * support.messages.image_path: the picture's path in that bucket.
-- * messages_image_check: a picture is its bytes (as before) or its path,
--   never both; messages_body_check: a picture by path counts as content.
--
-- Apply BEFORE pushing the server that writes image_path. Safe to re-run.
-- ============================================================================

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('support-images', 'support-images', false, 524288,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

alter table support.messages
  add column if not exists image_path text;

alter table support.messages
  drop constraint if exists messages_image_check;
alter table support.messages
  add constraint messages_image_check
    check (
      (image_bytes is null and image_path is null and image_mime is null)
      or (image_bytes is not null
          and image_path is null
          and octet_length(image_bytes) between 1 and 524288
          and image_mime in ('image/jpeg', 'image/png', 'image/webp'))
      or (image_bytes is null
          and image_path is not null
          and length(image_path) between 1 and 300
          and image_mime in ('image/jpeg', 'image/png', 'image/webp'))
    );

alter table support.messages
  drop constraint if exists messages_body_check;
alter table support.messages
  add constraint messages_body_check
    check (
      length(body) <= 2000
      and body = btrim(body)
      and (length(body) >= 1 or image_bytes is not null
           or image_path is not null)
    );

comment on column support.messages.image_path is
  'The picture''s path in the private Storage bucket support-images (0196); '
  'null for text, or for a picture still kept in image_bytes.';

insert into ops.applied_migrations (version)
values ('0196_support_images_storage')
on conflict (version) do nothing;

commit;
