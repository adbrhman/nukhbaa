-- ============================================================================
-- Migration 0184: the head-to-head league's secret round order (script 146)
--
-- ADDITIVE ONLY. One new table, its guards and its grants. No row of any
-- other table is written, changed or removed.
--
-- Why: a group plays a fixed round-robin (0100, the circle method): the
-- slot meets slot `opponentSlot(slot, round)`, so every member could read
-- his opponent of every round in advance, and the board shows everyone's
-- picks as each match kicks off. A player who knows his opponent can shape
-- his later picks of the day against that opponent's earlier ones, and two
-- friends can arrange which of them wins their round. Decided by the owner
-- on 2026-10-25 (option D): the round order is secret, the opponent is
-- named only after the last match of the round's day kicks off, and the
-- admins watch the suspicious matches.
--
-- * gamification.h2h_league_turns: one row per group, written once: the
--   order in which the group's rounds take the circle's turns, a
--   permutation of 1 .. capacity - 1 drawn with gen_random_uuid(). Round n
--   plays turn turns[n] (turns[(n - 1) % (capacity - 1) + 1] past the
--   last), so every pair still meets once in capacity - 1 rounds, and no
--   member can work out an opponent ahead of time. A group without a row
--   plays the turns in order, as before.
-- * The order is written in the same transaction as the group (the draw,
--   the extra groups) or, for a group drawn before this migration, by the
--   scheduler before its next round locks. It is refused once a member of
--   the group was seated before a round of its month was locked: that
--   member may already have played under the old order, and the table is
--   recomputed from the order on every read.
-- * Append-only and server-only, as the 0100 tables.
--
-- Apply BEFORE deploying the server that reads it.
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists gamification.h2h_league_turns (
  league_id  uuid primary key
    constraint h2h_league_turns_league_id_fkey
      references gamification.h2h_leagues (id),
  turns      smallint[] not null,
  created_at timestamptz not null default now()
);

comment on table gamification.h2h_league_turns is
  'The secret order in which a head-to-head group plays the turns of its '
  'round-robin (0184): round n plays turn turns[n]. A permutation of '
  '1 .. capacity - 1, written once with the group. A group without a row '
  'plays the turns in order. Server-only; never sent to a client.';

create or replace function gamification.check_h2h_league_turns()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_capacity smallint;
  v_month    date;
  v_turns    integer;
begin
  select l.capacity, l.month_start
    into v_capacity, v_month
    from gamification.h2h_leagues l
   where l.id = new.league_id;
  if v_capacity is null then
    -- The foreign key reports the missing group.
    return new;
  end if;

  v_turns := v_capacity - 1;
  if coalesce(cardinality(new.turns), 0) <> v_turns
     or (select count(distinct t)
           from unnest(new.turns) as t
          where t between 1 and v_turns) <> v_turns then
    raise exception
      'h2h turns of group % must order 1..% once each', new.league_id, v_turns
      using errcode = 'check_violation',
            constraint = 'h2h_league_turns_order';
  end if;

  if exists (
    select 1
      from gamification.h2h_league_members m
      join gamification.h2h_rounds r on r.month_start = v_month
      join gamification.h2h_round_locks k on k.round_id = r.id
     where m.league_id = new.league_id
       and m.joined_at <= k.locked_at
  ) then
    raise exception
      'h2h group % already played a round in the old order', new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_league_turns_played';
  end if;
  return new;
end;
$$;

comment on function gamification.check_h2h_league_turns() is
  'h2h_league_turns: a permutation of 1 .. capacity - 1, refused once a '
  'member of the group was seated before a round of its month locked '
  '(0184).';

drop trigger if exists h2h_league_turns_check
  on gamification.h2h_league_turns;
create trigger h2h_league_turns_check
  before insert on gamification.h2h_league_turns
  for each row
  execute function gamification.check_h2h_league_turns();

drop trigger if exists h2h_league_turns_reject_mutation
  on gamification.h2h_league_turns;
create trigger h2h_league_turns_reject_mutation
  before update or delete on gamification.h2h_league_turns
  for each row
  execute function gamification.reject_h2h_mutation();

alter table gamification.h2h_league_turns enable row level security;
revoke all on gamification.h2h_league_turns from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0184_h2h_secret_turns')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0184_h2h_secret_turns';                        -- 1 row
-- select count(*) from gamification.h2h_league_turns;  -- groups with an order
