#!/usr/bin/env bash
# Phase 3 — Application expand (Axiom 4 Amendment: Round -> monthly competition).
# Additive only: new use-cases (SubmitFixturePrediction, ScoreFixture) + their
# ports, alongside the old round-scoped ones. Also patches
# packages/domain/lib/src/scoring/scoring.dart to add the pure
# `Scoring.scoreFixture` grading function ScoreFixture depends on (no
# deletions — same expand-only rule as phases 1-2).
set -euo pipefail
cd "${1:-.}"

mkdir -p packages/application/lib/src/prediction/ports
mkdir -p packages/application/lib/src/scoring/ports
mkdir -p packages/application/test/prediction
mkdir -p packages/application/test/scoring

# ---------------------------------------------------------------------------
# packages/application/lib/src/prediction/fixture_prediction_view.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/lib/src/prediction/fixture_prediction_view.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';

/// A read model that pairs a [FixturePrediction] with the submission instant
/// its repository stamped on it — the per-fixture sibling of [PredictionView]
/// (docs/project-context.md, Axiom 4 Amendment), for the same reason:
/// `FixturePrediction` carries no `submittedAt` (a persistence fact, not a
/// domain invariant), but the wire DTO needs one.
///
/// Pure and immutable; value-comparable by `(prediction, submittedAt)`.
final class FixturePredictionView {
  /// Pairs [prediction] with the UTC [submittedAt] instant it was stored under.
  const FixturePredictionView({
    required this.prediction,
    required this.submittedAt,
  });

  /// The fixture-prediction aggregate.
  final FixturePrediction prediction;

  /// The submission instant (UTC) the repository stamped on this prediction.
  /// For an amended prediction this is the amendment instant.
  final DateTime submittedAt;

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionView &&
      other.prediction == prediction &&
      other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(prediction, submittedAt);
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart' <<'NUKHBA_EOF'
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for the per-fixture Prediction context
/// (docs/project-context.md, Axiom 4 Amendment — replaces the round-scoped
/// [PredictionRepository] for the new [FixturePrediction] aggregate; kept as
/// its own port rather than merged into it, exactly as [PredictionRepository]
/// was kept separate from `CompetitionRepository` — Database ADR, Section 1).
///
/// General contract for every method (Application ADR, Section 2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict (the unique
///   `(participant_id, fixture_id)` violation) to [ErrorKind.invariant]
///   `prediction.already_submitted`.
abstract interface class FixturePredictionRepository {
  /// Finds the single prediction for `(fixture, participantId)`, or
  /// `Ok(null)` when the participant has not yet predicted this fixture.
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  );

