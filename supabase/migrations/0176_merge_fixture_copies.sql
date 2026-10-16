-- ============================================================================
-- Migration 0176: merge two copies of one match (script 95)
--
-- ADDITIVE ONLY. One enum value, one table, two trigger functions (one new,
-- one replaced with the same name and trigger), one new trigger and one
-- function. No existing row is written, changed or removed by the migration
-- itself.
--
-- Why: on 2026-10-15/16 the sync and an admin added several Europa League
-- matches twice. Some players predicted one copy, some the other; hiding a
-- copy took its predictions out of sight with it, and the fixes by hand had
-- to switch the triggers off to move them. Decided by the owner on
-- 2026-10-16: an admin merges a copy into the one kept, from the panel, in
-- one transaction, with every trigger on.
--
-- competition.merge_fixture_copies(duplicate, kept, actor, apply):
--   * refuses: the same fixture twice, a fixture with no schedule, a test
--     fixture, a kept copy that is hidden, a copy already merged, and two
--     fixtures that are not one match -- no club in common (the same
--     catalog team or the same name key, 0110) or kickoffs 12 hours apart
--     or more (0175). check_violation, constraint fixture_merge_*.
--   * moves to the kept copy, as it is (the same id, scoreline,
--     submitted_at and double), each prediction of the copy whose player
--     did not predict the kept copy, sent before the kept copy's kickoff,
--     by a participant of a season the kept copy belongs to. One whose
--     player already has another double on a shown match of the kept
--     copy's Riyadh day moves without its double (one double a day, 0079);
--     it is counted in doubles_dropped.
--   * the others stay on the copy: both_predicted, late, not_participant.
--   * hides the copy (0098) before moving anything, so its doubles no
--     longer count (0172), and hands the copy's provider link to the kept
--     copy when the kept copy has none, so the results sync asks about it.
--   * writes the audit row (fixtures_merged, target the copy, the counts
--     in the reason) and the fixture_merges row, in the same transaction.
--   With apply false nothing is written: the counts of what it would do.
--
-- A merged copy is never shown again (fixture_schedules_merged): scores or
-- ledger entries it had before it was hidden stay on it, off every board
-- (0107), and showing it would count them a second time.
--
-- The kickoff lock (prediction.reject_fixture_write_after_kickoff) lets
-- one write through after kickoff: a prediction moved from a copy to the
-- kept copy, inside the transaction that recorded that merge, sent before
-- the kept copy's kickoff. Nothing else changes in it; every other trigger
-- applies to the move unchanged.
--
-- The server scores the kept copy again when it has a result (ScoreFixture
-- then PostFixtureToLedger, AdminMergeFixtureCopies).
--
-- Apply BEFORE deploying the server that calls it. Safe to re-run.
-- ============================================================================

begin;

alter type admin.audit_action
  add value if not exists 'fixtures_merged';

-- ---------------------------------------------------------------------------
-- 1. the merges
-- ---------------------------------------------------------------------------
create table if not exists competition.fixture_merges (
  duplicate_fixture_id uuid primary key
    references competition.fixture_schedules (fixture_id),
  kept_fixture_id      uuid not null
    references competition.fixture_schedules (fixture_id),
  merged_by            uuid not null references identity.users (id),
  merged_at            timestamptz not null default now(),
  merged_txid          bigint not null default txid_current(),
  moved                integer not null default 0,
  doubles_dropped      integer not null default 0,
  constraint fixture_merges_two_fixtures
    check (duplicate_fixture_id <> kept_fixture_id)
);

create index if not exists fixture_merges_kept_idx
  on competition.fixture_merges (kept_fixture_id);

comment on table competition.fixture_merges is
  'One row per copy of a match merged into the copy kept (0176). A merged '
  'copy stays hidden for good.';

