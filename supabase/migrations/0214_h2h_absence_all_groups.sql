-- ============================================================================
-- Migration 0214: absence in every group, the vacant seat and the waiting
-- list's seats (script 278)
--
-- ADDITIVE ONLY. Three new append-only tables, one function, new guards and
-- the replacement of three guard functions and of the moves view. No row of
-- any existing table is written, changed or removed.
--
-- Why: decided by the owner on 2026-11-14, from December 2026 on:
--   * a player of ANY group who misses three consecutive counted rounds goes
--     down one group: from groups 1 to 4 to group 5, from group k to group
--     k + 1, swapping seats with the most committed eligible player there
--     (h2h_seat_moves, now between neighbouring groups only);
--   * in the last group that plays there is no group below: the absent
--     player leaves his seat (h2h_seat_vacancies) and goes to the waiting
--     list, holding no seat and not counted among its twenty until he makes
--     a real prediction again; the seat is filled from the waiting list in
--     the same transaction when an eligible player is there
--     (h2h_vacancy_fills), else later, and stays vacant meanwhile (its
--     opponent plays an absent opponent, no average);
--   * a waiting seat a filler left is taken again by the next new player or
--     returning player (h2h_waiting_seats); who holds the waiting seats now
--     is gamification.h2h_waiting_holders(), and a waiting group starts
--     only with twenty holders;
--   * nobody moves twice before the same round, and nobody is relegated
--     twice in a month (h2h_one_move_per_round, h2h_one_relegation_a_month).
-- November 2026 and every earlier month are left exactly as they are: the
-- seat swap guard keeps its 0189 rule for them, and every new table and
-- guard refuses or ignores a month before December 2026.
--
-- Apply BEFORE pushing. Safe to re-run.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- A seat left for absence in the last group that plays
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_seat_vacancies (
  id          uuid primary key,
  month_start date     not null
    constraint h2h_seat_vacancies_month_fkey
      references gamification.h2h_months (month_start),
  league_id   uuid     not null
    constraint h2h_seat_vacancies_league_fkey
      references gamification.h2h_leagues (id),
  slot        smallint not null,
  -- The player who leaves the seat for the waiting list.
  out_user    uuid     not null
    constraint h2h_seat_vacancies_out_user_fkey
      references identity.users (id),
  -- The first round the seat is vacant.
  from_round  smallint not null,
  kind        text     not null,
  -- The absent rounds behind it: [{"month":..,"round":..}].
  absent_rounds jsonb  not null default '[]'::jsonb,
  created_at  timestamptz not null default clock_timestamp(),
  constraint h2h_seat_vacancies_kind_known check (kind in ('absence')),
  constraint h2h_seat_vacancies_from_round_range
    check (from_round between 2 and 19),
  constraint h2h_seat_vacancies_seat_round_uniq
    unique (league_id, slot, from_round),
  constraint h2h_seat_vacancies_out_once unique (month_start, out_user)
);

comment on table gamification.h2h_seat_vacancies is
  'A seat of the last group that plays, left for absence (0214, December '
  '2026 on): the player goes to the waiting list with no seat, the seat is '
  'vacant from from_round until filled (h2h_vacancy_fills). Append-only.';

-- ---------------------------------------------------------------------------
-- A vacant seat filled from the waiting list
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_vacancy_fills (
  vacancy_id     uuid primary key
    constraint h2h_vacancy_fills_vacancy_fkey
      references gamification.h2h_seat_vacancies (id),
  month_start    date     not null,
  in_user        uuid     not null
    constraint h2h_vacancy_fills_in_user_fkey
      references identity.users (id),
  from_round     smallint not null,
  -- The waiting seat the filler leaves.
  from_league_id uuid     not null
    constraint h2h_vacancy_fills_from_league_fkey
      references gamification.h2h_leagues (id),
  from_slot      smallint not null,
  -- What the filler was chosen on.
  candidate      jsonb    not null default '{}'::jsonb,
  created_at     timestamptz not null default clock_timestamp(),
  constraint h2h_vacancy_fills_from_round_range
    check (from_round between 2 and 19),
  constraint h2h_vacancy_fills_in_once unique (month_start, in_user)
);

