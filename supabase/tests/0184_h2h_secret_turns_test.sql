-- End-to-end test of migration 0184 (the head-to-head league's secret round
-- order) and of the statements that write and read it: PostgresH2hTurnKeeper
-- (ensureSql, also run by the draw and the extra groups) and
-- PostgresH2hSheetReader (turnsSql). The PREPARE statements are the
-- adapters' SQL constants, text for text, with @name::type turned into
-- $n::type. Rolled back at the end.
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

-- Whether [stmt] is refused, and by which constraint.
create function pg_temp.refused_by(stmt text) returns text
language plpgsql as $$
declare
  v_constraint text;
begin
  execute stmt;
  return null;
exception when others then
  get stacked diagnostics v_constraint = constraint_name;
  return coalesce(nullif(v_constraint, ''), sqlstate);
end $$;

-- ensureSql
PREPARE turns_ensure(date) AS

INSERT INTO gamification.h2h_league_turns (league_id, turns)
SELECT l.id,
       ARRAY(
         SELECT g::smallint
         FROM generate_series(1, l.capacity - 1) AS g
         ORDER BY gen_random_uuid()
       )
FROM gamification.h2h_leagues l
WHERE l.month_start = $1::date
  AND NOT EXISTS (
    SELECT 1 FROM gamification.h2h_league_turns t WHERE t.league_id = l.id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM gamification.h2h_league_members m
    JOIN gamification.h2h_rounds r ON r.month_start = l.month_start
    JOIN gamification.h2h_round_locks k ON k.round_id = r.id
    WHERE m.league_id = l.id
      AND m.joined_at <= k.locked_at
  )
ON CONFLICT (league_id) DO NOTHING
RETURNING league_id::text AS league_id;

-- turnsSql
PREPARE turns_read(uuid) AS

SELECT array_to_string(t.turns, ',') AS turns
FROM gamification.h2h_league_turns t
WHERE t.league_id = $1::uuid;

-- ---------------------------------------------------------------------------
-- The world: December 2099. Group A (four seats) was drawn on the 1st and
-- played round 1, locked on the 3rd. Group B (four seats) was added on the
-- 5th, after that lock. January 2100: group C (twenty seats) and five more
-- groups of twenty, nothing played.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0184-4000-8184-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'p' || n || '@t.io', now()
  from generate_series(1, 8) n;
insert into identity.users (id, email, display_name)
select ('00000000-0184-4000-8184-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'p' || n || '@t.io', 'P ' || n
  from generate_series(1, 8) n;

insert into gamification.h2h_months (month_start, is_pilot, seated_count) values
  ('2099-12-01', false, 4),
  ('2100-01-01', false, 0);
insert into gamification.h2h_leagues (id, month_start, division, group_index, capacity) values
  ('c1840000-0000-4000-8000-0000000000a1', '2099-12-01', 1, 0, 4),
  ('c1840000-0000-4000-8000-0000000000b1', '2099-12-01', 2, 0, 4),
  ('c1840000-0000-4000-8000-0000000000c1', '2100-01-01', 1, 0, 20);
insert into gamification.h2h_leagues (id, month_start, division, group_index, capacity)
select ('c1840000-0000-4000-8000-0000000000d' || n)::uuid, '2100-01-01', 4, n, 20
  from generate_series(1, 5) n;

insert into gamification.h2h_league_members (league_id, month_start, user_id, slot, joined_at)
select 'c1840000-0000-4000-8000-0000000000a1', '2099-12-01',
       ('00000000-0184-4000-8184-0000000000' || lpad(n::text, 2, '0'))::uuid,
       n - 1, '2099-11-30 21:05Z'
  from generate_series(1, 4) n;
insert into gamification.h2h_league_members (league_id, month_start, user_id, slot, joined_at)
select 'c1840000-0000-4000-8000-0000000000b1', '2099-12-01',
       ('00000000-0184-4000-8184-0000000000' || lpad(n::text, 2, '0'))::uuid,
       n - 5, '2099-12-05 09:00Z'
  from generate_series(5, 8) n;

insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count) values
  ('c1840000-0000-4000-8000-0000000000e1', '2099-12-01', 1, '2099-12-03', 6);
insert into gamification.h2h_round_locks (round_id, fixture_count, locked_at) values
  ('c1840000-0000-4000-8000-0000000000e1', 6, '2099-12-03 15:00Z');

