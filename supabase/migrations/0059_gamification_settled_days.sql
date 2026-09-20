-- ============================================================================
-- Migration 0059: settled match days (P1-5)
--
-- The streak calendar used to derive "match days" live from the current
-- fixture schedule, so moving, adding or removing a fixture re-wrote days that
-- were already over: a postponed match hid its old day and shortened every
-- streak that ran through it. From now on a Riyadh day that has ended is
-- settled ONCE, here, with the number of fixtures it had, and the calendar
-- reads a settled day exactly as it was frozen.
--
-- One row per Riyadh day, INCLUDING days with no fixture (fixture_count = 0):
-- the newest row is therefore the watermark "settled through here", and only
-- the days after it are still computed live. With an empty table, or if the
-- nightly job stops, the calendar behaves exactly as it did before.
--
-- Append-only (revoked UPDATE/DELETE plus an immutability trigger) and
-- server-only: no policy and no grant for anon or authenticated.
--
-- Forward-only, additive, guarded. Safe to re-run.
-- ============================================================================

begin;

create table if not exists gamification.settled_days (
  day           date        primary key,
  fixture_count integer     not null,
  settled_at    timestamptz not null default now(),
  constraint settled_days_fixture_count_nonneg
    check (fixture_count >= 0)
);

comment on table gamification.settled_days is
  'One row per Riyadh calendar day that has ended (P1-5), with the number of '
  'fixtures that kicked off in it when it was settled. Includes days with no '
  'fixture, so the newest row is the "settled through" watermark. Append-only '
  'and server-only: the streak calendar reads it, nothing else does.';

comment on column gamification.settled_days.fixture_count is
  'Fixtures scheduled in the day at the moment it was settled. Frozen: a '
  'fixture moved, added or removed later does not change it.';

create or replace function gamification.reject_settled_day_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception
      'gamification.settled_days is append-only: UPDATE is forbidden'
      using errcode = 'check_violation';
  elsif tg_op = 'DELETE' then
    raise exception
      'gamification.settled_days is append-only: DELETE is forbidden'
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

comment on function gamification.reject_settled_day_mutation() is
  'Append-only backstop: rejects any UPDATE or DELETE on '
  'gamification.settled_days for every role, including the service role that '
  'bypasses RLS.';

drop trigger if exists settled_days_reject_mutation
  on gamification.settled_days;
create trigger settled_days_reject_mutation
  before update or delete on gamification.settled_days
  for each row
  execute function gamification.reject_settled_day_mutation();

alter table gamification.settled_days enable row level security;

revoke all on gamification.settled_days from anon, authenticated;

commit;
