#!/usr/bin/env bash
# Phase 4 — Infrastructure + Migration expand (Axiom 4 Amendment).
# Additive only: new migration (season_fixtures, fixture_predictions,
# fixture_scores tables) + two new Postgres adapters + their hermetic unit
# tests, alongside everything from phases 1-3. composition_root.dart is
# deliberately UNTOUCHED — wiring is Phase 5 (Routes).
set -euo pipefail
cd "${1:-.}"

mkdir -p supabase/migrations
mkdir -p packages/infrastructure/lib/src/prediction
mkdir -p packages/infrastructure/lib/src/scoring
mkdir -p packages/infrastructure/test/prediction
mkdir -p packages/infrastructure/test/scoring

# ---------------------------------------------------------------------------
# supabase/migrations/0019_axiom4_fixture_prediction_scoring.sql
# ---------------------------------------------------------------------------
cat > 'supabase/migrations/0019_axiom4_fixture_prediction_scoring.sql' <<'NUKHBA_EOF'
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
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
// `postgres` exports its own `Result`; only its exception hierarchy is
// needed here (to read the SQLSTATE `code`/`constraintName` off a
// `ServerException`), so hide `Result` to keep `Result<T>` unambiguously
// our `shared` union — mirrors PostgresPredictionRepository.
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixturePredictionRepository] over
/// `prediction.fixture_predictions` (Axiom 4 Amendment; migration
/// `0019_axiom4_fixture_prediction_scoring.sql`) plus read-only projections of
/// `competition.season_fixtures` and `competition.fixture_schedules`, both
/// owned by earlier migrations.
///
/// The per-fixture sibling of [PostgresPredictionRepository] — same shape,
/// one row per (participant, fixture) instead of a parent + N child scores,
/// because a fixture prediction is a single scoreline.
///
/// Error mapping mirrors [PostgresPredictionRepository]:
/// * `fixture_predictions_participant_fixture_uniq` (`23505`) →
///   [ErrorKind.invariant] `prediction.already_submitted`.
/// * `fixture_predictions_participant_id_fkey` (`23503`) →
///   `prediction.not_a_participant`.
/// * A check/trigger rejection (`23514`, the "no write after kickoff"
///   backstop or a goal-range check) → `prediction.fixture_locked`.
/// * A genuinely transient/infrastructure failure stays [ErrorKind.transient].
///
/// All queries bind values through `@named` parameters (Security ADR §2).
final class PostgresFixturePredictionRepository
    implements FixturePredictionRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixturePredictionRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // findByFixtureAndParticipant
  // --------------------------------------------------------------------------

  static const String _selectByFixtureAndParticipantSql = '''
SELECT id, fixture_id, participant_id, home_goals, away_goals, is_double,
       submitted_at
FROM prediction.fixture_predictions
WHERE fixture_id = @fixture_id AND participant_id = @participant_id
''';

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    final result = await _connection.query(
      _selectByFixtureAndParticipantSql,
      parameters: {
        'fixture_id': fixture.value,
        'participant_id': participantId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      // Absence is a normal, successful "not yet predicted" outcome, exactly
      // like PostgresPredictionRepository.findByRoundAndParticipant.
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapOne(value.first),
    };
  }

  Result<FixturePredictionView?> _mapOne(Map<String, dynamic> row) {
    final idResult = PredictionId.tryParse(row['id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final homeGoals = row['home_goals'];
    final awayGoals = row['away_goals'];
    final isDouble = row['is_double'];

    if (idResult is Err<PredictionId>) {
      return Result.err(
        _corrupt('fixture_predictions', 'id', idResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt(
          'fixture_predictions',
          'fixture_id',
          fixtureResult.error.message,
        ),
      );
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'fixture_predictions',
          'participant_id',
          participantIdResult.error.message,
        ),
      );
    }
    if (homeGoals is! int) {
      return Result.err(
        _corrupt('fixture_predictions', 'home_goals', 'not an integer'),
      );
    }
    if (awayGoals is! int) {
      return Result.err(
        _corrupt('fixture_predictions', 'away_goals', 'not an integer'),
      );
    }
    if (isDouble is! bool) {
      return Result.err(
        _corrupt('fixture_predictions', 'is_double', 'not a boolean'),
      );
    }
    final submittedAtResult = _timestampOf(row, 'submitted_at');
    if (submittedAtResult is Err<DateTime>) {
      return Result.err(submittedAtResult.error);
    }

    final predictionResult = FixturePrediction.fromStored(
      id: (idResult as Ok<PredictionId>).value,
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      participantId: (participantIdResult as Ok<ParticipantId>).value,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );

    return Result.ok(
      FixturePredictionView(
        prediction: predictionResult,
        submittedAt: (submittedAtResult as Ok<DateTime>).value,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // save / update
  // --------------------------------------------------------------------------

  static const String _insertSql = '''
INSERT INTO prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double,
   submitted_at)
VALUES (@id, @fixture_id, @participant_id, @home_goals, @away_goals,
        @is_double, @submitted_at)
''';

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'id': prediction.id.value,
        'fixture_id': prediction.fixture.value,
        'participant_id': prediction.participantId.value,
        'home_goals': prediction.homeGoals,
        'away_goals': prediction.awayGoals,
        'is_double': prediction.isDouble,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      },
    );
    return _asVoid(result);
  }

  // Guarded on identity via RETURNING, exactly like
  // PostgresPredictionRepository.update: zero rows means the prediction no
  // longer exists (deleted between the use-case's read and this write).
  static const String _updateSql = '''
UPDATE prediction.fixture_predictions
SET home_goals = @home_goals,
    away_goals = @away_goals,
    is_double  = @is_double,
    submitted_at = @submitted_at
WHERE id = @id
RETURNING id
''';

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final result = await _connection.query(
      _updateSql,
      parameters: {
        'id': prediction.id.value,
        'home_goals': prediction.homeGoals,
        'away_goals': prediction.awayGoals,
        'is_double': prediction.isDouble,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.invariant(
                  'prediction.not_found',
                  'Prediction no longer exists',
                ),
              )
            : const Result.ok(null),
    };
  }

  // --------------------------------------------------------------------------
  // findSeasonFixture — read-only projection of competition.season_fixtures
  // --------------------------------------------------------------------------

  static const String _selectSeasonFixtureSql = '''
SELECT season_id, fixture_id, display_order
FROM competition.season_fixtures
WHERE season_id = @season_id AND fixture_id = @fixture_id
''';

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _selectSeasonFixtureSql,
      parameters: {'season_id': seasonId.value, 'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapSeasonFixture(value.first),
    };
  }

  Result<SeasonFixture?> _mapSeasonFixture(Map<String, dynamic> row) {
    final seasonIdResult = SeasonId.tryParse(row['season_id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final displayOrder = row['display_order'];

    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(
        _corrupt('season_fixtures', 'season_id', seasonIdResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt(
          'season_fixtures',
          'fixture_id',
          fixtureResult.error.message,
        ),
      );
    }
    if (displayOrder is! int) {
      return Result.err(
        _corrupt('season_fixtures', 'display_order', 'not an integer'),
      );
    }

    return Result.ok(
      SeasonFixture.fromStored(
        seasonId: (seasonIdResult as Ok<SeasonId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        displayOrder: displayOrder,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //
  // Joins fixture_predictions -> competition.fixture_schedules to group
  // stored doubles by the UTC calendar day of their fixture's kickoff — a
  // fixture_prediction whose fixture has NO schedule row is excluded (it
  // cannot be attributed to any day), matching the "no schedule = not
  // locked" default the use-case applies on the write side.
  // --------------------------------------------------------------------------

  static const String _countDoublesSql = '''
SELECT count(*) AS n
FROM prediction.fixture_predictions fp
JOIN competition.fixture_schedules fs ON fs.fixture_id = fp.fixture_id
WHERE fp.participant_id = @participant_id
  AND fp.is_double = true
  AND fs.kickoff_at >= @day_start AND fs.kickoff_at < @day_end
  AND (@excluding_fixture_id::uuid IS NULL
       OR fp.fixture_id <> @excluding_fixture_id)
''';

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async {
    final dayStart = DateTime.utc(dayUtc.year, dayUtc.month, dayUtc.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final result = await _connection.query(
      _countDoublesSql,
      parameters: {
        'participant_id': participantId.value,
        'day_start': dayStart.toIso8601String(),
        'day_end': dayEnd.toIso8601String(),
        'excluding_fixture_id': excludingFixture?.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapCount(value),
    };
  }

  Result<int> _mapCount(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.ok(0);
    }
    final raw = rows.first['n'];
    if (raw is int) {
      return Result.ok(raw);
    }
    // The `postgres` driver may return count(*) as a BigInt-backed int; a
    // defensive numeric-string fallback covers a text-codec projection.
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) {
      return Result.ok(parsed);
    }
    return Result.err(_corrupt('fixture_predictions', 'count', 'not a count'));
  }

  // --------------------------------------------------------------------------
  // listByFixture — every participant's prediction for a fixture
  // --------------------------------------------------------------------------

  static const String _selectByFixtureSql = '''
SELECT id, fixture_id, participant_id, home_goals, away_goals, is_double,
       submitted_at
FROM prediction.fixture_predictions
WHERE fixture_id = @fixture_id
ORDER BY submitted_at ASC, id ASC
''';

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _selectByFixtureSql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapList(value),
    };
  }

  Result<List<FixturePredictionView>> _mapList(
    List<Map<String, dynamic>> rows,
  ) {
    final views = <FixturePredictionView>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<FixturePredictionView?>) {
        return Result.err(mapped.error);
      }
      final view = (mapped as Ok<FixturePredictionView?>).value;
      if (view != null) {
        views.add(view);
      }
    }
    return Result.ok(List<FixturePredictionView>.unmodifiable(views));
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror PostgresPredictionRepository)
  // --------------------------------------------------------------------------

  Result<DateTime> _timestampOf(Map<String, dynamic> row, String column) {
    final raw = row[column];
    if (raw is DateTime) {
      return Result.ok(raw.toUtc());
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return Result.ok(parsed.toUtc());
      }
    }
    return Result.err(
      _corrupt('fixture_predictions', column, 'not a timestamp'),
    );
  }

  Result<void> _asVoid(Result<List<Map<String, dynamic>>> result) {
    return switch (result) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
    };
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }

    final constraint = cause.constraintName;
    switch (constraint) {
      case 'fixture_predictions_participant_fixture_uniq':
        return const AppError.invariant(
          'prediction.already_submitted',
          'A prediction already exists for this participant and fixture',
        );
      case 'fixture_predictions_pkey':
        return const AppError.invariant(
          'prediction.duplicate_id',
          'A prediction with this id already exists',
        );
      case 'fixture_predictions_participant_id_fkey':
        return const AppError.invariant(
          'prediction.not_a_participant',
          'Participant not found',
        );
    }

    // The trigger-raised "no write after kickoff" check_violation carries no
    // constraint name — same pattern as prediction.round_not_open.
    if (code == '23514') {
      return const AppError.invariant(
        'prediction.fixture_locked',
        'Predictions can only be written before the fixture kicks off',
      );
    }
    return const AppError.invariant(
      'prediction.integrity_violation',
      'The write violated a fixture-prediction integrity rule',
    );
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'prediction.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/infrastructure/lib/src/scoring/postgres_fixture_score_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/infrastructure/lib/src/scoring/postgres_fixture_score_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureScoreRepository] over `scoring.fixture_scores`
/// (Axiom 4 Amendment; migration
/// `0019_axiom4_fixture_prediction_scoring.sql`) — the per-fixture sibling of
/// [PostgresScoreRepository], collapsed to a single flat table since a
/// fixture score has no per-fixture children (it *is* the per-fixture row).
///
/// Atomicity/idempotency: [saveFixtureScores] upserts every row for the
/// fixture in ONE batched statement (`unnest` + `ON CONFLICT (fixture_id,
/// participant_id) DO UPDATE`) — re-scoring the same fixture replaces each
/// participant's row in place, mirroring [PostgresScoreRepository]'s
/// round-level upsert.
///
/// All queries bind values through `@named` parameters (Security ADR §2).
final class PostgresFixtureScoreRepository implements FixtureScoreRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureScoreRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // saveFixtureScores — batched, idempotent upsert
  // --------------------------------------------------------------------------

  static const String _upsertSql = '''
INSERT INTO scoring.fixture_scores
  (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
SELECT fixture_id, participant_id, ruleset_version, grade, points, now()
FROM unnest(
  @fixture_ids::uuid[],
  @participant_ids::uuid[],
  @ruleset_versions::int[],
  @grades::text[],
  @points::int[]
) AS t(fixture_id, participant_id, ruleset_version, grade, points)
ON CONFLICT (fixture_id, participant_id) DO UPDATE SET
  ruleset_version = EXCLUDED.ruleset_version,
  grade           = EXCLUDED.grade,
  points          = EXCLUDED.points,
  scored_at       = EXCLUDED.scored_at
''';

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    if (scores.isEmpty) {
      return const Result.ok(null);
    }

    final fixtureIds = <String>[];
    final participantIds = <String>[];
    final rulesetVersions = <int>[];
    final grades = <String>[];
    final points = <int>[];

    for (final score in scores) {
      fixtureIds.add(score.fixture.value);
      participantIds.add(score.participantId.value);
      rulesetVersions.add(score.rulesetVersion);
      grades.add(score.result.grade.wireValue);
      points.add(score.points);
    }

    final result = await _connection.query(
      _upsertSql,
      parameters: {
        'fixture_ids': fixtureIds,
        'participant_ids': participantIds,
        'ruleset_versions': rulesetVersions,
        'grades': grades,
        'points': points,
      },
    );
    return _asVoid(result);
  }

  // --------------------------------------------------------------------------
  // listByFixture — every participant's score for a fixture, id-ordered
  // --------------------------------------------------------------------------

  static const String _selectByFixtureSql = '''
SELECT fixture_id, participant_id, ruleset_version, grade, points
FROM scoring.fixture_scores
WHERE fixture_id = @fixture_id
ORDER BY participant_id ASC
''';

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _selectByFixtureSql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapList(value),
    };
  }

  Result<List<ParticipantFixtureScore>> _mapList(
    List<Map<String, dynamic>> rows,
  ) {
    final scores = <ParticipantFixtureScore>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<ParticipantFixtureScore>) {
        return Result.err(mapped.error);
      }
      scores.add((mapped as Ok<ParticipantFixtureScore>).value);
    }
    return Result.ok(List<ParticipantFixtureScore>.unmodifiable(scores));
  }

  Result<ParticipantFixtureScore> _mapOne(Map<String, dynamic> row) {
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final rulesetVersion = row['ruleset_version'];
    final gradeResult = FixtureScoreGrade.tryParse(row['grade']?.toString());
    final points = row['points'];

    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt('fixture_scores', 'fixture_id', fixtureResult.error.message),
      );
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'fixture_scores',
          'participant_id',
          participantIdResult.error.message,
        ),
      );
    }
    if (rulesetVersion is! int) {
      return Result.err(
        _corrupt('fixture_scores', 'ruleset_version', 'not an integer'),
      );
    }
    if (gradeResult is Err<FixtureScoreGrade>) {
      return Result.err(
        _corrupt('fixture_scores', 'grade', gradeResult.error.message),
      );
    }
    if (points is! int) {
      return Result.err(
        _corrupt('fixture_scores', 'points', 'not an integer'),
      );
    }

    final fixture = (fixtureResult as Ok<FixtureRef>).value;
    return ParticipantFixtureScore.fromGraded(
      fixture: fixture,
      participantId: (participantIdResult as Ok<ParticipantId>).value,
      rulesetVersion: rulesetVersion,
      result: FixtureScoreResult(
        fixture: fixture,
        grade: (gradeResult as Ok<FixtureScoreGrade>).value,
        points: points,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror PostgresScoreRepository)
  // --------------------------------------------------------------------------

  Result<void> _asVoid(Result<List<Map<String, dynamic>>> result) {
    return switch (result) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
    };
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_scores_participant_id_fkey') {
      return const AppError.invariant(
        'scoring.not_a_participant',
        'Participant not found',
      );
    }
    return const AppError.invariant(
      'scoring.integrity_violation',
      'The write violated a fixture-score integrity rule',
    );
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'scoring.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/infrastructure/test/prediction/postgres_fixture_prediction_repository_test.dart
# (hermetic unit tests — fake PostgresConnection, same pattern as
# postgres_prediction_repository_test.dart; the ServerException reclassify
# branch is DB-only and deferred to a Phase-4-integration test, as with the
# existing round-scoped adapter.)
# ---------------------------------------------------------------------------
cat > 'packages/infrastructure/test/prediction/postgres_fixture_prediction_repository_test.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/prediction/postgres_fixture_prediction_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _predictionId = '11111111-1111-1111-1111-111111111111';
const _seasonId = '22222222-2222-2222-2222-222222222222';
const _participantId = '33333333-3333-3333-3333-333333333333';
const _fixtureA = '44444444-4444-4444-4444-444444444444';
const _fixtureB = '55555555-5555-5555-5555-555555555555';