  /// Persists a brand-new [prediction] stamped [submittedAt] (UTC).
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  );

  /// Persists an amended [prediction] in place, refreshing [submittedAt]
  /// (UTC). Identity (`id`, `fixture`, `participantId`) is unchanged — an
  /// amendment is the same row, never a second prediction.
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  );

  /// Returns the `SeasonFixture` link for `(seasonId, fixture)`, or
  /// `Ok(null)` when the fixture is not linked to that season — the
  /// per-fixture replacement for the old round-fixture membership check,
  /// kept here (not on `CompetitionRepository`) for the same reason the
  /// round-fixture read was: it keeps that port frozen.
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  );

  /// Counts how many fixtures [participantId] has already marked as their
  /// double whose kickoff falls on the UTC calendar day [dayUtc] (midnight
  /// UTC of that day), optionally excluding [excludingFixture] (an amendment
  /// of an already-double fixture must not count itself) — the query
  /// [DailyDoublePolicy] is checked against.
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  });

  /// Lists every participant's [FixturePredictionView] for [fixture],
  /// unordered — the per-fixture replacement for the round-wide
  /// `listByRound`, used by `ScoreFixture` to grade every participant who
  /// predicted this fixture.
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  );
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/lib/src/prediction/submit_fixture_prediction.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/lib/src/prediction/submit_fixture_prediction.dart' <<'NUKHBA_EOF'
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: submit (or amend) a participant's prediction for a single
/// fixture (docs/project-context.md, Axiom 4 Amendment — replaces the
/// round-scoped `SubmitPrediction`'s atomic batch with one independent
/// submission per fixture, so a participant can predict one fixture "or
/// more" without waiting on the rest of any round).
///
/// The client names the [seasonId] it is predicting under (there is no round
/// to derive it from anymore) plus the [fixtureId]; the participant is
/// resolved server-side from the verified principal + that season, exactly
/// as `SubmitPrediction` did (Axiom 2: never trust a client-supplied
/// participant id). Points are never accepted or computed here (Axioms 2/5).
///
/// Business invariants enforced (in order):
/// 1. **The fixture belongs to the season** — via `SeasonFixture`
///    (`prediction.fixture_not_in_season`; the per-fixture replacement for
///    the old `fixture_not_in_round` check now that `RoundFixture` is gone).
/// 2. **The caller is a participant of that season**
///    (`prediction.not_a_participant`).
/// 3. **The fixture has not kicked off** — [FixtureLock], computed from the
///    fixture's own [FixtureSchedule.kickoffAt] against the clock
///    (`prediction.fixture_locked`). A fixture with no registered schedule is
///    treated as not locked, matching `SubmitPrediction`.
/// 4. **At most one double per participant per UTC calendar day** — checked
///    against [FixturePredictionRepository.countDoublesOnDay] for the
///    fixture's kickoff day, excluding this fixture itself so re-marking an
///    already-double fixture on amend never double-counts
///    (`prediction.daily_double_exceeded`). Only checked when [isDouble] is
///    true.
///
/// **Idempotent**: a first call for `(fixture, participant)` inserts; a
/// repeat call amends the existing prediction in place — one row per
/// `(fixture, participant)`, never a second.
///
/// Never throws; returns a typed [Result].
final class SubmitFixturePrediction {
  /// Creates the use-case over its collaborators.
  const SubmitFixturePrediction({
    required FixturePredictionRepository fixturePredictionRepository,
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _fixturePredictions = fixturePredictionRepository,
       _competition = competitionRepository,
       _fixtureSchedules = fixtureScheduleRepository,
       _idGenerator = idGenerator,
       _clock = clock;

  final FixturePredictionRepository _fixturePredictions;
  final CompetitionRepository _competition;
  final FixtureScheduleRepository _fixtureSchedules;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Submits (or amends) [homeGoals]-[awayGoals] as [principal]'s prediction
  /// for fixture [fixtureId] under season [seasonId].
  Future<Result<FixturePredictionView>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    // Rule 1: the fixture must belong to the season.
    final linkResult = await _fixturePredictions.findSeasonFixture(
      sId,
      fixture,
    );
    if (linkResult is Err<SeasonFixture?>) {
      return Result.err(linkResult.error);
    }
    if ((linkResult as Ok<SeasonFixture?>).value == null) {
      return Result.err(
        AppError.validation(
          'prediction.fixture_not_in_season',
          'Fixture ${fixture.value} is not part of this season',
        ),
      );
    }

    // Rule 2: resolve the caller's participant in this season.
    final participantResult = await _competition.findParticipant(
      sId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant == null) {
      return const Result.err(
        AppError.invariant(
          'prediction.not_a_participant',
          'You must join the season before submitting a prediction',
        ),
      );
    }

    // Rule 3: the fixture must not have kicked off yet. No registered
    // schedule is treated as not locked (mirrors SubmitPrediction). A
    // synthetic "well after now" kickoff stands in for FixtureLock's pure
    // comparison when there is no real schedule to compare against.
    final schedulesResult = await _fixtureSchedules.findByFixtures([fixture]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    final now = _clock.nowUtc();
    final kickoffAt = schedules.isEmpty ? null : schedules.first.kickoffAt;
    final effectiveKickoff = kickoffAt ?? now.add(const Duration(days: 1));

    final lockResult = FixtureLock.at(
      kickoffAt: effectiveKickoff,
      nowUtc: now,
    );
    if (lockResult is Err<FixtureLock>) {
      return Result.err(lockResult.error);
    }
    final lock = (lockResult as Ok<FixtureLock>).value;
    if (lock.isLocked) {
      return Result.err(
        AppError.invariant(
          'prediction.fixture_locked',
          'Fixture ${fixture.value} has already kicked off and can no '
              'longer be predicted',
        ),
      );
    }

    // Rule 4: at most one double per UTC calendar day, only when marking one.
    if (isDouble) {
      final dayReference = kickoffAt ?? now;
      final dayUtc = DateTime.utc(
        dayReference.year,
        dayReference.month,
        dayReference.day,
      );
      final countResult = await _fixturePredictions.countDoublesOnDay(
        participant.id,
        dayUtc,
        excludingFixture: fixture,
      );
      if (countResult is Err<int>) {
        return Result.err(countResult.error);
      }
      final existingDoubles = (countResult as Ok<int>).value;
      if (!DailyDoublePolicy.allowsAnotherDouble(existingDoubles)) {
        return Result.err(
          AppError.invariant(
            'prediction.daily_double_exceeded',
            'Only one fixture may be marked as your double per day',
          ),
        );
      }
    }

    // Idempotency read: first submission inserts, a repeat amends.
    final existingResult = await _fixturePredictions
        .findByFixtureAndParticipant(fixture, participant.id);
    if (existingResult is Err<FixturePredictionView?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<FixturePredictionView?>).value;

    if (existing != null) {
      return _amend(existing.prediction, lock, homeGoals, awayGoals, isDouble, now);
    }
    return _insert(
      fixture,
      participant.id,
      lock,
      homeGoals,
      awayGoals,
      isDouble,
      now,
    );
  }

  Future<Result<FixturePredictionView>> _insert(
    FixtureRef fixture,
    ParticipantId participantId,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
  ) async {
    final idResult = PredictionId.tryParse(_idGenerator.newUuid());
    if (idResult is Err<PredictionId>) {
      return Result.err(idResult.error);
    }

    final predictionResult = FixturePrediction.submit(
      id: (idResult as Ok<PredictionId>).value,
      fixture: fixture,
      participantId: participantId,
      lock: lock,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (predictionResult is Err<FixturePrediction>) {
      return Result.err(predictionResult.error);
    }
    final prediction = (predictionResult as Ok<FixturePrediction>).value;

    final saved = await _fixturePredictions.save(prediction, now);
    return switch (saved) {
      Ok<void>() => Result.ok(
        FixturePredictionView(prediction: prediction, submittedAt: now),
      ),
      Err<void>(:final error) =>
        error.code == 'prediction.already_submitted'
            ? await _resolveConflictThenAmend(
                fixture,
                participantId,
                lock,
                homeGoals,
                awayGoals,
                isDouble,
                now,
                error,
              )
            : Result.err(error),
    };
  }

  Future<Result<FixturePredictionView>> _amend(
    FixturePrediction existing,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
  ) async {
    final amendedResult = existing.amend(
      lock: lock,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (amendedResult is Err<FixturePrediction>) {
      return Result.err(amendedResult.error);
    }
    final amended = (amendedResult as Ok<FixturePrediction>).value;

    final updated = await _fixturePredictions.update(amended, now);
    return switch (updated) {
      Ok<void>() => Result.ok(
        FixturePredictionView(prediction: amended, submittedAt: now),
      ),
      Err<void>(:final error) => Result.err(error),
    };
  }

  Future<Result<FixturePredictionView>> _resolveConflictThenAmend(
    FixtureRef fixture,
    ParticipantId participantId,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
    AppError insertError,
  ) async {
    final reread = await _fixturePredictions.findByFixtureAndParticipant(
      fixture,
      participantId,
    );
    return switch (reread) {
      Ok<FixturePredictionView?>(:final value) =>
        value != null
            ? await _amend(value.prediction, lock, homeGoals, awayGoals, isDouble, now)
            : Result.err(insertError),
      Err<FixturePredictionView?>(:final error) => Result.err(error),
    };
  }
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/lib/src/scoring/ports/fixture_score_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/lib/src/scoring/ports/fixture_score_repository.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for computed **per-fixture scores**
/// (docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `ScoreRepository`, for the new [ParticipantFixtureScore] aggregate; kept
/// as its own port for the same reason `ScoreRepository` is separate from
/// the competition/prediction ports).
///
/// A score is a **server-owned read value** (Axioms 2/5): only `ScoreFixture`
/// (fed by the pure `Scoring.scoreFixture`) ever produces the
/// [ParticipantFixtureScore]s written here.
///
/// General contract for every method (Application ADR, Section 2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict to [ErrorKind.invariant].
abstract interface class FixtureScoreRepository {
  /// Persists every [scores] entry for a fixture **atomically**
  /// (all-or-nothing), replacing any previously stored score for the same
  /// `(fixture, participant)` in place so re-scoring is idempotent.
  ///
  /// Every [ParticipantFixtureScore] in [scores] MUST share the same
  /// fixture; the adapter does not mix fixtures in a single call.
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  );

  /// Lists every participant's [ParticipantFixtureScore] for [fixture],
  /// ordered by participant id for a stable read. An empty list means the
  /// fixture has not been scored yet.
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  );
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/lib/src/scoring/score_fixture.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/lib/src/scoring/score_fixture.dart' <<'NUKHBA_EOF'
import 'package:application/src/competition/ports/ruleset_provider.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: score every prediction recorded for a single fixture
/// (docs/project-context.md, Axiom 4 Amendment — "ScoreFixture replaces
/// ScoreRound"; replaces the round-wide batch of `ScoreRound` with a
/// per-fixture pass that can run the instant that fixture's result lands, on
/// one fixture or more — never waiting on the rest of any round).
///
/// It:
/// 1. authorizes the caller as an **admin** (only the platform scores —
///    Axioms 2/5);
/// 2. reads the platform's **current** ruleset for the football-scoreline
///    format via [RulesetProvider]. **Known reproducibility gap**: unlike
///    `ScoreRound` (which replays a *frozen* per-round snapshot forever),
///    there is no round left to freeze a snapshot onto at open time, so a
///    fixture re-scored after the ruleset changes re-grades under the *new*
///    rules — Axiom 5's "the competitive record never changes retroactively"
///    is not yet re-established for the per-fixture path. Freezing a ruleset
///    snapshot per fixture or season is deferred to a later phase and must
///    be resolved before this fully replaces `ScoreRound` in production;
/// 3. reads the fixture's actual [FixtureResult], if recorded yet
///    ([FixtureResultRepository], reused unchanged from `ScoreRound`);
/// 4. reads every [FixturePrediction] recorded for the fixture
///    ([FixturePredictionRepository.listByFixture]);
/// 5. runs the pure domain [Scoring.scoreFixture] per prediction — a missing
///    result grades every prediction [FixtureScoreGrade.pending] (always
///    zero), exactly like `ScoreRound`'s live/partial scoring;
/// 6. persists all [ParticipantFixtureScore]s atomically
///    ([FixtureScoreRepository.saveFixtureScores]).
///
/// **Idempotent**: re-running scoring for the same fixture — before or after
/// its result lands — recomputes the same deterministic result and
/// re-persists it without creating duplicates (one score per
/// `(fixture, participant)`).
///
/// Never throws; returns a typed [Result] carrying the scored
/// [ParticipantFixtureScore]s.
final class ScoreFixture {
  /// Creates the use-case over its collaborators.
  const ScoreFixture({
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureResultRepository resultRepository,
    required FixtureScoreRepository scoreRepository,
    required RulesetProvider rulesetProvider,
  }) : _fixturePredictions = fixturePredictionRepository,
       _results = resultRepository,
       _scores = scoreRepository,
       _rulesetProvider = rulesetProvider;

  final FixturePredictionRepository _fixturePredictions;
  final FixtureResultRepository _results;
  final FixtureScoreRepository _scores;
  final RulesetProvider _rulesetProvider;

  /// Scores fixture [fixtureId] on behalf of admin [principal].
  Future<Result<List<ParticipantFixtureScore>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final snapshotResult = await _rulesetProvider.currentSnapshotFor(
      FormatType.footballScoreline,
    );
    if (snapshotResult is Err<RulesetSnapshot>) {
      return Result.err(snapshotResult.error);
    }
    final snapshot = (snapshotResult as Ok<RulesetSnapshot>).value;
    final rulesetResult = ScoringRuleset.fromSnapshot(snapshot);
    if (rulesetResult is Err<ScoringRuleset>) {
      return Result.err(rulesetResult.error);
    }
    final ruleset = (rulesetResult as Ok<ScoringRuleset>).value;

    final resultResult = await _results.findByFixture(fixture);
    if (resultResult is Err<FixtureResult?>) {
      return Result.err(resultResult.error);
    }
    final result = (resultResult as Ok<FixtureResult?>).value;

    final predictionsResult = await _fixturePredictions.listByFixture(
      fixture,
    );
    if (predictionsResult is Err<List<FixturePredictionView>>) {
      return Result.err(predictionsResult.error);
    }
    final predictions =
        (predictionsResult as Ok<List<FixturePredictionView>>).value;
    if (predictions.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'scoring.fixture_has_no_predictions',
          'No predictions have been submitted for this fixture yet',
        ),
      );
    }

    final fixtureScores = <ParticipantFixtureScore>[];
    for (final view in predictions) {
      final scored = Scoring.scoreFixture(
        prediction: view.prediction,
        result: result,
        ruleset: ruleset,
        rulesetVersion: ruleset.rulesetVersion,
      );
      if (scored is Err<ParticipantFixtureScore>) {
        return Result.err(scored.error);
      }
      fixtureScores.add((scored as Ok<ParticipantFixtureScore>).value);
    }

    final saved = await _scores.saveFixtureScores(fixtureScores);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    return Result.ok(
      List<ParticipantFixtureScore>.unmodifiable(fixtureScores),
    );
  }
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/test/prediction/fake_fixture_prediction_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/test/prediction/fake_fixture_prediction_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A complete in-memory [FixturePredictionRepository] for use-case tests.
///
/// Reproduces the observable contract the Postgres adapter must honour — the
/// `(participant_id, fixture_id)` uniqueness, find/update/list semantics, the
/// season-fixture membership read, and the daily-double count — so a
/// use-case test that passes here exercises the same invariants the real
/// adapter enforces. It never throws.
final class FakeFixturePredictionRepository
    implements FixturePredictionRepository {
  /// keyed by `${fixtureId}|${participantId}`.
  final Map<String, _Stored> _byKey = {};

  /// keyed by `${seasonId}|${fixtureId}`.
  final Map<String, SeasonFixture> _seasonFixtures = {};

  /// keyed by fixtureId -> kickoff instant, so [countDoublesOnDay] can group
  /// stored doubles by the UTC calendar day of their fixture's kickoff.
  final Map<String, DateTime> _kickoffByFixture = {};

  AppError? _scriptedFailure;

  /// Scripts the *next* call to fail with [error], then clears the script.
  void failNextWith(AppError error) => _scriptedFailure = error;

  AppError? _takeFailure() {
    final f = _scriptedFailure;
    _scriptedFailure = null;
    return f;
  }

  static String _key(FixtureRef fixture, ParticipantId participantId) =>
      '${fixture.value}|${participantId.value}';

  // Seeding helpers.
  void seedSeasonFixture(SeasonFixture link) =>
      _seasonFixtures['${link.seasonId.value}|${link.fixture.value}'] = link;

  void seedKickoff(FixtureRef fixture, DateTime kickoffAt) =>
      _kickoffByFixture[fixture.value] = kickoffAt;

  void seedPrediction(FixturePrediction prediction, DateTime submittedAt) =>
      _byKey[_key(prediction.fixture, prediction.participantId)] = _Stored(
        prediction,
        submittedAt,
      );

  int get count => _byKey.length;

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final stored = _byKey[_key(fixture, participantId)];
    return Result.ok(
      stored == null
          ? null
          : FixturePredictionView(
              prediction: stored.prediction,
              submittedAt: stored.submittedAt,
            ),
    );
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = _key(prediction.fixture, prediction.participantId);
    if (_byKey.containsKey(key)) {
      return const Result.err(
        AppError.invariant(
          'prediction.already_submitted',
          'already submitted',
        ),
      );
    }
    _byKey[key] = _Stored(prediction, submittedAt);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = _key(prediction.fixture, prediction.participantId);
    if (!_byKey.containsKey(key)) {
      return const Result.err(
        AppError.invariant('prediction.not_found', 'not found'),
      );
    }
    _byKey[key] = _Stored(prediction, submittedAt);
    return const Result.ok(null);
  }

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    return Result.ok(_seasonFixtures['${seasonId.value}|${fixture.value}']);
  }

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    var count = 0;
    for (final stored in _byKey.values) {
      final prediction = stored.prediction;
      if (!prediction.isDouble) continue;
      if (prediction.participantId != participantId) continue;
      if (excludingFixture != null && prediction.fixture == excludingFixture) {
        continue;
      }
      final kickoff = _kickoffByFixture[prediction.fixture.value];
      if (kickoff == null) continue;
      final sameDay =
          kickoff.year == dayUtc.year &&
          kickoff.month == dayUtc.month &&
          kickoff.day == dayUtc.day;
      if (sameDay) count++;
    }
    return Result.ok(count);
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    return Result.ok([
      for (final s in _byKey.values)
        if (s.prediction.fixture == fixture)
          FixturePredictionView(
            prediction: s.prediction,
            submittedAt: s.submittedAt,
          ),
    ]);
  }
}