comment on table gamification.h2h_vacancy_fills is
  'A vacant seat taken by a player of the waiting list (0214), from '
  'from_round on; his waiting seat is free again. Append-only.';

-- ---------------------------------------------------------------------------
-- A waiting seat taken again: a returning player, or a new player on a seat
-- a filler left
-- ---------------------------------------------------------------------------
create table if not exists gamification.h2h_waiting_seats (
  month_start date     not null,
  user_id     uuid     not null
    constraint h2h_waiting_seats_user_fkey
      references identity.users (id),
  league_id   uuid     not null
    constraint h2h_waiting_seats_league_fkey
      references gamification.h2h_leagues (id),
  slot        smallint not null,
  -- 'return': a player who left a seat for absence and predicted again;
  -- 'newcomer': a new player on a seat a filler left.
  reason      text     not null,
  created_at  timestamptz not null default clock_timestamp(),
  constraint h2h_waiting_seats_pkey primary key (month_start, user_id),
  constraint h2h_waiting_seats_reason_known
    check (reason in ('return', 'newcomer')),
  constraint h2h_waiting_seats_slot_range check (slot between 0 and 19)
);

comment on table gamification.h2h_waiting_seats is
  'A seat of a waiting group taken again (0214): by a player back from '
  'absence after a real prediction, or by a new player on the seat a '
  'filler left. Append-only.';

-- ---------------------------------------------------------------------------
-- Who holds the seats of a waiting group now
-- ---------------------------------------------------------------------------
create or replace function gamification.h2h_waiting_holders(p_league uuid)
returns table (slot smallint, user_id uuid, held_at timestamptz)
language sql
stable
set search_path = ''
as $$
  with ev as (
    select m.slot, m.user_id, m.joined_at as at, 1 as arrive
      from gamification.h2h_league_members m
     where m.league_id = p_league
    union all
    select w.slot, w.user_id, w.created_at, 1
      from gamification.h2h_waiting_seats w
     where w.league_id = p_league
    union all
    select f.from_slot, null::uuid, f.created_at, 0
      from gamification.h2h_vacancy_fills f
     where f.from_league_id = p_league
  ),
  latest as (
    select distinct on (ev.slot) ev.slot, ev.user_id, ev.at, ev.arrive
      from ev
     order by ev.slot, ev.at desc, ev.arrive asc
  )
  select l.slot, l.user_id, l.at from latest l where l.arrive = 1;
$$;

comment on function gamification.h2h_waiting_holders(uuid) is
  'The holders of a waiting group''s seats now (0214): its seats taken '
  '(the draw, a new player, h2h_waiting_seats) less those a filler left.';