-- ---------------------------------------------------------------------------
-- The guards
-- ---------------------------------------------------------------------------
do $$
begin
  perform pg_temp.check(
    pg_temp.refused_by($q$insert into gamification.h2h_league_turns (league_id, turns)
      values ('c1840000-0000-4000-8000-0000000000c1', array[1, 2, 3]::smallint[])$q$)
      = 'h2h_league_turns_order',
    'an order shorter than the group''s 19 turns is refused');
  perform pg_temp.check(
    pg_temp.refused_by($q$insert into gamification.h2h_league_turns (league_id, turns)
      values ('c1840000-0000-4000-8000-0000000000b1', array[1, 1, 2]::smallint[])$q$)
      = 'h2h_league_turns_order',
    'a turn twice is refused');
  perform pg_temp.check(
    pg_temp.refused_by($q$insert into gamification.h2h_league_turns (league_id, turns)
      values ('c1840000-0000-4000-8000-0000000000b1', array[1, 2, 4]::smallint[])$q$)
      = 'h2h_league_turns_order',
    'a turn the group does not have is refused');
  perform pg_temp.check(
    pg_temp.refused_by($q$insert into gamification.h2h_league_turns (league_id, turns)
      values ('c1840000-0000-4000-8000-0000000000a1', array[3, 1, 2]::smallint[])$q$)
      = 'h2h_league_turns_played',
    'a group whose members were seated before a lock keeps the order of the slots');
  perform pg_temp.check(
    pg_temp.refused_by($q$insert into gamification.h2h_league_turns (league_id, turns)
      values ('c1840000-0000-4000-8000-0000000000ff', array[1]::smallint[])$q$)
      = 'h2h_league_turns_league_id_fkey',
    'an order for no group is refused');
  perform pg_temp.check(
    not has_table_privilege('authenticated', 'gamification.h2h_league_turns', 'select')
      and not has_table_privilege('anon', 'gamification.h2h_league_turns', 'select'),
    'the order is server-only');
  perform pg_temp.check(
    (select relrowsecurity from pg_class
      where oid = 'gamification.h2h_league_turns'::regclass),
    'row level security is on');
end $$;

-- ---------------------------------------------------------------------------
-- The keeper
-- ---------------------------------------------------------------------------
execute turns_ensure('2099-12-01');
create temp table december_out as
  select league_id::text as league_id, turns, created_at
    from gamification.h2h_league_turns;
execute turns_ensure('2099-12-01');
create temp table b_order as execute turns_read('c1840000-0000-4000-8000-0000000000b1');
create temp table a_order as execute turns_read('c1840000-0000-4000-8000-0000000000a1');
do $$
begin
  perform pg_temp.check(
    (select array_agg(league_id) from december_out)
      = array['c1840000-0000-4000-8000-0000000000b1'],
    'December: the group added after the lock gets an order, the one that played does not');
  perform pg_temp.check(
    (select array_agg(league_id::text || turns::text) from gamification.h2h_league_turns)
      = (select array_agg(league_id || turns::text) from december_out),
    'a second run writes nothing and changes nothing');
  perform pg_temp.check(
    (select array_agg(t::int order by t::int)
       from b_order, unnest(string_to_array(turns, ',')) t)
      = array[1, 2, 3],
    'the order reads back as text: each turn of four seats once');
  perform pg_temp.check((select count(*) from a_order) = 0,
    'a group without an order reads no row');
end $$;

execute turns_ensure('2100-01-01');
create temp table c_order as execute turns_read('c1840000-0000-4000-8000-0000000000c1');
do $$
begin
  perform pg_temp.check(
    (select count(*) from gamification.h2h_league_turns t
       join gamification.h2h_leagues l on l.id = t.league_id
      where l.month_start = '2100-01-01') = 6,
    'January: every group, none played, gets an order');
  perform pg_temp.check(
    (select array_agg(t::int order by t::int)
       from c_order, unnest(string_to_array(turns, ',')) t)
      = (select array_agg(g) from generate_series(1, 19) g),
    'twenty seats: each of the 19 turns once');
  perform pg_temp.check(
    (select count(distinct turns) from gamification.h2h_league_turns t
       join gamification.h2h_leagues l on l.id = t.league_id
      where l.month_start = '2100-01-01') > 1,
    'the groups do not share one order');
  perform pg_temp.check(
    (select bool_or(turns <> (select array_agg(g::smallint order by g)
                                from generate_series(1, 19) g))
       from gamification.h2h_league_turns t
       join gamification.h2h_leagues l on l.id = t.league_id
      where l.month_start = '2100-01-01'),
    'the orders are shuffled, not the slots'' own');
  perform pg_temp.check(
    pg_temp.refused_by($q$update gamification.h2h_league_turns
      set turns = turns where league_id = 'c1840000-0000-4000-8000-0000000000c1'$q$)
      = '23514',
    'an order is never changed');
  perform pg_temp.check(
    pg_temp.refused_by($q$delete from gamification.h2h_league_turns
      where league_id = 'c1840000-0000-4000-8000-0000000000c1'$q$)
      = '23514',
    'an order is never deleted');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0184_h2h_secret_turns'),
    '0184 records itself');
end $$;

rollback;