final class _Stored {
  const _Stored(this.prediction, this.submittedAt);
  final FixturePrediction prediction;
  final DateTime submittedAt;
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/test/scoring/fake_fixture_score_repository.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/test/scoring/fake_fixture_score_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A complete in-memory [FixtureScoreRepository] for use-case tests.
///
/// Reproduces the observable contract: idempotent upsert per
/// `(fixture, participant)` (re-scoring replaces in place, never
/// duplicates), and a stable by-fixture read ordered by participant id. It
/// never throws.
final class FakeFixtureScoreRepository implements FixtureScoreRepository {
  /// keyed by `${fixtureId}|${participantId}`.
  final Map<String, ParticipantFixtureScore> _byKey = {};

  AppError? _scriptedFailure;

  /// Scripts the *next* call to fail with [error], then clears the script.
  void failNextWith(AppError error) => _scriptedFailure = error;

  AppError? _takeFailure() {
    final f = _scriptedFailure;
    _scriptedFailure = null;
    return f;
  }

  static String _key(FixtureRef fixture, ParticipantId participantId) =>
      '${fixture.value}|${participantId.value}';

  /// How many fixture-score rows are stored (proves idempotent re-scoring
  /// keeps one row per participant).
  int get count => _byKey.length;

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final staged = <String, ParticipantFixtureScore>{};
    for (final s in scores) {
      staged[_key(s.fixture, s.participantId)] = s;
    }
    _byKey.addAll(staged);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final out = <ParticipantFixtureScore>[
      for (final s in _byKey.values)
        if (s.fixture == fixture) s,
    ]..sort((a, b) => a.participantId.value.compareTo(b.participantId.value));
    return Result.ok(out);
  }
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/test/prediction/submit_fixture_prediction_test.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/test/prediction/submit_fixture_prediction_test.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import 'fake_fixture_prediction_repository.dart';
import 'fake_fixture_schedule_repository.dart';

void main() {
  group('SubmitFixturePrediction', () {
    late FakeFixturePredictionRepository fixturePredictions;
    late FakeCompetitionRepository competition;
    late FakeFixtureScheduleRepository schedules;
    late SubmitFixturePrediction useCase;

    const seasonId = 'season-1';
    const fixtureId = '11111111-1111-1111-1111-111111111111';
    const userId = 'user-1';
    const participantId = 'participant-1';

    setUp(() {
      fixturePredictions = FakeFixturePredictionRepository();
      competition = FakeCompetitionRepository();
      schedules = FakeFixtureScheduleRepository();
      useCase = SubmitFixturePrediction(
        fixturePredictionRepository: fixturePredictions,
        competitionRepository: competition,
        fixtureScheduleRepository: schedules,
        idGenerator: FakeIdGenerator(['prediction-1']),
        clock: FixedClock(DateTime.utc(2026, 8, 1, 10)),
      );

      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: SeasonId(seasonId),
                  fixture: FixtureRef(fixtureId),
                  displayOrder: 0,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      competition.seedParticipant(
        Participant.fromStored(
          id: ParticipantId(participantId),
          seasonId: SeasonId(seasonId),
          userId: UserId(userId),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026),
        ),
      );
    });

    test('inserts a new prediction on first submission', () async {
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );

      expect(result, isA<Ok<FixturePredictionView>>());
      final view = (result as Ok<FixturePredictionView>).value;
      expect(view.prediction.homeGoals, 2);
      expect(view.prediction.awayGoals, 1);
      expect(view.prediction.isDouble, isTrue);
      expect(fixturePredictions.count, 1);
    });

    test('amends the same row on a repeat submission', () async {
      await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 1,
      );
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 0,
        awayGoals: 0,
      );

      expect(result, isA<Ok<FixturePredictionView>>());
      final view = (result as Ok<FixturePredictionView>).value;
      expect(view.prediction.homeGoals, 0);
      expect(view.prediction.awayGoals, 0);
      expect(fixturePredictions.count, 1);
    });

    test('rejects a fixture not linked to the season', () async {
      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: '22222222-2222-2222-2222-222222222222',
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.fixture_not_in_season',
      );
    });

    test('rejects a caller who has not joined the season', () async {
      final result = await useCase(
        principal: userPrincipal('someone-else'),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.not_a_participant',
      );
    });

    test('rejects a fixture that has already kicked off', () async {
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: FixtureRef(fixtureId),
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
          kickoffAt: DateTime.utc(2026, 8, 1, 9), // before the fixed clock
        ),
      );

      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.fixture_locked',
      );
    });

    test('rejects a second double on the same UTC day', () async {
      const otherFixtureId = '33333333-3333-3333-3333-333333333333';
      fixturePredictions.seedSeasonFixture(
        (SeasonFixture.create(
                  seasonId: SeasonId(seasonId),
                  fixture: FixtureRef(otherFixtureId),
                  displayOrder: 1,
                )
                as Ok<SeasonFixture>)
            .value,
      );
      fixturePredictions.seedKickoff(
        FixtureRef(otherFixtureId),
        DateTime.utc(2026, 8, 1, 12),
      );
      fixturePredictions.seedKickoff(
        FixtureRef(fixtureId),
        DateTime.utc(2026, 8, 1, 20),
      );
      await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: otherFixtureId,
        homeGoals: 1,
        awayGoals: 1,
        isDouble: true,
      );

      final result = await useCase(
        principal: userPrincipal(userId),
        seasonId: seasonId,
        fixtureId: fixtureId,
        homeGoals: 2,
        awayGoals: 0,
        isDouble: true,
      );

      expect(result, isA<Err<FixturePredictionView>>());
      expect(
        (result as Err<FixturePredictionView>).error.code,
        'prediction.daily_double_exceeded',
      );
    });
  });
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/application/test/scoring/score_fixture_test.dart
# ---------------------------------------------------------------------------
cat > 'packages/application/test/scoring/score_fixture_test.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import 'fake_fixture_score_repository.dart';
import 'fakes.dart';