-- Who holds seat [p_slot] of group [p_league] now: the draw's member, a
-- new player, whoever a swap, a fill or a waiting seat put there last; null
-- for a seat left vacant (or a waiting seat a filler left).
create or replace function gamification.h2h_seat_holder(
  p_league uuid,
  p_slot smallint
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select x.user_id
    from (
      select m.user_id, 1 as from_round, m.joined_at as at
        from gamification.h2h_league_members m
       where m.league_id = p_league and m.slot = p_slot
      union all
      select w.user_id, 1, w.created_at
        from gamification.h2h_waiting_seats w
       where w.league_id = p_league and w.slot = p_slot
      union all
      select null::uuid, 1, f.created_at
        from gamification.h2h_vacancy_fills f
       where f.from_league_id = p_league and f.from_slot = p_slot
      union all
      select mv.in_user, mv.from_round, mv.created_at
        from gamification.h2h_seat_moves mv
       where mv.elite_league_id = p_league and mv.elite_slot = p_slot
      union all
      select mv.out_user, mv.from_round, mv.created_at
        from gamification.h2h_seat_moves mv
       where mv.extra_league_id = p_league and mv.extra_slot = p_slot
      union all
      select null::uuid, v.from_round, v.created_at
        from gamification.h2h_seat_vacancies v
       where v.league_id = p_league and v.slot = p_slot
      union all
      select f.in_user, f.from_round, f.created_at
        from gamification.h2h_vacancy_fills f
        join gamification.h2h_seat_vacancies v on v.id = f.vacancy_id
       where v.league_id = p_league and v.slot = p_slot
    ) x
   order by x.from_round desc, x.at desc
   limit 1;
$$;

comment on function gamification.h2h_seat_holder(uuid, smallint) is
  'The holder of one seat now (0214), null when vacant.';

-- ---------------------------------------------------------------------------
-- The guards
-- ---------------------------------------------------------------------------

-- Whether a group is a waiting group that has not started.
create or replace function gamification.h2h_is_waiting(p_league uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from gamification.h2h_waiting_groups w
     where w.league_id = p_league
       and not exists (
         select 1 from gamification.h2h_group_starts s
          where s.league_id = w.league_id
       )
  );
$$;

-- A waiting group starts with twenty holders (replaces 0213's count of seats
-- ever taken, which a filler's departure would overstate).
create or replace function gamification.check_h2h_group_start()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month   date;
  v_members integer;
  v_played  integer;
begin
  select w.month_start into v_month
    from gamification.h2h_waiting_groups w
   where w.league_id = new.league_id;
  if v_month is null then
    return new;  -- the foreign key reports the missing waiting group
  end if;
  select count(*) into v_members
    from gamification.h2h_waiting_holders(new.league_id);
  if v_members < 20 then
    raise exception 'h2h group start: % holds % players, not 20',
      new.league_id, v_members
      using errcode = 'check_violation',
            constraint = 'h2h_group_starts_twenty';
  end if;
  select coalesce(max(r.round_no), 0) into v_played
    from gamification.h2h_rounds r
    join gamification.h2h_round_locks k on k.round_id = r.id
   where r.month_start = v_month;
  if new.from_round <= v_played then
    raise exception 'h2h group start: round % has started (last %)',
      new.from_round, v_played
      using errcode = 'check_violation',
            constraint = 'h2h_group_starts_not_played';
  end if;
  return new;
end;
$$;

-- A seat of a waiting group is taken only while nobody holds it.
create or replace function gamification.check_h2h_waiting_member()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not gamification.h2h_is_waiting(new.league_id) then
    return new;
  end if;
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_waiting_seats'),
    hashtext(new.league_id::text)
  );
  if exists (
    select 1 from gamification.h2h_waiting_holders(new.league_id) h
     where h.slot = new.slot
  ) then
    raise exception 'h2h waiting seat % of % is held', new.slot, new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_slot_free';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_league_members_waiting_check
  on gamification.h2h_league_members;
create trigger h2h_league_members_waiting_check
  before insert on gamification.h2h_league_members
  for each row
  execute function gamification.check_h2h_waiting_member();

create or replace function gamification.check_h2h_waiting_seat()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_month date;
begin
  select w.month_start into v_month
    from gamification.h2h_waiting_groups w
   where w.league_id = new.league_id;
  if v_month is null or not gamification.h2h_is_waiting(new.league_id) then
    raise exception 'h2h waiting seat: % is not a waiting group that has '
      'not started', new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_seats_waiting_only';
  end if;
  if v_month <> new.month_start then
    raise exception 'h2h waiting seat: month % differs from the group''s %',
      new.month_start, v_month
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_seats_month_matches';
  end if;
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_waiting_seats'),
    hashtext(new.league_id::text)
  );
  if exists (
    select 1 from gamification.h2h_waiting_holders(new.league_id) h
     where h.slot = new.slot
  ) then
    raise exception 'h2h waiting seat % of % is held', new.slot, new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_slot_free';
  end if;
  if new.reason = 'return' and not exists (
    select 1 from gamification.h2h_seat_vacancies v
     where v.month_start = new.month_start and v.out_user = new.user_id
  ) then
    raise exception 'h2h waiting seat: % left no seat for absence this month',
      new.user_id
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_seats_return_after_vacancy';
  end if;
  if new.reason = 'newcomer' and exists (
    select 1 from gamification.h2h_league_members m
     where m.month_start = new.month_start and m.user_id = new.user_id
  ) then
    raise exception 'h2h waiting seat: % has a seat this month', new.user_id
      using errcode = 'check_violation',
            constraint = 'h2h_waiting_seats_newcomer_unseated';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_waiting_seats_check on gamification.h2h_waiting_seats;
