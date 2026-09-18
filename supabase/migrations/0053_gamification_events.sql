-- ============================================================================
-- Migration 0053: gamification.events — the append-only event stream (P0-2)
--
-- ADDITIVE ONLY. One new schema, one table, one trigger, one function. No
-- existing table is touched, no column is added elsewhere, nothing is deleted.
--
-- ## What this table is, and what it is NOT
-- It is the audit stream every event-driven engine of the gamification plan
-- reads: streaks (P1), badges (P2), notification triggers (P3), insights (P4).
--
-- It is NOT a second points ledger. `ledger.fixture_point_entries` (0020) and
-- `ledger.point_entries` (0005) remain the ONLY source of points and standings.
-- A new kind of award (daily challenge, streak bonus, badge) is a new value of
-- `ledger.entry_kind` plus one entry in that ledger — never an amount stored
-- here. Two ledgers would mean two disagreeing standings, which is the exact
-- dual-scoring-path risk the Axiom 4 Amendment closed once already. A row here
-- may REFERENCE the ledger entry it caused, via ref_type/ref_id.
--
-- ## Append-only, mirroring 0005
-- UPDATE and DELETE are revoked from every non-owner role AND rejected by
-- `gamification.reject_event_mutation()`, which fires for ANY role including
-- the backend service role that bypasses RLS. A wrong event is corrected by a
-- new compensating event, never by an edit.
--
-- ## Idempotency
-- `dedupe_key` is unique and NOT NULL: the emitter composes it from whatever
-- makes the event unique in its own terms — 'prediction_placed:<prediction_id>',
-- 'streak_extended:<user_id>:<local_date>', 'badge_unlocked:<user_id>:<code>'.
-- Re-running a nightly job or replaying a scoring pass therefore inserts
-- nothing the second time (23505), exactly as `sync_runs` (0051) guards the
-- provider sync. Every job that writes here MUST be safe to re-run.
--
-- ## event_type is text, not an enum — a deliberate deviation
-- The project's convention is a Postgres enum (ledger.entry_kind,
-- identity.platform_role). Here the vocabulary grows with every phase of the
-- plan, and 0020 documents the cost: Postgres refuses to use an enum value in
-- the same transaction that added it (SQLSTATE 55P04), so each new value would
-- need its own migration, separate from the one that uses it. The authoritative
-- vocabulary therefore lives in the domain layer, where the plan already puts
-- its rules; the database keeps a non-blank check as its backstop.
--
-- ## rule_version
-- Fixed at 1 by default. Decided 2026-09-19: gamification starts at the date
-- the system is switched on — there is NO backfill from predictions made
-- before it, and no historical rows are written for 2026-09-05..2026-09-19.
-- A future change of the point rules is a NEW rule_version, never a rewrite of
-- past events (they are immutable in any case).
-- ============================================================================

begin;

create schema if not exists gamification;

comment on schema gamification is
  'Gamification-owned. The append-only event stream that the streak, badge, '
  'notification and insight engines read. Points themselves live in ledger.*, '
  'never here.';

create table if not exists gamification.events (
  id           uuid primary key,
  user_id      uuid not null
    constraint events_user_id_fkey
      references identity.users (id) on delete cascade,
  event_type   text not null,
  payload      jsonb not null default '{}'::jsonb,
  -- What this event is about: 'fixture', 'prediction', 'ledger_entry',
  -- 'badge', 'weekly_league', or null for an event about nothing but the user.
  ref_type     text,
  ref_id       uuid,
  dedupe_key   text not null,
  rule_version integer not null default 1,
  occurred_at  timestamptz not null,
  created_at   timestamptz not null default now(),
  constraint events_event_type_nonblank
    check (btrim(event_type) <> ''),
  constraint events_dedupe_key_nonblank
    check (btrim(dedupe_key) <> ''),
  constraint events_rule_version_positive
    check (rule_version >= 1),
  constraint events_ref_pairing
    check ((ref_type is null) = (ref_id is null)),
  constraint events_dedupe_key_uniq
    unique (dedupe_key)
);

comment on table gamification.events is
  'Append-only gamification event stream (P0-2). One row per meaningful act: '
  'a prediction placed, a prediction settled, a streak extended or frozen, a '
  'badge unlocked, a league promotion. Immutable (revoked UPDATE/DELETE + an '
  'immutability trigger). Carries NO points: an award is a ledger entry, and '
  'this row may point at it through ref_type/ref_id.';

comment on column gamification.events.dedupe_key is
  'The emitter''s idempotency key. Unique: re-running a job that emits the '
  'same event a second time raises 23505 and writes nothing, so every '
  'scheduled job here is safe to re-run.';

comment on column gamification.events.rule_version is
  'Which generation of the point rules produced this event. 1 is the system '
  'switch-on generation; no rows exist for predictions made before it.';

-- The engines read "this user's recent events", and the badge evaluator reads
-- "this user's events of one type": both are served by this index.
create index if not exists events_user_type_occurred_idx
  on gamification.events (user_id, event_type, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Append-only backstop, mirroring ledger.reject_entry_mutation (0005).
-- ---------------------------------------------------------------------------
create or replace function gamification.reject_event_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception
      'gamification.events is append-only: UPDATE is forbidden'
      using errcode = 'check_violation';
  elsif tg_op = 'DELETE' then
    raise exception
      'gamification.events is append-only: DELETE is forbidden'
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

comment on function gamification.reject_event_mutation() is
  'Append-only backstop: rejects any UPDATE or DELETE on gamification.events '
  'for every role, including the service role that bypasses RLS.';

drop trigger if exists events_reject_mutation on gamification.events;
create trigger events_reject_mutation
  before update or delete on gamification.events
  for each row
  execute function gamification.reject_event_mutation();

-- ---------------------------------------------------------------------------
-- RLS: the backend (service role) writes; a signed-in user reads only their
-- own rows; anon reads nothing. Mirrors ledger.fixture_point_entries (0020).
-- ---------------------------------------------------------------------------
alter table gamification.events enable row level security;

revoke insert, update, delete, truncate
  on gamification.events from anon, authenticated;

grant usage on schema gamification to authenticated;
grant select on gamification.events to authenticated;

drop policy if exists events_select_own on gamification.events;
create policy events_select_own
  on gamification.events
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists events_anon_no_access on gamification.events;
create policy events_anon_no_access
  on gamification.events
  for select
  to anon
  using (false);

commit;

-- Verification:
-- select count(*) from gamification.events;                      -- 0
-- update gamification.events set event_type = 'x';               -- must fail
-- select relrowsecurity from pg_class
--  where oid = 'gamification.events'::regclass;                  -- t
