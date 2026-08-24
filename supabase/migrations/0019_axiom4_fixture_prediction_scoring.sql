-- Migration 0019 — Axiom 4 Amendment, Phase 4 (Infrastructure expand):
-- physical backing for the per-fixture Prediction/Scoring contexts added in
-- Phases 1-3 (domain.FixturePrediction / ParticipantFixtureScore,
-- application.SubmitFixturePrediction / ScoreFixture).
--
-- Three new tables, ALL additive (Platform ADR: forward-only, expand-only).
-- Nothing here touches prediction.predictions, prediction.prediction_scores,
-- scoring.round_scores, scoring.round_score_fixtures, competition.rounds, or
-- competition.round_fixtures — the round-scoped tables and their RLS stay
-- exactly as they are until Phase 7 (contract).
--
--   1. competition.season_fixtures — the per-fixture sibling of
--      competition.round_fixtures (Axiom 3: the only place Competition names
--      a fixture, this time keyed by season instead of round).
--   2. prediction.fixture_predictions — the per-fixture sibling of
--      prediction.predictions/.prediction_scores, collapsed into ONE row per
--      (fixture, participant) because a fixture prediction is a single
--      scoreline, not a forecast over many fixtures.
--   3. scoring.fixture_scores — the per-fixture sibling of
--      scoring.round_scores/.round_score_fixtures, likewise one row per
--      (fixture, participant).
--
-- KNOWN GAP (carried over from the Phase 3 application-layer note in
-- ScoreFixture): the "at most one double per participant per UTC day" rule
-- spans MULTIPLE fixture_predictions rows joined against
-- competition.fixture_schedules.kickoff_at, which a single-table constraint
-- cannot express. It is enforced only in the application layer
-- (DailyDoublePolicy + FixturePredictionRepository.countDoublesOnDay) — NOT
-- backstopped in the database yet. Documented, not silently accepted.

-- ---------------------------------------------------------------------------
-- 1. competition.season_fixtures
-- ---------------------------------------------------------------------------
create table if not exists competition.season_fixtures (
  season_id     uuid not null
                references competition.seasons (id) on delete restrict,
  -- Opaque reference to the future Football-Data `Fixture` aggregate. NO FK
  -- yet (mirrors competition.round_fixtures.fixture_id); NO round reference
  -- (Axiom 4 Amendment: a season no longer groups fixtures through rounds).
  fixture_id    uuid not null,
  display_order integer not null,
  created_at    timestamptz not null default now(),
  constraint season_fixtures_order_nonneg check (display_order >= 0),
  -- A fixture is linked to a season at most once (natural key) — mirrors
  -- round_fixtures_pkey.
  constraint season_fixtures_pkey primary key (season_id, fixture_id)
);

comment on table competition.season_fixtures is
  'M:N link season <-> fixture (Axiom 4 Amendment; per-fixture sibling of '
  'competition.round_fixtures). fixture_id is an opaque reference to '
  'Football Data (no FK yet). display_order fixes feed presentation order.';

create index if not exists season_fixtures_fixture_idx
  on competition.season_fixtures (fixture_id);

alter table competition.season_fixtures enable row level security;

revoke insert, update, delete, truncate
  on competition.season_fixtures
  from anon, authenticated;

grant select on competition.season_fixtures to authenticated;

-- Readable by a signed-in user only when the owning season's competition is
-- public — mirrors round_fixtures_select_public exactly, minus the round hop.
drop policy if exists season_fixtures_select_public
  on competition.season_fixtures;
create policy season_fixtures_select_public
  on competition.season_fixtures
  for select
  to authenticated
  using (
    exists (
      select 1
      from competition.seasons s
      join competition.competitions c on c.id = s.competition_id
      where s.id = season_fixtures.season_id and c.visibility = 'public'
    )
  );

drop policy if exists season_fixtures_anon_no_access
  on competition.season_fixtures;
create policy season_fixtures_anon_no_access
  on competition.season_fixtures for select to anon using (false);

-- ---------------------------------------------------------------------------
-- 2. prediction.fixture_predictions
-- ---------------------------------------------------------------------------
create table if not exists prediction.fixture_predictions (
  id             uuid primary key,
  -- Opaque reference to the Football-Data fixture (no FK yet, Axiom 3).
  fixture_id     uuid not null,
  participant_id uuid not null
                 references competition.participants (id) on delete restrict,
  home_goals     integer not null,
  away_goals     integer not null,
  is_double      boolean not null default false,
  submitted_at   timestamptz not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint fixture_predictions_home_range
    check (home_goals >= 0 and home_goals <= 99),
  constraint fixture_predictions_away_range
    check (away_goals >= 0 and away_goals <= 99),
  -- EXACTLY one prediction per (participant, fixture) — the aggregate's
  -- natural key (Axiom 4 Amendment; replaces predictions_participant_round_uniq
  -- for the per-fixture path). SubmitFixturePrediction pivots on a violation
  -- here to converge a lost insert race into an amend.
  constraint fixture_predictions_participant_fixture_uniq
    unique (participant_id, fixture_id)
);

comment on table prediction.fixture_predictions is
  'A participant''s single forecast for a single fixture (Axiom 4 Amendment; '
  'per-fixture sibling of prediction.predictions + .prediction_scores, '
  'collapsed to one row since a fixture prediction is one scoreline). One row '
  'per (participant, fixture). No points here (Axioms 2/5). No round/season '
  'reference — the same prediction is reusable across ranking contexts, '
  'exactly like the round-scoped Prediction.';

