-- Migration 0227 (the Elite Cup widened for eight groups): the three widened
-- checks accept what the eight-group cup needs and still refuse what lies
-- outside it. Uses the statements of 0190's test (the adapter's SQL, text for
-- text). Rolled back at the end.
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

-- A statement that must be refused with constraint [name] (any refusal
-- when [name] is null).
create function pg_temp.refused(stmt text, name text, label text)
returns void language plpgsql as $$
declare
  v_name text;
begin
  begin
    execute stmt;
  exception when others then
    get stacked diagnostics v_name = constraint_name;
    perform pg_temp.check(name is null or v_name = name, label || ' (' || coalesce(v_name, sqlerrm) || ')');
    return;
  end;
  raise exception 'FAILED: % (not refused)', label;
end $$;

-- enterSql
PREPARE cup_enter(date, smallint, uuid, smallint, integer, integer, integer) AS
INSERT INTO gamification.h2h_cup_entries
  (month_start, place, user_id, group_number, league_points, points_for,
   exact_count)
VALUES ($1::date, $2::smallint, $3::uuid,
        $4::smallint, $5::integer,
        $6::integer, $7::integer)
ON CONFLICT DO NOTHING;

-- stageSql
PREPARE cup_stage(uuid, date, smallint, text, smallint, date, smallint) AS
INSERT INTO gamification.h2h_cup_stages
  (id, month_start, place, stage, attempt, day, fixture_count)
VALUES ($1::uuid, $2::date, $3::smallint, $4, $5::smallint,
        $6::date, $7::smallint);

-- pairSql
PREPARE cup_pair(uuid, smallint, uuid, uuid) AS
INSERT INTO gamification.h2h_cup_pairs (stage_id, slot, home_user, away_user)
VALUES ($1::uuid, $2::smallint, $3::uuid, $4::uuid);

-- ---------------------------------------------------------------------------
-- The world: November 2099 drawn, 19 rounds on the 1st..19th, eight cup
-- players u1..u8 (one per group).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0227-4000-8227-00000000000' || i)::uuid, 'e' || i || '@t.io', now()
from generate_series(1, 8) i;
insert into identity.users (id, email, display_name)
select ('00000000-0227-4000-8227-00000000000' || i)::uuid, 'e' || i || '@t.io', 'E ' || i
from generate_series(1, 8) i;

insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-11-01', false, 160);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2270000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2099-11-01', n, ('2099-11-01'::date + (n - 1)), 6
from generate_series(1, 19) n;

-- ---------------------------------------------------------------------------
-- The migration records itself.
-- ---------------------------------------------------------------------------
select pg_temp.check(
  (select count(*) from ops.applied_migrations
    where version = '0227_eight_groups_cup_constraints') = 1,
  '0227 is recorded');

-- ---------------------------------------------------------------------------
-- Eight groups: the first place of each of the eight groups qualifies.
-- ---------------------------------------------------------------------------
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000001', 1, 40, 120, 9);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000002', 2, 38, 110, 7);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000003', 3, 36, 100, 5);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000004', 4, 34, 90, 3);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000005', 5, 32, 80, 2);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000006', 6, 30, 70, 2);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000007', 7, 28, 60, 1);
execute cup_enter('2099-11-01', 1, '00000000-0227-4000-8227-000000000008', 8, 26, 50, 1);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_entries
    where month_start = '2099-11-01' and place = 1) = 8,
  'eight qualifiers, one per group 1..8');
select pg_temp.check(
  (select max(group_number) from gamification.h2h_cup_entries
    where month_start = '2099-11-01') = 8,
  'group 8 is a cup group');

select pg_temp.refused($q$execute cup_enter('2099-11-01', 2, '00000000-0227-4000-8227-000000000001', 9, 1, 1, 1)$q$,
  'h2h_cup_entries_group_range', 'group 9 is not a cup group');
select pg_temp.refused($q$execute cup_enter('2099-11-01', 2, '00000000-0227-4000-8227-000000000001', 0, 1, 1, 1)$q$,
  'h2h_cup_entries_group_range', 'group 0 is not a cup group');
select pg_temp.refused($q$execute cup_enter('2099-11-01', 4, '00000000-0227-4000-8227-000000000001', 1, 1, 1, 1)$q$,
  'h2h_cup_entries_place_range', 'a fourth place still does not qualify');

