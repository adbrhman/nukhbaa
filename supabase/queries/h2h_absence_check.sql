-- Seats left for absence and their fills, month by month (script 278,
-- 0214) -- READ ONLY.
--
-- One SELECT, nothing written. One line a seat left vacant in the last
-- group that plays: its month, group, seat, the player who left it for the
-- waiting list and from which round, who filled it from the waiting list
-- and from which round (empty: still vacant), whether he is back in a
-- waiting seat, and whether vacancies are frozen
-- (supabase/queries/h2h_absence_freeze.sql). Run it before and after a
-- freeze or an unfreeze: no line ever disappears.
select to_char(v.month_start, 'YYYY-MM')                          as month,
       case when l.division = 1 then l.group_index + 1
            else 4 + l.group_index + 1 end                        as group_no,
       v.slot                                                     as seat,
       uo.display_name                                            as left_by,
       v.from_round                                               as vacant_from,
       ui.display_name                                            as filled_by,
       f.from_round                                               as filled_from,
       exists (select 1 from gamification.h2h_waiting_seats ws
                where ws.month_start = v.month_start
                  and ws.user_id = v.out_user)                    as came_back,
       exists (select 1 from pg_trigger t
                where t.tgname = 'h2h_seat_vacancies_frozen'
                  and not t.tgisinternal)                         as frozen
from gamification.h2h_seat_vacancies v
join gamification.h2h_leagues l on l.id = v.league_id
join identity.users uo on uo.id = v.out_user
left join gamification.h2h_vacancy_fills f on f.vacancy_id = v.id
left join identity.users ui on ui.id = f.in_user
order by v.month_start, v.from_round, v.created_at;
