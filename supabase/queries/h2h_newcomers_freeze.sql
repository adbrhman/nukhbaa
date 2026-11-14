-- Freeze new players (script 277, 0213) -- WRITES NO ROW.
--
-- The database-side switch of script 277, for when it must stop at once:
-- from this statement on, no new player is seated in a waiting group and
-- no waiting group starts. Nothing is deleted or changed: every seat,
-- waiting group, start and result already written stays as it is, and the
-- groups already playing go on. The server's job reports the refusal
-- (h2h_newcomers_frozen) every five minutes until it is turned off too
-- (NUKHBA_H2H_NEWCOMERS=off on Northflank) or this is undone by
-- supabase/queries/h2h_newcomers_unfreeze.sql. Safe to run twice.
begin;

create or replace function gamification.refuse_h2h_newcomers_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'h2h new players are frozen (h2h_newcomers_freeze.sql)'
    using errcode = 'check_violation',
          constraint = 'h2h_newcomers_frozen';
end;
$$;

drop trigger if exists h2h_newcomer_seatings_frozen
  on gamification.h2h_newcomer_seatings;
create trigger h2h_newcomer_seatings_frozen
  before insert on gamification.h2h_newcomer_seatings
  for each row execute function gamification.refuse_h2h_newcomers_frozen();

drop trigger if exists h2h_group_starts_frozen
  on gamification.h2h_group_starts;
create trigger h2h_group_starts_frozen
  before insert on gamification.h2h_group_starts
  for each row execute function gamification.refuse_h2h_newcomers_frozen();

commit;