-- ---------------------------------------------------------------------------
-- Path 1: quarter-final on the 20th, semi-final on the 21st, final on the
-- 22nd, each on a later day than the stage before it.
-- ---------------------------------------------------------------------------
execute cup_stage('c2270000-0000-4000-8000-0000000005a1', '2099-11-01', 1, 'quarter', 1, '2099-11-20', 0);
execute cup_stage('c2270000-0000-4000-8000-0000000005a2', '2099-11-01', 1, 'semi', 1, '2099-11-21', 0);
execute cup_stage('c2270000-0000-4000-8000-0000000005a3', '2099-11-01', 1, 'final', 1, '2099-11-22', 0);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stages
    where month_start = '2099-11-01' and place = 1) = 3,
  'a path may hold a quarter-final, a semi-final and a final');
select pg_temp.check(
  (select string_agg(stage, ',' order by day) from gamification.h2h_cup_stages
    where month_start = '2099-11-01') = 'quarter,semi,final',
  'the stages run in order');

select pg_temp.refused($q$execute cup_stage('c2270000-0000-4000-8000-0000000005a4', '2099-11-01', 2, 'round16', 1, '2099-11-23', 0)$q$,
  'h2h_cup_stages_stage_known', 'an unknown stage is still refused');
select pg_temp.refused($q$execute cup_stage('c2270000-0000-4000-8000-0000000005a4', '2099-11-01', 4, 'quarter', 1, '2099-11-23', 0)$q$,
  'h2h_cup_stages_place_range', 'a fourth path is still refused');
select pg_temp.refused($q$execute cup_stage('c2270000-0000-4000-8000-0000000005a4', '2099-11-01', 2, 'quarter', 1, '2099-11-22', 0)$q$,
  'h2h_cup_stages_in_order', 'a quarter-final keeps the order of days');

-- ---------------------------------------------------------------------------
-- The quarter-final's four pairs, the semi-final's two, the final's one.
-- ---------------------------------------------------------------------------
execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 1, '00000000-0227-4000-8227-000000000001', '00000000-0227-4000-8227-000000000002');
execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 2, '00000000-0227-4000-8227-000000000003', '00000000-0227-4000-8227-000000000004');
execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 3, '00000000-0227-4000-8227-000000000005', '00000000-0227-4000-8227-000000000006');
execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 4, '00000000-0227-4000-8227-000000000007', '00000000-0227-4000-8227-000000000008');
execute cup_pair('c2270000-0000-4000-8000-0000000005a2', 1, '00000000-0227-4000-8227-000000000001', '00000000-0227-4000-8227-000000000003');
execute cup_pair('c2270000-0000-4000-8000-0000000005a2', 2, '00000000-0227-4000-8227-000000000005', '00000000-0227-4000-8227-000000000007');
execute cup_pair('c2270000-0000-4000-8000-0000000005a3', 1, '00000000-0227-4000-8227-000000000001', '00000000-0227-4000-8227-000000000005');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_pairs
    where stage_id = 'c2270000-0000-4000-8000-0000000005a1') = 4,
  'four pairs in the quarter-final');

select pg_temp.refused($q$execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 5, '00000000-0227-4000-8227-000000000001', '00000000-0227-4000-8227-000000000002')$q$,
  'h2h_cup_pairs_slot_range', 'a fifth slot is refused');
select pg_temp.refused($q$execute cup_pair('c2270000-0000-4000-8000-0000000005a1', 0, '00000000-0227-4000-8227-000000000001', '00000000-0227-4000-8227-000000000002')$q$,
  'h2h_cup_pairs_slot_range', 'slot 0 is refused');
select pg_temp.refused($q$execute cup_pair('c2270000-0000-4000-8000-0000000005a2', 3, '00000000-0227-4000-8227-000000000003', '00000000-0227-4000-8227-000000000003')$q$,
  'h2h_cup_pairs_two_players', 'a player is still not paired with himself');

-- ---------------------------------------------------------------------------
-- Still append-only.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$update gamification.h2h_cup_entries set group_number = 8$q$, null,
  'an entry is never changed');
select pg_temp.refused($q$delete from gamification.h2h_cup_pairs$q$, null,
  'a pair is never deleted');

rollback;