/// Fake [PostgresConnection] replaying a scripted queue of [Result]s (one per
/// `query`) — same double used by `postgres_prediction_repository_test.dart`.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;
  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _row({
  String id = _predictionId,
  String fixtureId = _fixtureA,
  String participantId = _participantId,
  int homeGoals = 2,
  int awayGoals = 1,
  bool isDouble = false,
  DateTime? submittedAt,
}) => {
  'id': id,
  'fixture_id': fixtureId,
  'participant_id': participantId,
  'home_goals': homeGoals,
  'away_goals': awayGoals,
  'is_double': isDouble,
  'submitted_at': (submittedAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
};

void main() {
  group('PostgresFixturePredictionRepository', () {
    test('findByFixtureAndParticipant returns Ok(null) when absent', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      expect(result, isA<Ok<FixturePredictionView?>>());
      expect((result as Ok<FixturePredictionView?>).value, isNull);
    });

    test('findByFixtureAndParticipant maps a found row', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([Result.ok([_row()])]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      final view = (result as Ok<FixturePredictionView?>).value!;
      expect(view.prediction.homeGoals, 2);
      expect(view.prediction.awayGoals, 1);
      expect(view.prediction.fixture, const FixtureRef(_fixtureA));
    });

    test('save binds every field, including submitted_at as UTC ISO-8601', () async {
      final connection = _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]);
      final repo = PostgresFixturePredictionRepository(connection);
      final prediction = (FixturePrediction.submit(
                id: const PredictionId(_predictionId),
                fixture: const FixtureRef(_fixtureA),
                participantId: const ParticipantId(_participantId),
                lock: (FixtureLock.at(
                          kickoffAt: DateTime.utc(2026, 8, 2),
                          nowUtc: DateTime.utc(2026, 8, 1),
                        )
                        as Ok<FixtureLock>)
                    .value,
                homeGoals: 2,
                awayGoals: 1,
              )
              as Ok<FixturePrediction>)
          .value;

      final result = await repo.save(prediction, DateTime.utc(2026, 8, 1, 12));

      expect(result, isA<Ok<void>>());
      expect(connection.parameters.single['id'], _predictionId);
      expect(connection.parameters.single['fixture_id'], _fixtureA);
      expect(
        connection.parameters.single['submitted_at'],
        '2026-08-01T12:00:00.000Z',
      );
    });

    test('update surfaces prediction.not_found on an empty RETURNING', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final prediction = (FixturePrediction.submit(
                id: const PredictionId(_predictionId),
                fixture: const FixtureRef(_fixtureA),
                participantId: const ParticipantId(_participantId),
                lock: (FixtureLock.at(
                          kickoffAt: DateTime.utc(2026, 8, 2),
                          nowUtc: DateTime.utc(2026, 8, 1),
                        )
                        as Ok<FixtureLock>)
                    .value,
                homeGoals: 0,
                awayGoals: 0,
              )
              as Ok<FixturePrediction>)
          .value;

      final result = await repo.update(prediction, DateTime.utc(2026, 8, 1));

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).error.code, 'prediction.not_found');
    });

    test('findSeasonFixture returns Ok(null) when not linked', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.findSeasonFixture(
        const SeasonId(_seasonId),
        const FixtureRef(_fixtureA),
      );
      expect(result, isA<Ok<SeasonFixture?>>());
      expect((result as Ok<SeasonFixture?>).value, isNull);
    });

    test('findSeasonFixture maps a linked row', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            {'season_id': _seasonId, 'fixture_id': _fixtureA, 'display_order': 3},
          ]),
        ]),
      );
      final result = await repo.findSeasonFixture(
        const SeasonId(_seasonId),
        const FixtureRef(_fixtureA),
      );
      final link = (result as Ok<SeasonFixture?>).value!;
      expect(link.displayOrder, 3);
    });

    test('countDoublesOnDay maps the count column', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            {'n': 2},
          ]),
        ]),
      );
      final result = await repo.countDoublesOnDay(
        const ParticipantId(_participantId),
        DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 2);
    });

    test('countDoublesOnDay defaults to 0 on an empty result', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.countDoublesOnDay(
        const ParticipantId(_participantId),
        DateTime.utc(2026, 8, 1),
      );
      expect((result as Ok<int>).value, 0);
    });

    test('listByFixture groups by first-seen order, no grouping needed (flat rows)', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            _row(participantId: _participantId, fixtureId: _fixtureB),
            _row(id: '66666666-6666-6666-6666-666666666666',
                participantId: '77777777-7777-7777-7777-777777777777',
                fixtureId: _fixtureB),
          ]),
        ]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureB));
      expect(result, isA<Ok<List<FixturePredictionView>>>());
      expect((result as Ok<List<FixturePredictionView>>).value, hasLength(2));
    });

    test('a corrupt row (non-integer home_goals) surfaces as row_corrupt', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            {..._row(), 'home_goals': 'not-a-number'},
          ]),
        ]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      expect(result, isA<Err<FixturePredictionView?>>());
      expect(
        (result as Err<FixturePredictionView?>).error.code,
        'prediction.row_corrupt',
      );
    });

    test('a transient connection error passes through verbatim', () async {
      const error = AppError.transient('boom', 'db down');
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.err(error)]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      expect((result as Err<FixturePredictionView?>).error.code, 'boom');
    });
  });
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/infrastructure/test/scoring/postgres_fixture_score_repository_test.dart
# ---------------------------------------------------------------------------
cat > 'packages/infrastructure/test/scoring/postgres_fixture_score_repository_test.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/scoring/postgres_fixture_score_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixtureA = '44444444-4444-4444-4444-444444444444';
const _participantA = '33333333-3333-3333-3333-333333333333';
const _participantB = '77777777-7777-7777-7777-777777777777';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.parameters.add(parameters);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

