-- ============================================================================
-- Migration 0204: pictures of the Elite Cup champions, and every crowning
-- picture erased with its account (scripts 238 and 239)
--
-- ADDITIVE, plus one function replaced (same name, arguments and result).
-- No existing row of a live account is written, changed or removed.
--
-- 1. gamification.h2h_cup_title_photos (new): the picture of the champion of
--    one path of the Elite Cup of one month (0190), added by an admin, like
--    the pictures of the month's champions (0077) and podium (0191). Optional:
--    a title without one shows the player's own avatar, then initials. The
--    picture may be replaced or removed; the title itself (append-only,
--    0190) is never touched, and only the champion of a title can have one.
--
-- 2. identity.delete_account (0203's function) now also erases, for the
--    deleted account: the picture of its crowning as month champion
--    (competition.month_champions), as podium place (competition.month_podium)
--    and as Elite Cup champion (the new table). The crowning record itself
--    stays, as a record without a name. Why: a crowning picture is a photo of
--    the player, shown to every player; Google Play's account-deletion policy
--    asks for the data tied to a deleted account to be deleted
--    (support.google.com/googleplay/android-developer/answer/13327111).
--    Until now these pictures stayed after a deletion.
--
-- 3. Once: the same pictures of accounts ALREADY deleted.
--
-- Apply before deploying the server of script 239. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The pictures of the Elite Cup champions
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_cup_title_photos (
  month_start      date     not null,
  place            smallint not null,
  user_id          uuid     not null
    constraint h2h_cup_title_photos_user_fkey
      references identity.users (id),
  photo_bytes      bytea    not null,
  photo_mime       text     not null,
  photo_updated_at timestamptz not null default now(),
  constraint h2h_cup_title_photos_pkey primary key (month_start, place),
  constraint h2h_cup_title_photos_title_fkey
    foreign key (month_start, place)
    references gamification.h2h_cup_titles (month_start, place),
  constraint h2h_cup_title_photos_mime_check
    check (photo_mime in ('image/jpeg', 'image/png', 'image/webp')),
  constraint h2h_cup_title_photos_size_check
    check (octet_length(photo_bytes) between 1 and 524288)
);

comment on table gamification.h2h_cup_title_photos is
  'The picture of the champion of one Elite Cup path of one month (0204), '
  'added by an admin like the month champions'' (0077). Optional, replaceable '
  'and removable; erased with the champion''s account. Server-only.';

create or replace function gamification.h2h_cup_title_photos_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from gamification.h2h_cup_titles t
       where t.month_start = new.month_start
         and t.place = new.place
         and t.champion = new.user_id
    ) then
      raise exception
        'h2h_cup_title_photos: only the champion of a title has a picture'
        using errcode = 'check_violation',
              constraint = 'h2h_cup_title_photos_champion';
    end if;
    return new;
  end if;
  if (new.month_start, new.place, new.user_id)
     is distinct from (old.month_start, old.place, old.user_id) then
    raise exception 'h2h_cup_title_photos: only the picture may change'
      using errcode = 'check_violation',
            constraint = 'h2h_cup_title_photos_frozen';
  end if;
  return new;
end
$$;

drop trigger if exists h2h_cup_title_photos_guard
  on gamification.h2h_cup_title_photos;
create trigger h2h_cup_title_photos_guard
  before insert or update on gamification.h2h_cup_title_photos
  for each row execute function gamification.h2h_cup_title_photos_guard();

alter table gamification.h2h_cup_title_photos enable row level security;
revoke all on gamification.h2h_cup_title_photos from anon, authenticated;
revoke all on function gamification.h2h_cup_title_photos_guard()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. delete_account: 0203's function, plus every crowning picture
-- ---------------------------------------------------------------------------
create or replace function identity.delete_account(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update identity.users u
     set status = 'suspended',
         deleted_at = now(),
         email = null,
         display_name = null,
         avatar_bytes = null,
         avatar_mime = null,
         avatar_updated_at = null
   where u.id = p_user_id
     and u.deleted_at is null
     and u.role = 'user';
  if not found then
    return false;
  end if;
  delete from notification.device_tokens where user_id = p_user_id;
  delete from notification.device_token_owners where user_id = p_user_id;
  delete from notification.notification_preferences where user_id = p_user_id;
  delete from identity.user_favorite_teams where user_id = p_user_id;
  delete from identity.install_accounts where user_id = p_user_id;
  delete from gamification.referral_install_marks where user_id = p_user_id;
  delete from gamification.referrals
   where invitee_id = p_user_id or referrer_id = p_user_id;
  delete from gamification.referral_codes where user_id = p_user_id;
  -- The pictures of his crownings (0077, 0191, 0204); the records stay.
  update competition.month_champions
     set photo_bytes = null, photo_mime = null, photo_updated_at = null
   where user_id = p_user_id and photo_bytes is not null;
  update competition.month_podium
     set photo_bytes = null, photo_mime = null, photo_updated_at = null
   where user_id = p_user_id and photo_bytes is not null;
  delete from gamification.h2h_cup_title_photos where user_id = p_user_id;
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
  delete from auth.identities where user_id = p_user_id;
  update auth.users
     set email = null,
         phone = null,
         raw_user_meta_data = '{}'::jsonb,
         banned_until = timestamptz '2999-12-31 00:00:00+00',
         updated_at = now()
   where id = p_user_id;
  return true;
end;
$$;

comment on function identity.delete_account(uuid) is
  'A player deletes his own account (0178, audit M-05; 0202 adds the links '
  'to the phones he used; 0203 the invitation rows; 0204 the pictures of his '
  'crownings): suspended for good, e-mail, name, picture, push tokens, phone '
  'links, invitation rows, crowning pictures and sign-in erased, points and '
  'predictions kept. True when deleted now.';

revoke all on function identity.delete_account(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Once: the crowning pictures of accounts deleted before this migration
-- ---------------------------------------------------------------------------
update competition.month_champions c
   set photo_bytes = null, photo_mime = null, photo_updated_at = null
  from identity.users u
 where u.id = c.user_id and u.deleted_at is not null
   and c.photo_bytes is not null;

update competition.month_podium p
   set photo_bytes = null, photo_mime = null, photo_updated_at = null
  from identity.users u
 where u.id = p.user_id and u.deleted_at is not null
   and p.photo_bytes is not null;

insert into ops.applied_migrations (version)
values ('0204_cup_champion_photos_and_erasure')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
--  select version from ops.applied_migrations
--   where version = '0204_cup_champion_photos_and_erasure';          -- 1 row
--  select count(*) from competition.month_champions c
--   join identity.users u on u.id = c.user_id
--  where u.deleted_at is not null and c.photo_bytes is not null;     -- 0
--  select count(*) from competition.month_podium p
--   join identity.users u on u.id = p.user_id
--  where u.deleted_at is not null and p.photo_bytes is not null;     -- 0
--  select to_regclass('gamification.h2h_cup_title_photos');          -- the table
