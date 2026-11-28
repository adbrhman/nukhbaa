-- Migration 0228 (the Elite Cup as one knockout bracket): the widened checks
-- and the bracket's cup-day numbering accept a round of sixteen, a quarter-
-- final, a semi-final and a final on four days, and still refuse what lies
-- outside it; an older three-path month keeps 0212's numbering. Uses the
-- statements of 0190's test (the adapter's SQL, text for text). Rolled back
-- at the end.
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
-- The world: November 2099 (the bracket) and December 2099 (an older
-- three-path month), 19 rounds each, and sixteen cup players u1..u16: the
-- first and the second place of each of the eight groups.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0228-4000-8228-' || lpad(i::text, 12, '0'))::uuid, 'b' || i || '@t.io', now()
from generate_series(1, 16) i;
insert into identity.users (id, email, display_name)
select ('00000000-0228-4000-8228-' || lpad(i::text, 12, '0'))::uuid, 'b' || i || '@t.io', 'B ' || i
from generate_series(1, 16) i;

insert into gamification.h2h_months (month_start, is_pilot, seated_count)
values ('2099-11-01', false, 160), ('2099-12-01', false, 80);
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2280000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid,
       '2099-11-01', n, ('2099-11-01'::date + (n - 1)), 6
from generate_series(1, 19) n;
insert into gamification.h2h_rounds (id, month_start, round_no, day, fixture_count)
select ('c2280000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       '2099-12-01', n, ('2099-12-01'::date + (n - 1)), 6
from generate_series(1, 19) n;

-- ---------------------------------------------------------------------------
-- The migration records itself, and the bracket's cup days.
-- ---------------------------------------------------------------------------
select pg_temp.check(
  (select count(*) from ops.applied_migrations
    where version = '0228_elite_cup_bracket') = 1,
  '0228 is recorded');
select pg_temp.check(
  (select array_agg(gamification.h2h_cup_bracket_day(s) order by o)
     from unnest(array['round16', 'quarter', 'semi', 'final']) with ordinality as t(s, o))
    = array[1, 2, 3, 4]::smallint[],
  'the bracket days are 1, 2, 3, 4');
select pg_temp.check(gamification.h2h_cup_bracket_day('round32') is null,
  'an unknown round has no bracket day');

-- ---------------------------------------------------------------------------
-- Sixteen qualifiers: the first and second place of each of the eight groups.
-- ---------------------------------------------------------------------------
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000001', 1, 39, 119, 9);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000002', 2, 38, 118, 8);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000003', 3, 37, 117, 8);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000004', 4, 36, 116, 7);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000005', 5, 35, 115, 7);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000006', 6, 34, 114, 6);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000007', 7, 33, 113, 6);
execute cup_enter('2099-11-01', 1, '00000000-0228-4000-8228-000000000008', 8, 32, 112, 5);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000009', 1, 19, 59, 4);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000010', 2, 18, 58, 4);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000011', 3, 17, 57, 3);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000012', 4, 16, 56, 3);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000013', 5, 15, 55, 3);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000014', 6, 14, 54, 2);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000015', 7, 13, 53, 2);
execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000016', 8, 12, 52, 2);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_entries
    where month_start = '2099-11-01') = 16,
  'sixteen qualifiers');
select pg_temp.check(
  (select count(distinct group_number) from gamification.h2h_cup_entries
    where month_start = '2099-11-01') = 8,
  'from eight groups');

