-- ============================================================================
-- Migration 0077: the champion of a monthly contest
--
-- ADDITIVE ONLY. One new table; nothing existing is altered or deleted.
--
-- When a month has ended and its results are in, an admin crowns its
-- champion from the final board: the player ranked first, or -- when two
-- players are level on every tie-break -- both of them. The admin decides;
-- the server only allows players who are first on the final board.
--
--   season_id / user_id    the month and its champion (one row each, two at
--                          most per month)
--   points .. referral     the final figures, frozen as they stood when the
--                          month was crowned
--   crowned_at / by        when and by which admin; every row of one month
--                          carries the same instant, so a month is crowned
--                          once
--   photo_*                the picture the admin chose for the celebration,
--                          stored inline like the avatars of 0033 (512 KB,
--                          JPEG / PNG / WEBP). Optional: the app falls back
--                          to the player's own avatar, then to initials.
--
-- A crowning is a record: rows are never deleted, and after the insert only
-- the picture may change (a wrong picture can be replaced; a wrong champion
-- cannot be edited away). The triggers below are the backstop for rules the
-- server already enforces.
--
-- Server-only, like 0070. Forward-only. Safe to re-run.
-- ============================================================================

begin;

create table if not exists competition.month_champions (
  season_id        uuid        not null
    references competition.seasons (id) on delete restrict,
  user_id          uuid        not null
    references identity.users (id) on delete restrict,
  points           integer     not null,
  exact_count      integer     not null,
  decided_count    integer     not null,
  referral_points  integer     not null default 0,
  crowned_at       timestamptz not null default now(),
  crowned_by       uuid        not null
    references identity.users (id) on delete restrict,
  photo_bytes      bytea,
  photo_mime       text,
  photo_updated_at timestamptz,
  constraint month_champions_pkey primary key (season_id, user_id),
  constraint month_champions_counts_check
    check (
      points >= 0
      and exact_count >= 0
      and decided_count >= exact_count
      and referral_points >= 0
    ),
  constraint month_champions_photo_consistent
    check (
      (photo_bytes is null
        and photo_mime is null
        and photo_updated_at is null)
      or (photo_bytes is not null
        and photo_mime in ('image/jpeg', 'image/png', 'image/webp')
        and photo_updated_at is not null
        and octet_length(photo_bytes) between 1 and 524288)
    )
);

comment on table competition.month_champions is
  'The crowned champion(s) of a monthly contest: at most two per month, '
  'crowned once by an admin from the final board. Written by '
  'POST /admin/champions/{seasonId}; the picture by '
  'PUT /admin/champions/{seasonId}/photos/{userId}. Read by GET /champions.';

create index if not exists month_champions_crowned_idx
  on competition.month_champions (crowned_at desc);

-- A month is crowned once, with one or two champions who played it.
create or replace function competition.month_champions_guard_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from competition.participants p
    where p.season_id = new.season_id and p.user_id = new.user_id
  ) then
    raise exception 'month_champions: the champion did not play this month'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from competition.month_champions c
    where c.season_id = new.season_id and c.crowned_at <> new.crowned_at
  ) then
    raise exception 'month_champions: this month is already crowned'
      using errcode = 'check_violation';
  end if;
  if (
    select count(*) from competition.month_champions c
    where c.season_id = new.season_id
  ) >= 2 then
    raise exception 'month_champions: at most two champions per month'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;

-- After the crowning only the picture may change; nothing is deleted.
create or replace function competition.month_champions_guard_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'month_champions: a crowning is never deleted'
      using errcode = 'check_violation';
  end if;
  if (new.season_id, new.user_id, new.points, new.exact_count,
      new.decided_count, new.referral_points, new.crowned_at,
      new.crowned_by)
     is distinct from
     (old.season_id, old.user_id, old.points, old.exact_count,
      old.decided_count, old.referral_points, old.crowned_at,
      old.crowned_by) then
    raise exception 'month_champions: only the picture may change'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;

drop trigger if exists month_champions_guard_insert
  on competition.month_champions;
create trigger month_champions_guard_insert
  before insert on competition.month_champions
  for each row execute function competition.month_champions_guard_insert();

drop trigger if exists month_champions_guard_change
  on competition.month_champions;
create trigger month_champions_guard_change
  before update or delete on competition.month_champions
  for each row execute function competition.month_champions_guard_change();

alter table competition.month_champions enable row level security;
revoke all on competition.month_champions from anon, authenticated;
revoke all on function competition.month_champions_guard_insert()
  from public, anon, authenticated;
revoke all on function competition.month_champions_guard_change()
  from public, anon, authenticated;

commit;