create trigger h2h_waiting_seats_check
  before insert on gamification.h2h_waiting_seats
  for each row
  execute function gamification.check_h2h_waiting_seat();

create or replace function gamification.check_h2h_seat_vacancy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_league gamification.h2h_leagues%rowtype;
begin
  select * into v_league from gamification.h2h_leagues
   where id = new.league_id;
  if v_league.id is null then
    return new;  -- the foreign key reports the missing group
  end if;
  if v_league.month_start <> new.month_start then
    raise exception 'h2h vacancy: month % differs from the group''s %',
      new.month_start, v_league.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_month_matches';
  end if;
  if new.month_start < date '2026-12-01' then
    raise exception 'h2h vacancy: none before December 2026 (%)',
      new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_december_on';
  end if;
  if gamification.h2h_is_waiting(new.league_id) then
    raise exception 'h2h vacancy: % has not started', new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_started';
  end if;
  if new.slot < 0 or new.slot >= v_league.capacity then
    raise exception 'h2h vacancy: a slot outside its group'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_slot_in_capacity';
  end if;
  if gamification.h2h_seat_holder(new.league_id, new.slot)
     is distinct from new.out_user then
    raise exception 'h2h vacancy: % does not hold seat % of %', new.out_user,
      new.slot, new.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_holder';
  end if;
  if exists (
    select 1
      from gamification.h2h_rounds r
      join gamification.h2h_round_locks k on k.round_id = r.id
     where r.month_start = new.month_start
       and r.round_no = new.from_round
  ) then
    raise exception 'h2h vacancy: round % already started', new.from_round
      using errcode = 'check_violation',
            constraint = 'h2h_seat_vacancies_round_not_started';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_seat_vacancies_check
  on gamification.h2h_seat_vacancies;
create trigger h2h_seat_vacancies_check
  before insert on gamification.h2h_seat_vacancies
  for each row
  execute function gamification.check_h2h_seat_vacancy();

create or replace function gamification.check_h2h_vacancy_fill()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_vacancy gamification.h2h_seat_vacancies%rowtype;
begin
  select * into v_vacancy from gamification.h2h_seat_vacancies
   where id = new.vacancy_id;
  if v_vacancy.id is null then
    return new;  -- the foreign key reports the missing vacancy
  end if;
  if v_vacancy.month_start <> new.month_start
     or new.from_round < v_vacancy.from_round then
    raise exception 'h2h fill: not the vacancy''s month, or before it'
      using errcode = 'check_violation',
            constraint = 'h2h_vacancy_fills_after_vacancy';
  end if;
  if exists (
    select 1
      from gamification.h2h_rounds r
      join gamification.h2h_round_locks k on k.round_id = r.id
     where r.month_start = new.month_start
       and r.round_no = new.from_round
  ) then
    raise exception 'h2h fill: round % already started', new.from_round
      using errcode = 'check_violation',
            constraint = 'h2h_vacancy_fills_round_not_started';
  end if;
  if gamification.h2h_seat_holder(v_vacancy.league_id, v_vacancy.slot)
     is not null then
    raise exception 'h2h fill: seat % of % is not vacant', v_vacancy.slot,
      v_vacancy.league_id
      using errcode = 'check_violation',
            constraint = 'h2h_vacancy_fills_vacant';
  end if;
  if not gamification.h2h_is_waiting(new.from_league_id) then
    raise exception 'h2h fill: % is not the waiting list', new.from_league_id
      using errcode = 'check_violation',
            constraint = 'h2h_vacancy_fills_from_waiting';
  end if;
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_waiting_seats'),
    hashtext(new.from_league_id::text)
  );
  if not exists (
    select 1 from gamification.h2h_waiting_holders(new.from_league_id) h
     where h.slot = new.from_slot and h.user_id = new.in_user
  ) then
    raise exception 'h2h fill: % does not hold waiting seat %', new.in_user,
      new.from_slot
      using errcode = 'check_violation',
            constraint = 'h2h_vacancy_fills_from_holder';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_vacancy_fills_check on gamification.h2h_vacancy_fills;
