-- Unfreeze new players (script 277, 0213) -- WRITES NO ROW.
--
-- Undoes supabase/queries/h2h_newcomers_freeze.sql: new players are seated
-- again at the server's next run, and a waiting group that reached twenty
-- while frozen starts from the next round that has not started. Safe to
-- run twice, and harmless when nothing was frozen.
begin;

drop trigger if exists h2h_newcomer_seatings_frozen
  on gamification.h2h_newcomer_seatings;
drop trigger if exists h2h_group_starts_frozen
  on gamification.h2h_group_starts;
drop function if exists gamification.refuse_h2h_newcomers_frozen();

commit;