ParticipantFixtureScore _score({
  String participantId = _participantA,
  FixtureScoreGrade grade = FixtureScoreGrade.exactScoreline,
  int points = 3,
}) =>
    (ParticipantFixtureScore.fromGraded(
              fixture: const FixtureRef(_fixtureA),
              participantId: ParticipantId(participantId),
              rulesetVersion: 1,
              result: FixtureScoreResult(
                fixture: const FixtureRef(_fixtureA),
                grade: grade,
                points: points,
              ),
            )
            as Ok<ParticipantFixtureScore>)
        .value;

void main() {
  group('PostgresFixtureScoreRepository', () {
    test('saveFixtureScores is a no-op for an empty list (no query sent)', () async {
      final connection = _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]);
      final repo = PostgresFixtureScoreRepository(connection);

      final result = await repo.saveFixtureScores(const []);

      expect(result, isA<Ok<void>>());
      expect(connection.parameters, isEmpty);
    });

    test('saveFixtureScores flattens every score into parallel arrays', () async {
      final connection = _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]);
      final repo = PostgresFixtureScoreRepository(connection);

      final result = await repo.saveFixtureScores([
        _score(participantId: _participantA, points: 3),
        _score(
          participantId: _participantB,
          grade: FixtureScoreGrade.incorrect,
          points: 0,
        ),
      ]);

      expect(result, isA<Ok<void>>());
      final bound = connection.parameters.single;
      expect(bound['fixture_ids'], [_fixtureA, _fixtureA]);
      expect(bound['participant_ids'], [_participantA, _participantB]);
      expect(bound['grades'], ['exact_scoreline', 'incorrect']);
      expect(bound['points'], [3, 0]);
    });

    test('listByFixture maps every row, ordered as returned', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([
          Result.ok([
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantA,
              'ruleset_version': 1,
              'grade': 'exact_scoreline',
              'points': 3,
            },
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantB,
              'ruleset_version': 1,
              'grade': 'pending',
              'points': 0,
            },
          ]),
        ]),
      );

      final result = await repo.listByFixture(const FixtureRef(_fixtureA));

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      final list = (result as Ok<List<ParticipantFixtureScore>>).value;
      expect(list, hasLength(2));
      expect(list.first.result.grade, FixtureScoreGrade.exactScoreline);
      expect(list.last.result.grade, FixtureScoreGrade.pending);
    });

    test('an empty result maps to an empty list', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect((result as Ok<List<ParticipantFixtureScore>>).value, isEmpty);
    });

    test('an unparseable grade surfaces as row_corrupt', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([
          Result.ok([
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantA,
              'ruleset_version': 1,
              'grade': 'not_a_real_grade',
              'points': 0,
            },
          ]),
        ]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect(result, isA<Err<List<ParticipantFixtureScore>>>());
      expect(
        (result as Err<List<ParticipantFixtureScore>>).error.code,
        'scoring.row_corrupt',
      );
    });

    test('a transient connection error passes through verbatim', () async {
      const error = AppError.transient('boom', 'db down');
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([const Result.err(error)]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect((result as Err<List<ParticipantFixtureScore>>).error.code, 'boom');
    });
  });
}
NUKHBA_EOF