create trigger h2h_vacancy_fills_check
  before insert on gamification.h2h_vacancy_fills
  for each row
  execute function gamification.check_h2h_vacancy_fill();

-- From December 2026 a seat swap is between neighbouring groups that play:
-- groups 1 to 4 and group 5, group k and group k + 1. Earlier months keep
-- the 0189 rule (an elite seat for any extra seat), word for word.
create or replace function gamification.check_h2h_seat_move()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_elite gamification.h2h_leagues%rowtype;
  v_extra gamification.h2h_leagues%rowtype;
begin
  select * into v_elite from gamification.h2h_leagues
   where id = new.elite_league_id;
  select * into v_extra from gamification.h2h_leagues
   where id = new.extra_league_id;
  if v_elite.id is null or v_extra.id is null then
    return new;  -- the foreign keys report the missing group
  end if;
  if v_elite.month_start <> new.month_start
     or v_extra.month_start <> new.month_start then
    raise exception 'h2h seat move: both groups must belong to month %',
      new.month_start
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_month_matches';
  end if;
  if new.month_start < date '2026-12-01' then
    if v_elite.division <> 1 or v_extra.division <> 2 then
      raise exception 'h2h seat move: an elite seat (1) for an extra seat (2)'
        using errcode = 'check_violation',
              constraint = 'h2h_seat_moves_divisions';
    end if;
  else
    if v_elite.division > v_extra.division then
      raise exception 'h2h seat move: a seat for a seat below it'
        using errcode = 'check_violation',
              constraint = 'h2h_seat_moves_divisions';
    end if;
    if not ((v_elite.division = 1 and v_extra.division = 2
             and v_extra.group_index = 0)
            or (v_elite.division = 2 and v_extra.division = 2
                and v_extra.group_index = v_elite.group_index + 1)) then
      raise exception 'h2h seat move: from a group to the one below it'
        using errcode = 'check_violation',
              constraint = 'h2h_seat_moves_neighbours';
    end if;
    if gamification.h2h_is_waiting(new.elite_league_id)
       or gamification.h2h_is_waiting(new.extra_league_id) then
      raise exception 'h2h seat move: a waiting group takes no swap'
        using errcode = 'check_violation',
              constraint = 'h2h_seat_moves_started';
    end if;
    -- A swap the table's own keys refuse (out_once, in_once) is left to
    -- them.
    if not exists (
         select 1 from gamification.h2h_seat_moves mv
          where mv.month_start = new.month_start
            and (mv.out_user = new.out_user or mv.in_user = new.in_user)
       )
       and (gamification.h2h_seat_holder(new.elite_league_id, new.elite_slot)
         is distinct from new.out_user
       or gamification.h2h_seat_holder(new.extra_league_id, new.extra_slot)
         is distinct from new.in_user) then
      raise exception 'h2h seat move: each player leaves the seat he holds'
        using errcode = 'check_violation',
              constraint = 'h2h_seat_moves_holders';
    end if;
  end if;
  if new.elite_slot < 0 or new.elite_slot >= v_elite.capacity
     or new.extra_slot < 0 or new.extra_slot >= v_extra.capacity then
    raise exception 'h2h seat move: a slot outside its group'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_slot_in_capacity';
  end if;
  if exists (
    select 1 from gamification.h2h_seat_moves m
     where m.month_start = new.month_start
       and m.out_user = new.in_user
  ) then
    raise exception 'h2h seat move: a relegated player does not come back '
      'in the same month'
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_no_return';
  end if;
  if exists (
    select 1
      from gamification.h2h_rounds r
      join gamification.h2h_round_locks k on k.round_id = r.id
     where r.month_start = new.month_start
       and r.round_no = new.from_round
  ) then
    raise exception 'h2h seat move: round % already started', new.from_round
      using errcode = 'check_violation',
            constraint = 'h2h_seat_moves_round_not_started';
  end if;
  return new;
