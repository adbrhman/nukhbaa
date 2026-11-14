-- Unfreeze the vacant seats (script 278, 0214) -- WRITES NO ROW.
--
-- Undoes supabase/queries/h2h_absence_freeze.sql: the absence job leaves
-- and fills seats again before the next round, and a player back from
-- absence takes a waiting seat at the next run. Safe to run twice, and
-- harmless when nothing was frozen.
begin;

drop trigger if exists h2h_seat_vacancies_frozen
  on gamification.h2h_seat_vacancies;
drop trigger if exists h2h_vacancy_fills_frozen
  on gamification.h2h_vacancy_fills;
drop trigger if exists h2h_waiting_seats_frozen
  on gamification.h2h_waiting_seats;
drop function if exists gamification.refuse_h2h_vacancies_frozen();

commit;
