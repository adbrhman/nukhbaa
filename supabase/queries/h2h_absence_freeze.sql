-- Freeze the vacant seats (script 278, 0214) -- WRITES NO ROW.
--
-- The database-side switch of script 278, for when it must stop at once:
-- from this statement on, no seat of the last group is left for absence,
-- no vacant seat is filled and no waiting seat is taken again. Nothing is
-- deleted or changed: every seat, vacancy, fill, swap and result already
-- written stays as it is, and the groups go on. The absence job skips each
-- refused vacancy (the absent player keeps his seat) and tries again at its
-- next run; the seat swaps between groups go on unless they are turned off
-- too (NUKHBA_H2H_ABSENCE_RELEGATION=off on Northflank). Undone by
-- supabase/queries/h2h_absence_unfreeze.sql. Safe to run twice.
begin;

create or replace function gamification.refuse_h2h_vacancies_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'h2h vacant seats are frozen (h2h_absence_freeze.sql)'
    using errcode = 'check_violation',
          constraint = tg_table_name || '_frozen';
end;
$$;

drop trigger if exists h2h_seat_vacancies_frozen
  on gamification.h2h_seat_vacancies;
create trigger h2h_seat_vacancies_frozen
  before insert on gamification.h2h_seat_vacancies
  for each row execute function gamification.refuse_h2h_vacancies_frozen();

drop trigger if exists h2h_vacancy_fills_frozen
  on gamification.h2h_vacancy_fills;
create trigger h2h_vacancy_fills_frozen
  before insert on gamification.h2h_vacancy_fills
  for each row execute function gamification.refuse_h2h_vacancies_frozen();

drop trigger if exists h2h_waiting_seats_frozen
  on gamification.h2h_waiting_seats;
create trigger h2h_waiting_seats_frozen
  before insert on gamification.h2h_waiting_seats
  for each row execute function gamification.refuse_h2h_vacancies_frozen();

commit;