end;
$$;

-- Nobody moves twice before the same round, nobody is relegated twice in a
-- month, and a relegated player never comes back up in it: across the
-- swaps, the vacancies and the fills (December 2026 on).
create or replace function gamification.check_h2h_one_move()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_row   jsonb := to_jsonb(new);
  v_month date := (v_row->>'month_start')::date;
  v_round smallint := (v_row->>'from_round')::smallint;
  v_out   uuid := (v_row->>'out_user')::uuid;
  v_in    uuid := (v_row->>'in_user')::uuid;
begin
  if v_month < date '2026-12-01' then
    return new;
  end if;
  perform pg_advisory_xact_lock(
    hashtext('gamification.h2h_moves'),
    hashtext(v_month::text)
  );
  -- A swap the table's own keys refuse (out_once, in_once) is left to them.
  if tg_table_name = 'h2h_seat_moves' and exists (
    select 1 from gamification.h2h_seat_moves mv
     where mv.month_start = v_month
       and (mv.out_user = v_out or mv.in_user = v_in)
  ) then
    return new;
  end if;
  if exists (
    select 1 from (
      select mv.out_user as u, mv.from_round as r
        from gamification.h2h_seat_moves mv where mv.month_start = v_month
      union all
      select mv.in_user, mv.from_round
        from gamification.h2h_seat_moves mv where mv.month_start = v_month
      union all
      select v.out_user, v.from_round
        from gamification.h2h_seat_vacancies v where v.month_start = v_month
      union all
      select f.in_user, f.from_round
        from gamification.h2h_vacancy_fills f where f.month_start = v_month
    ) x
    where x.r = v_round and (x.u = v_out or x.u = v_in)
  ) then
    raise exception 'h2h move: a player moves once before round %', v_round
      using errcode = 'check_violation',
            constraint = 'h2h_one_move_per_round';
  end if;
  if v_out is not null and exists (
    select 1 from gamification.h2h_seat_moves mv
     where mv.month_start = v_month and mv.out_user = v_out
    union all
    select 1 from gamification.h2h_seat_vacancies v
     where v.month_start = v_month and v.out_user = v_out
  ) then
    raise exception 'h2h move: % was relegated this month already', v_out
      using errcode = 'check_violation',
            constraint = 'h2h_one_relegation_a_month';
  end if;
  if v_in is not null and exists (
    select 1 from gamification.h2h_seat_moves mv
     where mv.month_start = v_month and mv.out_user = v_in
    union all
    select 1 from gamification.h2h_seat_vacancies v
     where v.month_start = v_month and v.out_user = v_in
  ) then
    raise exception 'h2h move: % was relegated this month', v_in
      using errcode = 'check_violation',
            constraint = 'h2h_no_return_in_month';
  end if;
  return new;
end;
$$;

drop trigger if exists h2h_seat_moves_one_move on gamification.h2h_seat_moves;
create trigger h2h_seat_moves_one_move
  before insert on gamification.h2h_seat_moves
  for each row execute function gamification.check_h2h_one_move();
drop trigger if exists h2h_seat_vacancies_one_move
  on gamification.h2h_seat_vacancies;
create trigger h2h_seat_vacancies_one_move
  before insert on gamification.h2h_seat_vacancies
  for each row execute function gamification.check_h2h_one_move();
drop trigger if exists h2h_vacancy_fills_one_move
  on gamification.h2h_vacancy_fills;
create trigger h2h_vacancy_fills_one_move
  before insert on gamification.h2h_vacancy_fills
  for each row execute function gamification.check_h2h_one_move();

