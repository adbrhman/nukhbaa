-- New players and waiting groups, month by month (script 277, 0213) --
-- READ ONLY.
--
-- One SELECT, nothing written. One line a waiting group: its month, its
-- group number, players seated, how many joined as new players, the round
-- it started from (empty: still waiting) and whether new seats are frozen
-- (supabase/queries/h2h_newcomers_freeze.sql). Run it before and after a
-- freeze or an unfreeze: the numbers never go down.
select to_char(w.month_start, 'YYYY-MM')                          as month,
       4 + l.group_index + 1                                      as group_no,
       (select count(*) from gamification.h2h_league_members m
         where m.league_id = w.league_id)                         as seated,
       (select count(*) from gamification.h2h_newcomer_seatings n
         where n.league_id = w.league_id)                         as newcomers,
       s.from_round                                               as started_from,
       to_char(w.opened_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI')
                                                                  as opened,
       exists (select 1 from pg_trigger t
                where t.tgname = 'h2h_newcomer_seatings_frozen'
                  and not t.tgisinternal)                         as frozen
from gamification.h2h_waiting_groups w
join gamification.h2h_leagues l on l.id = w.league_id
left join gamification.h2h_group_starts s on s.league_id = w.league_id
order by w.month_start, l.group_index;
