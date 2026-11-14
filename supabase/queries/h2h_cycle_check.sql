-- The leagues and their rounds past the month's end (script 279, 0215)
-- -- READ ONLY.
--
-- One SELECT, nothing written. One line a drawn month from November 2026:
-- its rounds, the last round's day, how many of them fell after the
-- month's end, whether the month is judged, its Elite Cup titles (3 once
-- crowned) and the day of the next month's first round. A league still
-- playing past its month's end shows rounds under 19, judged false and
-- after_month_end above 0; the next month's first round comes after the
-- last crowning. Run it on the 1st of a month and after the 19th round.
select to_char(m.month_start, 'YYYY-MM')                          as month,
       (select count(*) from gamification.h2h_rounds r
         where r.month_start = m.month_start)                     as rounds,
       (select to_char(max(r.day), 'YYYY-MM-DD')
          from gamification.h2h_rounds r
         where r.month_start = m.month_start)                     as last_round,
       (select count(*) from gamification.h2h_rounds r
         where r.month_start = m.month_start
           and r.day >= (m.month_start + interval '1 month')::date) as after_month_end,
       exists (select 1 from gamification.h2h_month_closures c
                where c.month_start = m.month_start)              as judged,
       (select count(*) from gamification.h2h_cup_titles t
         where t.month_start = m.month_start)                     as cup_titles,
       (select to_char(min(r.day), 'YYYY-MM-DD')
          from gamification.h2h_rounds r
         where r.month_start = (m.month_start + interval '1 month')::date)
                                                                  as next_month_first_round
from gamification.h2h_months m
where m.month_start >= date '2026-11-01'
order by m.month_start;
