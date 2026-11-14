-- ============================================================================
-- Migration 0211: every write of a prediction is kept (script 274)
--
-- ADDITIVE ONLY. One table, two functions and two triggers are added. No row
-- of any existing table is written, changed or removed.
--
-- Why: decided by the owner on 2026-11-14. A player said he had predicted
-- 5-1 and that the app stored 5-0; prediction.fixture_predictions keeps only
-- the latest score with its first and last write times, so what the first
-- write held could not be shown. From this migration every insert, update
-- and delete of a prediction is kept, with the values before and after:
--
-- * prediction.fixture_prediction_changes: one row a write -- the
--   prediction, its match and participant, the operation, the score and the
--   double before (null on an insert) and after (null on a delete), the match
--   before when a merge moved it (0176), the time of the write
--   (clock_timestamp) and the statement that made it (current_query(), cut
--   to 200 characters: the app's own INSERT / UPDATE, a merge function, or a
--   hand-written query). A write that changes nothing is kept too: it is a
--   write the app made.
-- * prediction.log_fixture_prediction_change(): the AFTER row trigger
--   (security definer, so the server's role needs no grant on the table).
-- * prediction.reject_prediction_change_mutation(): the log is append-only;
--   an UPDATE or DELETE of it raises.
-- * Backend-only: RLS on, nothing granted to anon or authenticated. Read by
--   the owner through supabase/queries/prediction_changes.sql.
--
-- A deleted account keeps its predictions (0178), so it keeps this log too,
-- under its anonymised participant. Predictions written before this
-- migration have no rows here: their history starts with their next write.
--
-- Apply BEFORE pushing. Safe to re-run.
-- ============================================================================

begin;

create table if not exists prediction.fixture_prediction_changes (
  id              bigint generated always as identity primary key,
  prediction_id   uuid        not null,
  fixture_id      uuid        not null,
  participant_id  uuid        not null,
  op              text        not null,
  old_home        integer,
  old_away        integer,
  old_double      boolean,
  new_home        integer,
  new_away        integer,
  new_double      boolean,
  old_fixture_id  uuid,
  changed_at      timestamptz not null default clock_timestamp(),
  source          text,
  constraint fixture_prediction_changes_op_known
    check (op in ('insert', 'update', 'delete'))
);

comment on table prediction.fixture_prediction_changes is
  'Every write of a prediction (0211): the score and double before and '
  'after, the time and the statement. Append-only, backend-only.';

create index if not exists fixture_prediction_changes_participant_idx
  on prediction.fixture_prediction_changes (participant_id, fixture_id);
create index if not exists fixture_prediction_changes_fixture_idx
  on prediction.fixture_prediction_changes (fixture_id);

create or replace function prediction.log_fixture_prediction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into prediction.fixture_prediction_changes
      (prediction_id, fixture_id, participant_id, op,
       new_home, new_away, new_double, source)
    values (new.id, new.fixture_id, new.participant_id, 'insert',
            new.home_goals, new.away_goals, new.is_double,
            left(current_query(), 200));
    return new;
  elsif tg_op = 'UPDATE' then
    insert into prediction.fixture_prediction_changes
      (prediction_id, fixture_id, participant_id, op,
       old_home, old_away, old_double, new_home, new_away, new_double,
       old_fixture_id, source)
    values (new.id, new.fixture_id, new.participant_id, 'update',
            old.home_goals, old.away_goals, old.is_double,
            new.home_goals, new.away_goals, new.is_double,
            case when old.fixture_id is distinct from new.fixture_id
                 then old.fixture_id end,
            left(current_query(), 200));
    return new;
  end if;
  insert into prediction.fixture_prediction_changes
    (prediction_id, fixture_id, participant_id, op,
     old_home, old_away, old_double, source)
  values (old.id, old.fixture_id, old.participant_id, 'delete',
          old.home_goals, old.away_goals, old.is_double,
          left(current_query(), 200));
  return old;
end;
$$;

revoke all on function prediction.log_fixture_prediction_change()
  from public, anon, authenticated;

drop trigger if exists fixture_predictions_z_change_log
  on prediction.fixture_predictions;
create trigger fixture_predictions_z_change_log
  after insert or update or delete on prediction.fixture_predictions
  for each row execute function prediction.log_fixture_prediction_change();

create or replace function prediction.reject_prediction_change_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'prediction.fixture_prediction_changes is append-only'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists fixture_prediction_changes_append_only
  on prediction.fixture_prediction_changes;
create trigger fixture_prediction_changes_append_only
  before update or delete on prediction.fixture_prediction_changes
  for each row execute function prediction.reject_prediction_change_mutation();

alter table prediction.fixture_prediction_changes enable row level security;
revoke all on prediction.fixture_prediction_changes from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0211_prediction_change_log')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0211_prediction_change_log';                      -- 1 row
-- select tgname from pg_trigger
--  where tgrelid = 'prediction.fixture_predictions'::regclass
--    and tgname = 'fixture_predictions_z_change_log';                  -- 1 row
-- select count(*) from prediction.fixture_prediction_changes;          -- grows