void main() {
  group('ScoreFixture', () {
    late FakeFixturePredictionRepository fixturePredictions;
    late FakeFixtureResultRepository results;
    late FakeFixtureScoreRepository scores;
    late ScoreFixture useCase;

    const fixtureId = '11111111-1111-1111-1111-111111111111';
    const participantId = 'participant-1';

    setUp(() {
      fixturePredictions = FakeFixturePredictionRepository();
      results = FakeFixtureResultRepository();
      scores = FakeFixtureScoreRepository();
      useCase = ScoreFixture(
        fixturePredictionRepository: fixturePredictions,
        resultRepository: results,
        scoreRepository: scores,
        rulesetProvider: FakeRulesetProvider(Result.ok(scoringSnapshot())),
      );
    });

    FixturePrediction seedPrediction({
      required int home,
      required int away,
      bool isDouble = false,
    }) {
      final prediction =
          (FixturePrediction.submit(
                    id: const PredictionId('prediction-1'),
                    fixture: const FixtureRef(fixtureId),
                    participantId: const ParticipantId(participantId),
                    lock: (FixtureLock.at(
                              kickoffAt: DateTime.utc(2026, 8, 2),
                              nowUtc: DateTime.utc(2026, 8, 1),
                            )
                            as Ok<FixtureLock>)
                        .value,
                    homeGoals: home,
                    awayGoals: away,
                    isDouble: isDouble,
                  )
                  as Ok<FixturePrediction>)
              .value;
      fixturePredictions.seedPrediction(prediction, DateTime.utc(2026, 8, 1));
      return prediction;
    }

    test('grades an exact-scoreline prediction once the result lands', () async {
      seedPrediction(home: 2, away: 1);
      results.seed(
        FixtureResult.fromStored(
          fixture: const FixtureRef(fixtureId),
          homeGoals: 2,
          awayGoals: 1,
        ),
      );

      final result = await useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      final list = (result as Ok<List<ParticipantFixtureScore>>).value;
      expect(list, hasLength(1));
      expect(list.single.result.grade, FixtureScoreGrade.exactScoreline);
      expect(scores.count, 1);
    });

    test('grades pending when no result has been recorded yet', () async {
      seedPrediction(home: 2, away: 1);

      final result = await useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      final list = (result as Ok<List<ParticipantFixtureScore>>).value;
      expect(list.single.result.grade, FixtureScoreGrade.pending);
      expect(list.single.points, 0);
    });

    test('rejects scoring a fixture with no predictions', () async {
      final result = await useCase(
        principal: adminPrincipal('admin-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Err<List<ParticipantFixtureScore>>>());
      expect(
        (result as Err<List<ParticipantFixtureScore>>).error.code,
        'scoring.fixture_has_no_predictions',
      );
    });

    test('rejects a non-admin caller', () async {
      seedPrediction(home: 1, away: 0);

      final result = await useCase(
        principal: userPrincipal('user-1'),
        fixtureId: fixtureId,
      );

      expect(result, isA<Err<List<ParticipantFixtureScore>>>());
    });
  });
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# packages/domain/test/scoring/scoring_fixture_test.dart
# ---------------------------------------------------------------------------
mkdir -p packages/domain/test/scoring
cat > 'packages/domain/test/scoring/scoring_fixture_test.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Scoring.scoreFixture', () {
    final ruleset =
        (ScoringRuleset.fromSnapshot(
                  (RulesetSnapshot.create(
                            payload: const {
                              'format': 'football_scoreline',
                              'points': {
                                'exact_scoreline': 3,
                                'correct_outcome': 1,
                                'incorrect': 0,
                              },
                            },
                            rulesetVersion: 1,
                          )
                          as Ok<RulesetSnapshot>)
                      .value,
                )
                as Ok<ScoringRuleset>)
            .value;

    FixturePrediction prediction({
      required int home,
      required int away,
      bool isDouble = false,
    }) =>
        (FixturePrediction.submit(
                  id: const PredictionId('prediction-1'),
                  fixture: const FixtureRef(
                    '11111111-1111-1111-1111-111111111111',
                  ),
                  participantId: const ParticipantId('participant-1'),
                  lock: (FixtureLock.at(
                            kickoffAt: DateTime.utc(2026, 8, 2),
                            nowUtc: DateTime.utc(2026, 8, 1),
                          )
                          as Ok<FixtureLock>)
                      .value,
                  homeGoals: home,
                  awayGoals: away,
                  isDouble: isDouble,
                )
                as Ok<FixturePrediction>)
            .value;

    test('grades pending with zero points when no result yet', () {
      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 1),
        result: null,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.pending);
      expect(score.points, 0);
    });

    test('grades exact scoreline, doubled', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('11111111-1111-1111-1111-111111111111'),
        homeGoals: 2,
        awayGoals: 1,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 1, isDouble: true),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.exactScoreline);
      expect(score.points, 6); // 3 * doubleMultiplier(2)
    });

    test('grades correct outcome without exact scoreline', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('11111111-1111-1111-1111-111111111111'),
        homeGoals: 3,
        awayGoals: 1,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 2, away: 0),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Ok<ParticipantFixtureScore>>());
      final score = (scored as Ok<ParticipantFixtureScore>).value;
      expect(score.result.grade, FixtureScoreGrade.correctOutcome);
      expect(score.points, 1);
    });

    test('rejects a result for a different fixture', () {
      final result = FixtureResult.fromStored(
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        homeGoals: 1,
        awayGoals: 0,
      );

      final scored = Scoring.scoreFixture(
        prediction: prediction(home: 1, away: 0),
        result: result,
        ruleset: ruleset,
        rulesetVersion: 1,
      );

      expect(scored, isA<Err<ParticipantFixtureScore>>());
      expect(
        (scored as Err<ParticipantFixtureScore>).error.code,
        'scoring.fixture_mismatch',
      );
    });
  });
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# Patch packages/domain/lib/src/scoring/scoring.dart (additive: new imports +
# new Scoring.scoreFixture / _gradeFixturePrediction static methods).
# ---------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib

