-- A head-to-head player's moves and their reasons (scripts 277 and 278,
-- 0213 and 0214) -- READ ONLY.
--
-- One SELECT, nothing written. Paste it into the Supabase SQL Editor and put
-- part of the player's name in `params` (Arabic or English, any part). One
-- line a move, oldest first: the month, what happened, why, from which
-- group to which, from which round, and when (Riyadh).
--   seat            the draw ('draw') or a new player at his first
--                   prediction ('newcomer')
--   group_start     his waiting group started (from the round shown)
--   seat_move_down  relegated for absence ('absence') or by an admin
--   seat_move_up    came up as a substitute
--   month_end       the month's end: the reason ('commitment', 'table',
--                   'not_counted', 'active_days') or, before December
--                   2026, the outcome
--   seat_vacated    left his seat in the last group for absence: on the
--                   waiting list from the round shown ('absence')
--   vacancy_filled  took a vacant seat from the waiting list
--   waiting_seat    took a waiting seat again: back after a prediction
--                   ('return') or a new player on a seat a filler left
--                   ('newcomer')
with params as (
  select '%علوش%' as player
),
who as (
  select u.id, u.display_name
  from params pa
  join identity.users u on u.display_name ilike pa.player
),
groups as (
  select l.id,
         case when l.division = 1 then l.group_index + 1
              else 4 + l.group_index + 1 end as group_no
  from gamification.h2h_leagues l
)
select w.display_name                                   as player,
       to_char(mv.month_start, 'YYYY-MM')               as month,
       mv.kind                                          as what,
       mv.reason                                        as why,
       gf.group_no                                      as from_group,
       gt.group_no                                      as to_group,
       mv.from_round                                    as from_round,
       to_char(mv.at at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI')
                                                        as at_riyadh
from who w
join gamification.h2h_movements mv
  on mv.user_id = w.id
  or (mv.kind = 'group_start' and mv.to_league_id in (
        select m.league_id from gamification.h2h_league_members m
        where m.user_id = w.id
        union
        select ws.league_id from gamification.h2h_waiting_seats ws
        where ws.user_id = w.id))
left join groups gf on gf.id = mv.from_league_id
left join groups gt on gt.id = mv.to_league_id
order by w.display_name, mv.month_start, mv.at;