-- ---------------------------------------------------------------------------
-- Every move of a player, with its reason (0213's view, three more kinds)
-- ---------------------------------------------------------------------------
create or replace view gamification.h2h_movements
with (security_invoker = true)
as
select m.month_start,
       m.user_id,
       'seat'::text                                         as kind,
       case when n.user_id is null then 'draw' else 'newcomer' end
                                                            as reason,
       null::uuid                                           as from_league_id,
       m.league_id                                          as to_league_id,
       null::smallint                                       as from_round,
       coalesce(n.seated_at, m.joined_at)                   as at
from gamification.h2h_league_members m
left join gamification.h2h_newcomer_seatings n
  on n.month_start = m.month_start and n.user_id = m.user_id
union all
select w.month_start, null::uuid, 'group_start', null, null, s.league_id,
       s.from_round, s.started_at
from gamification.h2h_group_starts s
join gamification.h2h_waiting_groups w on w.league_id = s.league_id
union all
select mv.month_start, mv.out_user, 'seat_move_down', mv.kind,
       mv.elite_league_id, mv.extra_league_id, mv.from_round, mv.created_at
from gamification.h2h_seat_moves mv
union all
select mv.month_start, mv.in_user, 'seat_move_up', mv.kind,
       mv.extra_league_id, mv.elite_league_id, mv.from_round, mv.created_at
from gamification.h2h_seat_moves mv
union all
select (e.payload->>'month')::date, e.user_id, 'month_end',
       coalesce(e.payload->>'reason', e.payload->>'outcome'),
       e.ref_id, null, null, e.occurred_at
from gamification.events e
where e.event_type = 'h2h_league_finished'
union all
select v.month_start, v.out_user, 'seat_vacated', v.kind,
       v.league_id, null, v.from_round, v.created_at
from gamification.h2h_seat_vacancies v
union all
select f.month_start, f.in_user, 'vacancy_filled', 'absence',
       f.from_league_id, v.league_id, f.from_round, f.created_at
from gamification.h2h_vacancy_fills f
join gamification.h2h_seat_vacancies v on v.id = f.vacancy_id
union all
select ws.month_start, ws.user_id, 'waiting_seat', ws.reason,
       null, ws.league_id, null, ws.created_at
from gamification.h2h_waiting_seats ws;

comment on view gamification.h2h_movements is
  'Every move of a head-to-head player with its reason (0213, 0214): the '
  'draw, a new player, a group start, a seat swap, a seat vacated for '
  'absence, a vacant seat filled, a waiting seat taken again, the month''s '
  'end. Read-only, server-only; read by supabase/queries/h2h_movements.sql.';

-- ---------------------------------------------------------------------------
-- Append-only, server-only
-- ---------------------------------------------------------------------------
drop trigger if exists h2h_seat_vacancies_reject_mutation
  on gamification.h2h_seat_vacancies;
create trigger h2h_seat_vacancies_reject_mutation
  before update or delete on gamification.h2h_seat_vacancies
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_vacancy_fills_reject_mutation
  on gamification.h2h_vacancy_fills;
create trigger h2h_vacancy_fills_reject_mutation
  before update or delete on gamification.h2h_vacancy_fills
  for each row execute function gamification.reject_h2h_mutation();
drop trigger if exists h2h_waiting_seats_reject_mutation
  on gamification.h2h_waiting_seats;
create trigger h2h_waiting_seats_reject_mutation
  before update or delete on gamification.h2h_waiting_seats
  for each row execute function gamification.reject_h2h_mutation();

alter table gamification.h2h_seat_vacancies enable row level security;
alter table gamification.h2h_vacancy_fills enable row level security;
alter table gamification.h2h_waiting_seats enable row level security;

revoke all on gamification.h2h_seat_vacancies from anon, authenticated;
revoke all on gamification.h2h_vacancy_fills from anon, authenticated;
revoke all on gamification.h2h_waiting_seats from anon, authenticated;
revoke all on gamification.h2h_movements from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0214_h2h_absence_all_groups')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0214_h2h_absence_all_groups';                  -- 1 row
-- select relname, relrowsecurity from pg_class
--  where relnamespace = 'gamification'::regnamespace
--    and relname in ('h2h_seat_vacancies', 'h2h_vacancy_fills',
--                    'h2h_waiting_seats');                    -- 3 rows, true