# --- تحديث exports في infrastructure.dart (إضافة فقط، لا حذف) ---
F=packages/infrastructure/lib/infrastructure.dart
grep -q "src/prediction/postgres_fixture_prediction_repository.dart" "$F" || \
  sed -i "\#export 'src/prediction/postgres_prediction_repository.dart';#i export 'src/prediction/postgres_fixture_prediction_repository.dart';" "$F"
grep -q "src/scoring/postgres_fixture_score_repository.dart" "$F" || \
  sed -i "\#export 'src/scoring/postgres_score_repository.dart';#i export 'src/scoring/postgres_fixture_score_repository.dart';" "$F"

# --- إلحاق احتياطي: إذا لم تُضف الأسطر أعلاه (اختلاف مرساة نصية)، ألحقها في نهاية الملف ---
grep -q "src/prediction/postgres_fixture_prediction_repository.dart" "$F" || \
  echo "export 'src/prediction/postgres_fixture_prediction_repository.dart';" >> "$F"
grep -q "src/scoring/postgres_fixture_score_repository.dart" "$F" || \
  echo "export 'src/scoring/postgres_fixture_score_repository.dart';" >> "$F"

echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze packages/infrastructure"
echo "  flutter test packages/infrastructure --exclude-tags=integration"
echo "  (اختياري، بقاعدة بيانات فعلية) supabase db reset  # لتطبيق مايجريشن 0019"
echo ""
echo "تحقق فوري من نجاح الـ exports:"
echo "  grep -n fixture_prediction packages/infrastructure/lib/infrastructure.dart"
echo "  grep -n fixture_score packages/infrastructure/lib/infrastructure.dart"