alter table competition.fixture_merges enable row level security;
revoke all on competition.fixture_merges from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. the kickoff lock lets a merge move its predictions
-- ---------------------------------------------------------------------------
create or replace function prediction.reject_fixture_write_after_kickoff()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  fixture_kickoff timestamptz;
begin
  select kickoff_at into fixture_kickoff
  from competition.fixture_schedules
  where fixture_id = new.fixture_id;

  if fixture_kickoff is null then
    raise exception
      'fixture predictions require a registered kickoff (fixture % has no '
      'schedule row)',
      new.fixture_id
      using errcode = 'check_violation';
  end if;

  -- A prediction moved by a merge (0176): only inside the transaction that
  -- recorded that merge, from the copy to the kept copy, nothing else
  -- changed, and sent before the kept copy's kickoff.
  if tg_op = 'UPDATE'
     and new.fixture_id <> old.fixture_id
     and new.id = old.id
     and new.participant_id = old.participant_id
     and new.home_goals = old.home_goals
     and new.away_goals = old.away_goals
     and new.submitted_at = old.submitted_at
     and new.submitted_at < fixture_kickoff
     and exists (
       select 1
         from competition.fixture_merges m
        where m.duplicate_fixture_id = old.fixture_id
          and m.kept_fixture_id = new.fixture_id
          and m.merged_txid = txid_current()
     ) then
    return new;
  end if;

  if now() >= fixture_kickoff then
    raise exception
      'fixture predictions can only be written before kickoff (fixture % '
      'kicked off at %)',
      new.fixture_id, fixture_kickoff
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. a merged copy is never shown again
-- ---------------------------------------------------------------------------
create or replace function competition.reject_showing_merged_copy()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.hidden_at is null
     and exists (
       select 1
         from competition.fixture_merges m
        where m.duplicate_fixture_id = new.fixture_id
     ) then
    raise exception 'fixture % was merged into another copy', new.fixture_id
      using errcode = 'check_violation',
            constraint = 'fixture_schedules_merged';
  end if;
  return new;
end;
$$;

drop trigger if exists fixture_schedules_merged
  on competition.fixture_schedules;
create trigger fixture_schedules_merged
  before update of hidden_at on competition.fixture_schedules
  for each row execute function competition.reject_showing_merged_copy();