-- ---------------------------------------------------------------------------
-- The bracket on path 1: round16 on the 20th, quarter on the 21st, semi on
-- the 22nd, final on the 23rd, each on a later day than the one before it.
-- ---------------------------------------------------------------------------
execute cup_stage('c2280000-0000-4000-8000-0000000005a1', '2099-11-01', 1, 'round16', 1, '2099-11-20', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005a2', '2099-11-01', 1, 'quarter', 1, '2099-11-21', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005a3', '2099-11-01', 1, 'semi', 1, '2099-11-22', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005a4', '2099-11-01', 1, 'final', 1, '2099-11-23', 0);
select pg_temp.check(
  (select string_agg(stage, ',' order by day) from gamification.h2h_cup_stages
    where month_start = '2099-11-01') = 'round16,quarter,semi,final',
  'a bracket runs round16, quarter, semi, final in order');

select pg_temp.refused($q$execute cup_stage('c2280000-0000-4000-8000-0000000005a5', '2099-11-01', 1, 'round32', 1, '2099-11-24', 0)$q$,
  'h2h_cup_stages_stage_known', 'an unknown stage is still refused');
select pg_temp.refused($q$execute cup_stage('c2280000-0000-4000-8000-0000000005a6', '2099-11-01', 1, 'round16', 2, '2099-11-24', 0)$q$,
  'h2h_cup_stages_in_order', 'a round of sixteen after the final is refused');
select pg_temp.refused($q$execute cup_stage('c2280000-0000-4000-8000-0000000005a7', '2099-11-01', 1, 'semi', 2, '2099-11-23', 0)$q$,
  'h2h_cup_stages_in_order', 'no second stage on the final''s day');

-- ---------------------------------------------------------------------------
-- The pairs: eight, four, two, one. u1..u8 are the groups' first places and
-- u9..u16 their second places; the first pairing is only a shape for the test.
-- ---------------------------------------------------------------------------
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 1, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000016');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 2, '00000000-0228-4000-8228-000000000002', '00000000-0228-4000-8228-000000000015');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 3, '00000000-0228-4000-8228-000000000003', '00000000-0228-4000-8228-000000000014');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 4, '00000000-0228-4000-8228-000000000004', '00000000-0228-4000-8228-000000000013');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 5, '00000000-0228-4000-8228-000000000005', '00000000-0228-4000-8228-000000000012');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 6, '00000000-0228-4000-8228-000000000006', '00000000-0228-4000-8228-000000000011');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 7, '00000000-0228-4000-8228-000000000007', '00000000-0228-4000-8228-000000000010');
execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 8, '00000000-0228-4000-8228-000000000008', '00000000-0228-4000-8228-000000000009');
execute cup_pair('c2280000-0000-4000-8000-0000000005a2', 1, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000008');
execute cup_pair('c2280000-0000-4000-8000-0000000005a2', 2, '00000000-0228-4000-8228-000000000002', '00000000-0228-4000-8228-000000000007');
execute cup_pair('c2280000-0000-4000-8000-0000000005a2', 3, '00000000-0228-4000-8228-000000000003', '00000000-0228-4000-8228-000000000006');
execute cup_pair('c2280000-0000-4000-8000-0000000005a2', 4, '00000000-0228-4000-8228-000000000004', '00000000-0228-4000-8228-000000000005');
execute cup_pair('c2280000-0000-4000-8000-0000000005a3', 1, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000004');
execute cup_pair('c2280000-0000-4000-8000-0000000005a3', 2, '00000000-0228-4000-8228-000000000002', '00000000-0228-4000-8228-000000000003');
execute cup_pair('c2280000-0000-4000-8000-0000000005a4', 1, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000002');
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_pairs
    where stage_id = 'c2280000-0000-4000-8000-0000000005a1') = 8,
  'eight pairs in the round of sixteen');
select pg_temp.check(
  (select max(slot) from gamification.h2h_cup_pairs
    where stage_id = 'c2280000-0000-4000-8000-0000000005a1') = 8,
  'slot 8 is a pair of the round of sixteen');

select pg_temp.refused($q$execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 9, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000002')$q$,
  'h2h_cup_pairs_slot_range', 'a ninth slot is refused');
select pg_temp.refused($q$execute cup_pair('c2280000-0000-4000-8000-0000000005a1', 0, '00000000-0228-4000-8228-000000000001', '00000000-0228-4000-8228-000000000002')$q$,
  'h2h_cup_pairs_slot_range', 'slot 0 is refused');
select pg_temp.refused($q$execute cup_pair('c2280000-0000-4000-8000-0000000005a2', 2, '00000000-0228-4000-8228-000000000003', '00000000-0228-4000-8228-000000000003')$q$,
  'h2h_cup_pairs_two_players', 'a player is still not paired with himself');

-- Entries keep 0227's ranges.
select pg_temp.refused($q$execute cup_enter('2099-11-01', 2, '00000000-0228-4000-8228-000000000001', 9, 1, 1, 1)$q$,
  'h2h_cup_entries_group_range', 'group 9 is still not a cup group');
select pg_temp.refused($q$execute cup_enter('2099-11-01', 4, '00000000-0228-4000-8228-000000000001', 1, 1, 1, 1)$q$,
  'h2h_cup_entries_place_range', 'a fourth place still does not qualify');

-- ---------------------------------------------------------------------------
-- An older month keeps 0212's numbering: path 1 semi (day 1), path 1 final
-- (day 2), then paths 2 and 3 side by side on one day (day 3).
-- ---------------------------------------------------------------------------
execute cup_stage('c2280000-0000-4000-8000-0000000005a8', '2099-12-01', 1, 'semi', 1, '2099-12-20', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005a9', '2099-12-01', 1, 'final', 1, '2099-12-21', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005aa', '2099-12-01', 2, 'semi', 1, '2099-12-22', 0);
execute cup_stage('c2280000-0000-4000-8000-0000000005ab', '2099-12-01', 3, 'semi', 1, '2099-12-22', 0);
select pg_temp.check(
  (select count(*) from gamification.h2h_cup_stages
    where month_start = '2099-12-01') = 4,
  'an older month still plays paths 2 and 3 on the same day');
select pg_temp.refused($q$execute cup_stage('c2280000-0000-4000-8000-0000000005ac', '2099-12-01', 1, 'semi', 2, '2099-12-23', 0)$q$,
  'h2h_cup_stages_in_order', 'an older month keeps its order of days');

-- ---------------------------------------------------------------------------
-- Still append-only.
-- ---------------------------------------------------------------------------
select pg_temp.refused($q$update gamification.h2h_cup_pairs set slot = 8$q$, null,
  'a pair is never changed');
select pg_temp.refused($q$delete from gamification.h2h_cup_stages$q$, null,
  'a stage is never deleted');

rollback;
