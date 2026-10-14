-- End-to-end test of migration 0111 (a league holds 50 members; a weekly
-- league group never takes more than its capacity) and of the roster
-- statements of PostgresGroupRepository (parameters inlined as function
-- arguments; keep the bodies identical to the adapter's constants):
-- leaving, removal, deletion and the members of a month. Batch 140, audit
-- M-26, L-40, L-45.
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

-- Whether p_sql is refused by the named capacity constraint.
create function pg_temp.refused(p_sql text, p_constraint text) returns boolean
language plpgsql as $$
declare
  v_constraint text;
begin
  execute p_sql;
  return false;
exception when check_violation then
  get stacked diagnostics v_constraint = constraint_name;
  return v_constraint = p_constraint;
end $$;

-- PostgresGroupRepository._removeMembershipSql
create function pg_temp.remove_membership(p_group_id uuid, p_user_id uuid)
returns int
language sql as $q$
WITH gone AS (
  DELETE FROM "group".group_memberships
  WHERE group_id = p_group_id
    AND user_id = p_user_id
    AND role = 'member'
  RETURNING user_id
), invitation AS (
  DELETE FROM "group".group_invitations i
  USING gone
  WHERE i.group_id = p_group_id
    AND i.invitee_user_id = gone.user_id
)
SELECT count(*)::int AS removed FROM gone
$q$;

-- PostgresGroupRepository._deleteGroupSql
create function pg_temp.delete_group(p_group_id uuid)
returns int
language sql as $q$
WITH gone AS (
  DELETE FROM "group".groups
  WHERE id = p_group_id
  RETURNING id
)
SELECT count(*)::int AS deleted FROM gone
$q$;

-- PostgresGroupRepository._memberParticipantIdsSql
create function pg_temp.member_participant_ids(p_group_id uuid, p_season_id uuid)
returns setof text
language sql as $q$
SELECT p.id::text AS participant_id
FROM "group".group_memberships gm
JOIN competition.participants p
  ON p.user_id = gm.user_id
 AND p.season_id = p_season_id
WHERE gm.group_id = p_group_id
$q$;

-- 60 players, one league owned by the first.
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0111-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'p' || n || '@example.com', now()
  from generate_series(1, 60) n;
insert into identity.users (id, email, display_name)
select ('00000000-0111-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'p' || n || '@example.com', 'Player ' || n
  from generate_series(1, 60) n;

insert into "group".groups (id, owner_id, name, invite_code)
values ('00000000-0111-4000-8000-0000000000aa',
        '00000000-0111-4000-8000-000000000001', 'Friends', 'AAAAAAAAAA');

insert into "group".group_memberships (id, group_id, user_id, role)
select gen_random_uuid(), '00000000-0111-4000-8000-0000000000aa',
       ('00000000-0111-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       (case when n = 1 then 'owner' else 'member' end)::"group".group_role
  from generate_series(1, 50) n;

do $$
declare
  g uuid := '00000000-0111-4000-8000-0000000000aa';
  n int;
begin
  -- 1. The 51st member is refused.
  perform pg_temp.check(pg_temp.refused(format(
    'insert into "group".group_memberships (id, group_id, user_id) values (gen_random_uuid(), %L, %L)',
    g, '00000000-0111-4000-8000-000000000051'), 'group_memberships_capacity'),
    'a 51st member is refused');

  -- 2. A member leaves (his invitation goes with him); now one fits.
  insert into "group".group_invitations (id, group_id, inviter_user_id, invitee_user_id, status, responded_at)
  values (gen_random_uuid(), g, '00000000-0111-4000-8000-000000000001',
          '00000000-0111-4000-8000-000000000002', 'accepted', now());
  n := pg_temp.remove_membership(g, '00000000-0111-4000-8000-000000000002');
  perform pg_temp.check(n = 1, 'a member is removed');
  perform pg_temp.check(not exists (
    select 1 from "group".group_invitations
     where group_id = g and invitee_user_id = '00000000-0111-4000-8000-000000000002'),
    'his invitation goes with him');
  perform pg_temp.check(not pg_temp.refused(format(
    'insert into "group".group_memberships (id, group_id, user_id) values (gen_random_uuid(), %L, %L)',
    g, '00000000-0111-4000-8000-000000000051'), 'group_memberships_capacity'),
    'the freed place can be taken');

  -- 3. The owner row is never removed by the statement.
  n := pg_temp.remove_membership(g, '00000000-0111-4000-8000-000000000001');
  perform pg_temp.check(n = 0, 'the owner is not removed');
  n := pg_temp.remove_membership(g, '00000000-0111-4000-8000-000000000060');
  perform pg_temp.check(n = 0, 'someone outside is not removed');
end $$;

-- 4. The members of a month: one read, members only.
insert into competition.competitions (id, name, format, visibility)
values ('00000000-0111-4000-8000-0000000000c1', 'Monthly', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at)
values ('00000000-0111-4000-8000-0000000000e1', '00000000-0111-4000-8000-0000000000c1',
        '06/2099', '2099-06-01', '2099-07-01');
insert into competition.participants (id, season_id, user_id, joined_at) values
  ('00000000-0111-4000-8000-0000000000f1', '00000000-0111-4000-8000-0000000000e1',
   '00000000-0111-4000-8000-000000000001', '2099-06-01'),
  ('00000000-0111-4000-8000-0000000000f3', '00000000-0111-4000-8000-0000000000e1',
   '00000000-0111-4000-8000-000000000003', '2099-06-01'),
  ('00000000-0111-4000-8000-0000000000f9', '00000000-0111-4000-8000-0000000000e1',
   '00000000-0111-4000-8000-000000000060', '2099-06-01');

do $$
declare
  ids text[];
begin
  select array_agg(x order by x) into ids
    from pg_temp.member_participant_ids('00000000-0111-4000-8000-0000000000aa',
                                        '00000000-0111-4000-8000-0000000000e1') x;
  perform pg_temp.check(ids = array['00000000-0111-4000-8000-0000000000f1',
                                    '00000000-0111-4000-8000-0000000000f3'],
    'the members playing the month, and no one else');
end $$;

-- 5. Deleting the league takes its memberships and invitations with it;
--    the participants (points live there) stay.
do $$
declare
  g uuid := '00000000-0111-4000-8000-0000000000aa';
  n int;
begin
  n := pg_temp.delete_group(g);
  perform pg_temp.check(n = 1, 'the league is deleted');
  perform pg_temp.check(not exists (select 1 from "group".group_memberships where group_id = g),
    'its memberships go with it');
  perform pg_temp.check(
    (select count(*) from competition.participants
      where season_id = '00000000-0111-4000-8000-0000000000e1') = 3,
    'nobody''s contest entry is touched');
  n := pg_temp.delete_group(g);
  perform pg_temp.check(n = 0, 'a league already gone is not found');
end $$;

-- 6. A weekly league group never takes more than its capacity, and a
--    player already seated this week is left to the unique constraint.
insert into gamification.weekly_leagues (id, week_start, tier, group_index, capacity)
values ('00000000-0111-4000-8000-0000000000b1', '2099-06-01', 1, 0, 2);
insert into gamification.weekly_league_members (league_id, week_start, user_id) values
  ('00000000-0111-4000-8000-0000000000b1', '2099-06-01', '00000000-0111-4000-8000-000000000001'),
  ('00000000-0111-4000-8000-0000000000b1', '2099-06-01', '00000000-0111-4000-8000-000000000002');

do $$
declare
  n int;
begin
  perform pg_temp.check(pg_temp.refused(
    'insert into gamification.weekly_league_members (league_id, week_start, user_id)
     values (''00000000-0111-4000-8000-0000000000b1'', ''2099-06-01'', ''00000000-0111-4000-8000-000000000003'')',
    'weekly_league_members_capacity'),
    'a third seat in a group of two is refused');

  insert into gamification.weekly_league_members (league_id, week_start, user_id)
  values ('00000000-0111-4000-8000-0000000000b1', '2099-06-01', '00000000-0111-4000-8000-000000000001')
  on conflict (week_start, user_id) do nothing;
  select count(*) into n from gamification.weekly_league_members
   where league_id = '00000000-0111-4000-8000-0000000000b1';
  perform pg_temp.check(n = 2, 'a seated player placed again keeps his one seat');

  select count(*) into n from ops.applied_migrations where version = '0111_group_limits';
  perform pg_temp.check(n = 1, '0111 records itself');
end $$;

rollback;
