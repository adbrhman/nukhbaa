-- ============================================================================
-- Migration 0191: the podium of a crowned month (second and third places)
--
-- ADDITIVE ONLY. One new table in `competition`. Nothing is changed or
-- deleted; month_champions (0077, 0078) stays exactly as it is.
--
-- ## The rule (decided by the owner on 2026-11-01, script 186)
-- Once a month is crowned, the admin fixes its podium: the first two
-- players of the final board after the champion(s), in the board's own
-- order (prediction points, invitation points, exact scorelines, right
-- outcomes, the earlier join), become the second and third places. Their
-- figures are frozen as they stood; only their celebration picture may
-- change afterwards. Only the champion wins the prize; the podium carries
-- none. Allowed for every crowned month, October 2026 included.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

create table if not exists competition.month_podium (
  season_id        uuid     not null
    constraint month_podium_season_fkey
      references competition.seasons (id),
  place            smallint not null,
  user_id          uuid     not null
    constraint month_podium_user_fkey
      references identity.users (id),
  points           integer  not null,
  exact_count      integer  not null,
  decided_count    integer  not null,
  set_at           timestamptz not null default now(),
  set_by           uuid     not null
    constraint month_podium_set_by_fkey
      references identity.users (id),
  photo_bytes      bytea,
  photo_mime       text,
  photo_updated_at timestamptz,
  constraint month_podium_pkey primary key (season_id, place),
  constraint month_podium_user_uniq unique (season_id, user_id),
  constraint month_podium_place_range check (place between 2 and 3),
  constraint month_podium_counts_check
    check (points >= 0 and exact_count >= 0 and decided_count >= 0),
  constraint month_podium_photo_consistent
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

comment on table competition.month_podium is
  'The second and third places of a crowned month (0191), from its final '
  'board, with their celebration pictures. Set once, after the crowning; '
  'only the picture may change. Read by GET /champions.';

-- A podium only for a crowned month, never its champion, a player of it.
create or replace function competition.month_podium_guard_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from competition.month_champions c
    where c.season_id = new.season_id
  ) then
    raise exception 'month_podium: the month is not crowned'
      using errcode = 'check_violation',
            constraint = 'month_podium_after_crowning';
  end if;
  if exists (
    select 1 from competition.month_champions c
    where c.season_id = new.season_id and c.user_id = new.user_id
  ) then
    raise exception 'month_podium: a champion is not on the podium'
      using errcode = 'check_violation',
            constraint = 'month_podium_not_champion';
  end if;
  if not exists (
    select 1 from competition.participants p
    where p.season_id = new.season_id and p.user_id = new.user_id
  ) then
    raise exception 'month_podium: the player did not play this month'
      using errcode = 'check_violation',
            constraint = 'month_podium_played';
  end if;
  return new;
end
$$;

-- After it is set only the picture may change; nothing is deleted.
create or replace function competition.month_podium_guard_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'month_podium: a podium is never deleted'
      using errcode = 'check_violation';
  end if;
  if (new.season_id, new.place, new.user_id, new.points, new.exact_count,
      new.decided_count, new.set_at, new.set_by)
     is distinct from
     (old.season_id, old.place, old.user_id, old.points, old.exact_count,
      old.decided_count, old.set_at, old.set_by) then
    raise exception 'month_podium: only the picture may change'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;

drop trigger if exists month_podium_guard_insert on competition.month_podium;
create trigger month_podium_guard_insert
  before insert on competition.month_podium
  for each row execute function competition.month_podium_guard_insert();

drop trigger if exists month_podium_guard_change on competition.month_podium;
create trigger month_podium_guard_change
  before update or delete on competition.month_podium
  for each row execute function competition.month_podium_guard_change();

alter table competition.month_podium enable row level security;
revoke all on competition.month_podium from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0191_month_podium')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0191_month_podium';                            -- 1 row
-- select relrowsecurity from pg_class
--  where oid = 'competition.month_podium'::regclass;               -- true