-- ---------------------------------------------------------------------------
-- 4. the merge
-- ---------------------------------------------------------------------------
create or replace function competition.merge_fixture_copies(
  p_duplicate uuid,
  p_kept      uuid,
  p_actor     uuid,
  p_apply     boolean
)
returns table (
  moved           integer,
  doubles_moved   integer,
  doubles_dropped integer,
  both_predicted  integer,
  late            integer,
  not_participant integer,
  link_moved      boolean,
  kept_has_result boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dup        competition.fixture_schedules%rowtype;
  v_kept       competition.fixture_schedules%rowtype;
  v_day_start  timestamptz;
  v_link_moved boolean := false;
begin
  if p_duplicate is null or p_kept is null or p_duplicate = p_kept then
    raise exception 'a fixture is merged into another one'
      using errcode = 'check_violation', constraint = 'fixture_merge_same';
  end if;

  -- Both rows locked, the lesser id first, so two merges never deadlock.
  perform 1
     from competition.fixture_schedules s
    where s.fixture_id in (p_duplicate, p_kept)
    order by s.fixture_id
      for update;

  select * into v_dup from competition.fixture_schedules s
   where s.fixture_id = p_duplicate;
  select * into v_kept from competition.fixture_schedules s
   where s.fixture_id = p_kept;

  if v_dup.fixture_id is null or v_kept.fixture_id is null then
    raise exception 'fixture % or % has no schedule', p_duplicate, p_kept
      using errcode = 'check_violation', constraint = 'fixture_merge_not_found';
  end if;
  if v_dup.is_test or v_kept.is_test then
    raise exception 'a test fixture is never merged'
      using errcode = 'check_violation', constraint = 'fixture_merge_test';
  end if;
  if v_kept.hidden_at is not null then
    raise exception 'the kept copy % is hidden', p_kept
      using errcode = 'check_violation', constraint = 'fixture_merge_kept_hidden';
  end if;
  if exists (select 1 from competition.fixture_merges m
              where m.duplicate_fixture_id = p_duplicate) then
    raise exception 'fixture % is already merged', p_duplicate
      using errcode = 'check_violation', constraint = 'fixture_merge_already_merged';
  end if;
  if not (
       v_dup.kickoff_at > v_kept.kickoff_at - interval '12 hours'
       and v_dup.kickoff_at < v_kept.kickoff_at + interval '12 hours'
       and coalesce(
             (v_dup.home_team_id is not null
                and v_dup.home_team_id in (v_kept.home_team_id, v_kept.away_team_id))
             or (v_dup.away_team_id is not null
                and v_dup.away_team_id in (v_kept.home_team_id, v_kept.away_team_id))
             or competition.team_name_key(v_dup.home_team) in (
                  competition.team_name_key(v_kept.home_team),
                  competition.team_name_key(v_kept.away_team))
             or competition.team_name_key(v_dup.away_team) in (
                  competition.team_name_key(v_kept.home_team),
                  competition.team_name_key(v_kept.away_team)),
             false)) then
    raise exception 'fixtures % and % are not one match', p_duplicate, p_kept
      using errcode = 'check_violation', constraint = 'fixture_merge_not_copies';
  end if;

  v_day_start := date_trunc('day', v_kept.kickoff_at, 'Asia/Riyadh');

  -- What happens to each prediction of the copy.
  if to_regclass('pg_temp.fixture_merge_plan') is null then
    create temporary table fixture_merge_plan (
      prediction_id uuid primary key,
      verdict       text not null,
      keeps_double  boolean not null,
      was_double    boolean not null
    ) on commit drop;
  end if;
  delete from pg_temp.fixture_merge_plan;

  insert into pg_temp.fixture_merge_plan
  select fp.id,
         case
           when exists (select 1 from prediction.fixture_predictions k
                         where k.fixture_id = p_kept
                           and k.participant_id = fp.participant_id)
             then 'both_predicted'
           when fp.submitted_at >= v_kept.kickoff_at
             then 'late'
           when not exists (
                  select 1
                    from competition.participants pa
                    join competition.season_fixtures sf
                      on sf.season_id = pa.season_id
                   where pa.id = fp.participant_id
                     and sf.fixture_id = p_kept)
             then 'not_participant'
           else 'move'
         end,
         fp.is_double and not exists (
           select 1
             from prediction.fixture_predictions o
             join competition.fixture_schedules os on os.fixture_id = o.fixture_id
            where o.participant_id = fp.participant_id
              and o.is_double
              and o.fixture_id not in (p_duplicate, p_kept)
              and os.hidden_at is null
              and os.kickoff_at >= v_day_start
              and os.kickoff_at < v_day_start + interval '24 hours'),
         fp.is_double
    from prediction.fixture_predictions fp
   where fp.fixture_id = p_duplicate;

  if p_apply then
    insert into competition.fixture_merges
      (duplicate_fixture_id, kept_fixture_id, merged_by)
    values (p_duplicate, p_kept, p_actor);

    -- Hidden first: its doubles stop counting (0172) before any moves.
    update competition.fixture_schedules s
       set hidden_at = now()
     where s.fixture_id = p_duplicate
       and s.hidden_at is null;

    update prediction.fixture_predictions fp
       set fixture_id = p_kept,
           is_double  = pl.keeps_double
      from pg_temp.fixture_merge_plan pl
     where pl.prediction_id = fp.id
       and pl.verdict = 'move';

    if not exists (select 1 from football_data.external_identity_map m
                    where m.canonical_table = 'fixture'
                      and m.canonical_id = p_kept) then
      update football_data.external_identity_map m
         set canonical_id = p_kept
       where m.canonical_table = 'fixture'
         and m.canonical_id = p_duplicate;
      v_link_moved := found;
    end if;
  end if;

  select count(*) filter (where pl.verdict = 'move')::integer,
         count(*) filter (where pl.verdict = 'move' and pl.keeps_double)::integer,
         count(*) filter (where pl.verdict = 'move' and pl.was_double
                            and not pl.keeps_double)::integer,
         count(*) filter (where pl.verdict = 'both_predicted')::integer,
         count(*) filter (where pl.verdict = 'late')::integer,
         count(*) filter (where pl.verdict = 'not_participant')::integer
    into moved, doubles_moved, doubles_dropped,
         both_predicted, late, not_participant
    from pg_temp.fixture_merge_plan pl;

  link_moved      := v_link_moved;
  kept_has_result := exists (select 1 from scoring.fixture_results fr
                              where fr.fixture_id = p_kept);

  if p_apply then
    update competition.fixture_merges m
       set moved = merge_fixture_copies.moved,
           doubles_dropped = merge_fixture_copies.doubles_dropped
     where m.duplicate_fixture_id = p_duplicate;

    insert into admin.audit_log (id, actor_id, action, target_ref, reason)
    values (
      gen_random_uuid(), p_actor, 'fixtures_merged', p_duplicate::text,
      format('into %s: moved %s (doubles %s, doubles dropped %s), '
             'both predicted %s, late %s, not in the season %s%s',
             p_kept, moved, doubles_moved, doubles_dropped,
             both_predicted, late, not_participant,
             case when v_link_moved then ', provider link moved' else '' end));
  end if;

  delete from pg_temp.fixture_merge_plan;
  return next;
end;
$$;

comment on function competition.merge_fixture_copies(uuid, uuid, uuid, boolean) is
  'Merges a copy of a match into the copy kept (0176): moves the copy''s '
  'predictions that may move, hides the copy for good, hands over its '
  'provider link and audits it, in one transaction; with p_apply false, '
  'the counts only. Called by AdminMergeFixtureCopies.';

revoke all on function competition.merge_fixture_copies(uuid, uuid, uuid, boolean)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0176_merge_fixture_copies')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0176_merge_fixture_copies';                    -- 1 row
-- select count(*) from competition.fixture_merges;                 -- 0
-- select tgname from pg_trigger
--  where tgname = 'fixture_schedules_merged';                      -- 1 row
