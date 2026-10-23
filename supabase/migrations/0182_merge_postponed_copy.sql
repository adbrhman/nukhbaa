-- ============================================================================
-- Migration 0182: merge a match put back to another day (script 137)
--
-- ADDITIVE ONLY. One function replaced (same name, same arguments, same
-- result, still security definer and closed to the clients). No row is
-- written, changed or removed by the migration itself.
--
-- Why: on 2026-10-23 the provider put Al-Ahli - Al-Khaleej back from 22
-- October 21:00 to 23 October 21:00 (Riyadh) after the first kickoff had
-- passed (provider_sync.kickoff_put_back_late). The admin hid the first
-- copy and added the match again on the 23rd; 27 players who predicted
-- only the first copy would get nothing. 0176 refuses to merge copies 12
-- hours apart or more, so their predictions could not move. Decided by the
-- owner on 2026-10-23: such a copy may be merged too.
--
-- competition.merge_fixture_copies also takes two fixtures as one match
-- when the kept copy is the same match put back:
--   * the same two catalog teams, home and away (home_team_id and
--     away_team_id, both set on both copies);
--   * the kept copy kicks off later, by 7 days at most;
--   * both copies belong to one season (the same monthly contest).
-- Everything else is 0176 unchanged: the predictions that move were all
-- sent before the copy's kickoff, so before the kept copy's; the kickoff
-- lock lets them through only inside the merge's transaction; the copy is
-- hidden for good; the audit row is written.
--
-- Apply BEFORE deploying the server that lists such copies
-- (PostgresFixtureMerger._copiesSql). Safe to re-run.
-- ============================================================================

begin;

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
  -- One match: kickoffs less than 12 hours apart with a club in common
  -- (0176), or the same match put back (0182): the same two catalog teams,
  -- home and away, the kept copy later by at most 7 days, both in one
  -- season.
  if not (
       (v_dup.kickoff_at > v_kept.kickoff_at - interval '12 hours'
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
             false))
       or (v_dup.home_team_id is not null
           and v_dup.away_team_id is not null
           and v_dup.home_team_id = v_kept.home_team_id
           and v_dup.away_team_id = v_kept.away_team_id
           and v_kept.kickoff_at > v_dup.kickoff_at
           and v_kept.kickoff_at <= v_dup.kickoff_at + interval '7 days'
           and exists (
             select 1
               from competition.season_fixtures a
               join competition.season_fixtures b on b.season_id = a.season_id
              where a.fixture_id = p_duplicate
                and b.fixture_id = p_kept))) then
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
  'Merges a copy of a match into the copy kept (0176), or a match put '
  'back up to 7 days into its later copy (0182): moves the copy''s '
  'predictions that may move, hides the copy for good, hands over its '
  'provider link and audits it, in one transaction; with p_apply false, '
  'the counts only. Called by AdminMergeFixtureCopies.';

revoke all on function competition.merge_fixture_copies(uuid, uuid, uuid, boolean)
  from public, anon, authenticated;

insert into ops.applied_migrations (version)
values ('0182_merge_postponed_copy')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0182_merge_postponed_copy';                    -- 1 row
-- select prosrc like '%interval ''7 days''%'
--   from pg_proc where proname = 'merge_fixture_copies';           -- true