p = pathlib.Path('packages/domain/lib/src/scoring/scoring.dart')
s = p.read_text()

old_imports = (
    "import 'package:domain/src/prediction/fixture_score_prediction.dart';\n"
    "import 'package:domain/src/prediction/prediction.dart';"
)
new_imports = (
    "import 'package:domain/src/prediction/fixture_prediction.dart';\n"
    "import 'package:domain/src/prediction/fixture_score_prediction.dart';\n"
    "import 'package:domain/src/prediction/prediction.dart';"
)
assert old_imports in s, 'anchor #1 (prediction imports) not found'
s = s.replace(old_imports, new_imports, 1)

old_import2 = "import 'package:domain/src/scoring/round_score.dart';"
new_import2 = (
    "import 'package:domain/src/scoring/participant_fixture_score.dart';\n"
    "import 'package:domain/src/scoring/round_score.dart';"
)
assert old_import2 in s, 'anchor #2 (round_score import) not found'
s = s.replace(old_import2, new_import2, 1)

anchor = "  static FixtureScoreResult _gradeFixture("
assert s.count(anchor) == 1, 'anchor #3 (_gradeFixture) not found or not unique'

new_methods = '''  /// Scores a single [FixturePrediction] against its fixture's actual
  /// [result] (if recorded yet) under [ruleset] -- the per-fixture sibling of
  /// [scoreRound] (docs/project-context.md, Axiom 4 Amendment: "ScoreFixture
  /// replaces ScoreRound").
  ///
  /// [result] is `null` when the fixture's actual result has not been
  /// recorded yet -- graded [FixtureScoreGrade.pending] (always zero points),
  /// exactly like [scoreRound]'s live/partial-scoring behaviour. There is no
  /// `missed` grade here: `missed` only ever applied to a round fixture the
  /// participant never predicted, and a [FixturePrediction] by construction
  /// always names the fixture it is for.
  static Result<ParticipantFixtureScore> scoreFixture({
    required FixturePrediction prediction,
    required FixtureResult? result,
    required ScoringRuleset ruleset,
    required int rulesetVersion,
  }) {
    if (result != null && result.fixture != prediction.fixture) {
      return const Result.err(
        AppError.invariant(
          'scoring.fixture_mismatch',
          'The result must be for the same fixture being scored',
        ),
      );
    }

    final graded = result == null
        ? FixtureScoreResult(
            fixture: prediction.fixture,
            grade: FixtureScoreGrade.pending,
            points: 0,
          )
        : _gradeFixturePrediction(prediction, result, ruleset);

    return ParticipantFixtureScore.fromGraded(
      fixture: prediction.fixture,
      participantId: prediction.participantId,
      rulesetVersion: rulesetVersion,
      result: graded,
    );
  }

  static FixtureScoreResult _gradeFixturePrediction(
    FixturePrediction prediction,
    FixtureResult result,
    ScoringRuleset ruleset,
  ) {
    final FixtureRef fixture = prediction.fixture;
    final multiplier = prediction.isDouble ? ruleset.doubleMultiplier : 1;

    if (prediction.homeGoals == result.homeGoals &&
        prediction.awayGoals == result.awayGoals) {
      return FixtureScoreResult(
        fixture: fixture,
        grade: FixtureScoreGrade.exactScoreline,
        points: ruleset.exactScorelinePoints * multiplier,
      );
    }

    final predictedOutcome = MatchOutcome.fromGoals(
      prediction.homeGoals,
      prediction.awayGoals,
    );
    if (predictedOutcome == result.outcome) {
      return FixtureScoreResult(
        fixture: fixture,
        grade: FixtureScoreGrade.correctOutcome,
        points: ruleset.correctOutcomePoints * multiplier,
      );
    }

    return FixtureScoreResult(
      fixture: fixture,
      grade: FixtureScoreGrade.incorrect,
      points: ruleset.incorrectPoints * multiplier,
    );
  }

'''
s = s.replace(anchor, new_methods + anchor, 1)
p.write_text(s)
print('scoring.dart patched OK')
PYEOF