create index if not exists fixture_predictions_fixture_idx
  on prediction.fixture_predictions (fixture_id);
create index if not exists fixture_predictions_participant_idx
  on prediction.fixture_predictions (participant_id);

drop trigger if exists fixture_predictions_set_updated_at
  on prediction.fixture_predictions;
create trigger fixture_predictions_set_updated_at
  before update on prediction.fixture_predictions
  for each row execute function identity.set_updated_at();

-- "No write after kickoff" backstop (Axiom 6) — the per-fixture sibling of
-- prediction.reject_write_after_lock. There is no round.status to check
-- anymore; the lock is the fixture's own kickoff_at (FixtureLock, Phase 1)
-- read from competition.fixture_schedules. A fixture with NO registered
-- schedule row is treated as not locked (mirrors SubmitFixturePrediction's
-- application-layer default), so the trigger only rejects when a schedule
-- row exists AND its kickoff_at has arrived/passed.
create or replace function prediction.reject_fixture_write_after_kickoff()
returns trigger
language plpgsql
as $$
declare
  fixture_kickoff timestamptz;
begin
  select kickoff_at into fixture_kickoff
  from competition.fixture_schedules
  where fixture_id = new.fixture_id;

  if fixture_kickoff is not null and now() >= fixture_kickoff then
    raise exception
      'fixture predictions can only be written before kickoff (fixture % '
      'kicked off at %)',
      new.fixture_id, fixture_kickoff
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists fixture_predictions_reject_write_after_kickoff
  on prediction.fixture_predictions;
create trigger fixture_predictions_reject_write_after_kickoff
  before insert or update on prediction.fixture_predictions
  for each row execute function prediction.reject_fixture_write_after_kickoff();

alter table prediction.fixture_predictions enable row level security;

revoke insert, update, delete, truncate
  on prediction.fixture_predictions
  from anon, authenticated;

grant select on prediction.fixture_predictions to authenticated;

-- Own prediction always visible; someone else's only once the fixture has
-- kicked off (mirrors predictions_select_own_or_locked, minus the round hop —
-- "locked" is now the fixture's own kickoff_at, missing schedule = not locked).
drop policy if exists fixture_predictions_select_own_or_locked
  on prediction.fixture_predictions;
create policy fixture_predictions_select_own_or_locked
  on prediction.fixture_predictions
  for select
  to authenticated
  using (
    exists (
      select 1
      from competition.participants pa
      where pa.id = fixture_predictions.participant_id
        and pa.user_id = auth.uid()
    )
    or exists (
      select 1
      from competition.fixture_schedules fs
      where fs.fixture_id = fixture_predictions.fixture_id
        and now() >= fs.kickoff_at
    )
  );

drop policy if exists fixture_predictions_anon_no_access
  on prediction.fixture_predictions;
create policy fixture_predictions_anon_no_access
  on prediction.fixture_predictions for select to anon using (false);

-- ---------------------------------------------------------------------------
-- 3. scoring.fixture_scores
-- ---------------------------------------------------------------------------
create table if not exists scoring.fixture_scores (
  fixture_id      uuid not null,
  participant_id  uuid not null
                  references competition.participants (id) on delete restrict,
  ruleset_version integer not null,
  grade           text not null,
  points          integer not null,
  scored_at       timestamptz not null default now(),
  constraint fixture_scores_points_nonneg check (points >= 0),
  -- No 'missed' here (Axiom 4 Amendment, Phase 3 note): a FixturePrediction
  -- always names the fixture it is for, so the "kicked off before ever
  -- predicted" case that 'missed' models cannot occur at this granularity.
  constraint fixture_scores_grade_valid
    check (grade in ('exact_scoreline', 'correct_outcome', 'incorrect',
                      'pending')),
  -- One score per (fixture, participant) — Axiom 4; ScoreFixture upserts in
  -- place on re-score, never a second row.
  constraint fixture_scores_pkey primary key (fixture_id, participant_id)
);

comment on table scoring.fixture_scores is
  'A single participant''s scored result for a single fixture (Axiom 4 '
  'Amendment; per-fixture sibling of scoring.round_scores + '
  '.round_score_fixtures, collapsed to one row). Server-computed only '
  '(Axioms 2/5). No round/season reference.';

create index if not exists fixture_scores_participant_idx
  on scoring.fixture_scores (participant_id);

alter table scoring.fixture_scores enable row level security;

revoke insert, update, delete, truncate
  on scoring.fixture_scores
  from anon, authenticated;

grant select on scoring.fixture_scores to authenticated;

-- Follows the same own-or-locked visibility as fixture_predictions.
drop policy if exists fixture_scores_select_own_or_locked
  on scoring.fixture_scores;
create policy fixture_scores_select_own_or_locked
  on scoring.fixture_scores
  for select
  to authenticated
  using (
    exists (
      select 1
      from competition.participants pa
      where pa.id = fixture_scores.participant_id
        and pa.user_id = auth.uid()
    )
    or exists (
      select 1
      from competition.fixture_schedules fs
      where fs.fixture_id = fixture_scores.fixture_id
        and now() >= fs.kickoff_at
    )
  );

drop policy if exists fixture_scores_anon_no_access
  on scoring.fixture_scores;
create policy fixture_scores_anon_no_access
  on scoring.fixture_scores for select to anon using (false);
