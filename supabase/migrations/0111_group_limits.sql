-- ============================================================================
-- Migration 0111: a friends' league holds 50 members, a weekly league group
-- never takes more than its capacity (audit M-26, L-45)
--
-- ADDITIVE ONLY. Two trigger functions and two triggers. No row of any
-- table is written, changed or removed; leagues and groups already over the
-- limit keep everyone they have and take no one new.
--
-- 1. group.group_memberships: a new membership is refused when its league
--    already has 50 members (check_violation, constraint
--    group_memberships_capacity). JoinGroupByInvite checks first and says so
--    in Arabic (group.full); this is the backstop for two joins at once,
--    serialised by locking the league row.
-- 2. gamification.weekly_league_members: a new seat is refused when its
--    group already holds its capacity (check_violation, constraint
--    weekly_league_members_capacity). The placement serialises itself per
--    week and tier (PostgresWeeklyLeagueRepository, batch 140), so this only
--    stops what slips past. A player who already has his seat this week is
--    left to the (week_start, user_id) unique constraint, so a re-placement
--    still reads his seat instead of failing.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function "group".reject_member_over_capacity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_members int;
begin
  perform 1 from "group".groups g where g.id = new.group_id for update;

  select count(*) into v_members
    from "group".group_memberships m
   where m.group_id = new.group_id;

  if v_members >= 50 then
    raise exception 'group % already has % members', new.group_id, v_members
      using errcode = 'check_violation',
            constraint = 'group_memberships_capacity';
  end if;
  return new;
end;
$$;

comment on function "group".reject_member_over_capacity() is
  'Refuses a 51st member of a friends'' league (0111, audit M-26).';

drop trigger if exists group_memberships_capacity
  on "group".group_memberships;
create trigger group_memberships_capacity
  before insert on "group".group_memberships
  for each row execute function "group".reject_member_over_capacity();

create or replace function gamification.reject_seat_over_capacity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_capacity smallint;
  v_seated   int;
begin
  if exists (
    select 1
      from gamification.weekly_league_members m
     where m.week_start = new.week_start
       and m.user_id = new.user_id
  ) then
    return new;
  end if;

  select l.capacity into v_capacity
    from gamification.weekly_leagues l
   where l.id = new.league_id
     for update;

  select count(*) into v_seated
    from gamification.weekly_league_members m
   where m.league_id = new.league_id;

  if v_capacity is not null and v_seated >= v_capacity then
    raise exception 'weekly league % is full (% of %)',
      new.league_id, v_seated, v_capacity
      using errcode = 'check_violation',
            constraint = 'weekly_league_members_capacity';
  end if;
  return new;
end;
$$;

comment on function gamification.reject_seat_over_capacity() is
  'Refuses a seat in a weekly league group already at its capacity (0111, '
  'audit L-45).';

drop trigger if exists weekly_league_members_capacity
  on gamification.weekly_league_members;
create trigger weekly_league_members_capacity
  before insert on gamification.weekly_league_members
  for each row execute function gamification.reject_seat_over_capacity();

insert into ops.applied_migrations (version)
values ('0111_group_limits')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0111_group_limits';                            -- 1 row
-- select tgname from pg_trigger
--  where tgname in ('group_memberships_capacity',
--                   'weekly_league_members_capacity');               -- 2 rows
