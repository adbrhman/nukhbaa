-- ============================================================================
-- Migration 0098: hidden and test fixtures
--
-- ADDITIVE ONLY. Two columns, two audit actions, four guard triggers, one
-- function replaced (same name, arguments and result). No row is deleted or
-- rewritten.
--
-- * hidden_at -- set by an admin to pull a fixture out of sight at once
--   (a wrong team, a wrong kickoff) and cleared to bring it back. Nothing
--   attached to the fixture is deleted: its predictions, result, scores and
--   ledger entries stay as they are. While hidden, no prediction can be
--   written and no score computed; the rescore sweep picks it up again once
--   it is shown.
-- * is_test -- chosen when the fixture is registered, never changed after.
--   Only an admin may predict it, and it never produces a score or a
--   ledger entry, so it can never reach a board, a prize or a champion.
--
-- The server enforces both rules first (FixtureVisibility in the
-- application layer); these triggers are the backstop (Axiom 6).
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table competition.fixture_schedules
  add column if not exists hidden_at timestamptz,
  add column if not exists is_test boolean not null default false;

comment on column competition.fixture_schedules.hidden_at is
  'When an admin hid the fixture from players (0098); null while visible.';
comment on column competition.fixture_schedules.is_test is
  'A test fixture (0098): admins only, never scored, never in the ledger. '
  'Fixed at registration.';

-- Hiding and showing are audited (AdminSetFixturesHidden).
alter type admin.audit_action add value if not exists 'fixture_hidden';
alter type admin.audit_action add value if not exists 'fixture_shown';

-- ---------------------------------------------------------------------------
-- 1. is_test is fixed at registration
-- ---------------------------------------------------------------------------
create or replace function competition.freeze_fixture_is_test()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_test is distinct from old.is_test then
    raise exception 'fixture % : is_test is fixed at registration',
      old.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_schedules_is_test_fixed';
  end if;
  return new;
end;
$$;

drop trigger if exists fixture_schedules_freeze_is_test
  on competition.fixture_schedules;
create trigger fixture_schedules_freeze_is_test
  before update of is_test on competition.fixture_schedules
  for each row execute function competition.freeze_fixture_is_test();

-- ---------------------------------------------------------------------------
-- 2. no prediction on a hidden fixture; a test fixture is for admins only
-- ---------------------------------------------------------------------------
create or replace function prediction.reject_unavailable_fixture_prediction()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_hidden_at timestamptz;
  v_is_test   boolean;
begin
  select fs.hidden_at, fs.is_test
    into v_hidden_at, v_is_test
    from competition.fixture_schedules fs
   where fs.fixture_id = new.fixture_id;

  if v_hidden_at is not null then
    raise exception 'fixture % is hidden', new.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_predictions_fixture_hidden';
  end if;

  if coalesce(v_is_test, false) and not exists (
    select 1
      from competition.participants p
      join identity.users u on u.id = p.user_id
     where p.id = new.participant_id
       and u.role = 'admin'
  ) then
    raise exception 'fixture % is a test fixture', new.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_predictions_test_fixture_admins_only';
  end if;

  return new;
end;
$$;

drop trigger if exists fixture_predictions_reject_unavailable
  on prediction.fixture_predictions;
create trigger fixture_predictions_reject_unavailable
  before insert or update on prediction.fixture_predictions
  for each row execute function prediction.reject_unavailable_fixture_prediction();

-- ---------------------------------------------------------------------------
-- 3. no score for a test fixture, nor for a hidden one
-- ---------------------------------------------------------------------------
create or replace function scoring.reject_unavailable_fixture_score()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
      from competition.fixture_schedules fs
     where fs.fixture_id = new.fixture_id
       and (fs.is_test or fs.hidden_at is not null)
  ) then
    raise exception 'fixture % is hidden or a test fixture', new.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_scores_fixture_unavailable';
  end if;
  return new;
end;
$$;

drop trigger if exists fixture_scores_reject_unavailable
  on scoring.fixture_scores;
create trigger fixture_scores_reject_unavailable
  before insert or update on scoring.fixture_scores
  for each row execute function scoring.reject_unavailable_fixture_score();

-- ---------------------------------------------------------------------------
-- 4. no ledger entry for a test fixture
-- ---------------------------------------------------------------------------
create or replace function ledger.reject_test_fixture_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
      from competition.fixture_schedules fs
     where fs.fixture_id = new.fixture_id
       and fs.is_test
  ) then
    raise exception 'fixture % is a test fixture', new.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_point_entries_test_fixture';
  end if;
  return new;
end;
$$;

drop trigger if exists fixture_point_entries_reject_test_fixture
  on ledger.fixture_point_entries;
create trigger fixture_point_entries_reject_test_fixture
  before insert on ledger.fixture_point_entries
  for each row execute function ledger.reject_test_fixture_entry();

-- ---------------------------------------------------------------------------
-- 5. the rescore sweep leaves test and hidden fixtures alone
-- ---------------------------------------------------------------------------
create or replace function scoring.fixtures_with_unscored_predictions(
  p_recorded_from   timestamptz,
  p_recorded_before timestamptz,
  p_limit           integer
)
returns table (fixture_id uuid)
language sql
stable
set search_path = ''
as $$
  select r.fixture_id
    from scoring.fixture_results r
   where r.recorded_at >= p_recorded_from
     and r.recorded_at < p_recorded_before
     and not exists (
       select 1
         from competition.fixture_schedules fs
        where fs.fixture_id = r.fixture_id
          and (fs.is_test or fs.hidden_at is not null)
     )
     and (
       exists (
         select 1
           from prediction.fixture_predictions fp
          where fp.fixture_id = r.fixture_id
            and not exists (
              select 1
                from scoring.fixture_scores s
               where s.fixture_id = fp.fixture_id
                 and s.participant_id = fp.participant_id
            )
       )
       or exists (
         select 1
           from scoring.fixture_scores s
          where s.fixture_id = r.fixture_id
            and s.points is distinct from (
              select sum(e.amount)
                from ledger.fixture_point_entries e
               where e.fixture_id = s.fixture_id
                 and e.participant_id = s.participant_id
                 and e.entry_kind in ('fixture_score', 'correction')
            )
       )
     )
   order by r.recorded_at, r.fixture_id
   limit greatest(p_limit, 0);
$$;

comment on function scoring.fixtures_with_unscored_predictions(timestamptz, timestamptz, integer) is
  'Fixtures whose result was recorded in [from, before) and that still hold '
  'a prediction with no fixture_scores row (0080), or a score the ledger '
  'does not match (0082). Test and hidden fixtures are left out (0098). '
  'Read by the rescore sweep.';

insert into ops.applied_migrations (version)
values ('0098_fixture_visibility')
on conflict (version) do nothing;

commit;