# ---------------------------------------------------------------------------
# Fix pre-existing gap: season_fixture.dart exists in the tree (from before
# phase 1) but was never exported from domain.dart, so `SeasonFixture` is
# unreachable via `package:domain/domain.dart` — needed by this phase's
# FixturePredictionRepository port. Additive, one line.
# ---------------------------------------------------------------------------
D=packages/domain/lib/domain.dart
if ! grep -q "src/competition/season_fixture.dart" "$D"; then
  sed -i "\#export 'src/competition/season_id.dart';#i export 'src/competition/season_fixture.dart';" "$D"
fi

# ---------------------------------------------------------------------------
# Update exports in packages/application/lib/application.dart (additive only)
# ---------------------------------------------------------------------------
F=packages/application/lib/application.dart
sed -i "\#export 'src/prediction/get_my_prediction.dart';#i export 'src/prediction/fixture_prediction_view.dart';" "$F"
sed -i "\#export 'src/prediction/ports/prediction_repository.dart';#i export 'src/prediction/ports/fixture_prediction_repository.dart';" "$F"
sed -i "\#export 'src/prediction/submit_prediction.dart';#i export 'src/prediction/submit_fixture_prediction.dart';" "$F"
sed -i "\#export 'src/scoring/ports/score_repository.dart';#i export 'src/scoring/ports/fixture_score_repository.dart';" "$F"
sed -i "\#export 'src/scoring/score_round.dart';#i export 'src/scoring/score_fixture.dart';" "$F"

echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze packages/domain packages/application"
echo "  flutter test packages/domain packages/application"
