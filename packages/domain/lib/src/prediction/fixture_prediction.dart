import 'package:domain/src/competition/fixture_lock.dart';
import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/prediction/prediction_id.dart';
import 'package:shared/shared.dart';

/// The `FixturePrediction` aggregate root — a single participant's forecast
/// for a single fixture (docs/project-context.md, Axiom 4 Amendment).
///
/// Replaces the round-scoped `Prediction` (one row per round, N child
/// `FixtureScorePrediction`s submitted atomically). Under the amendment,
/// `Prediction` and `FixtureScorePrediction` merge into this one per-fixture
/// entity, keyed by `(fixture, participantId)` instead of `(roundId,
/// participantId)`. Each fixture arrives as its own independent submission
/// over time, not as part of a round's atomic batch.
///
/// It carries **no** round or group reference (Axiom 4: "predict once, rank
/// everywhere" — reused across every ranking context) and names the fixture
/// by id only (Axiom 3: the football seam). Points are never computed or
/// stored here — that is the server-only Scoring phase.
///
/// Invariants encoded as types / enforced at construction:
/// * Exactly **one** prediction per `(participant, fixture)` — enforced
///   physically by a unique constraint in the migration (Axiom 6 backstop).
/// * A prediction may only be submitted or amended while its fixture's
///   [FixtureLock] is **not** locked (i.e. before kickoff).
/// * Goal tallies are non-negative and within [maxGoals].
/// * [isDouble] is a plain flag here — the cross-fixture "at most one double
///   per UTC day" cap is **not** self-checkable by a single-fixture
///   aggregate anymore; it is enforced in the application layer
///   (`DailyDoublePolicy`) against a same-day repository count.
///
/// Pure and immutable; a change produces a new instance via [amend].
final class FixturePrediction {
  const FixturePrediction._({
    required this.id,
    required this.fixture,
    required this.participantId,
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
  });

  /// Rehydrates a fixture prediction from already-trusted stored fields.
  const FixturePrediction.fromStored({
    required this.id,
    required this.fixture,
    required this.participantId,
    required this.homeGoals,
    required this.awayGoals,
    this.isDouble = false,
  });

  /// Creates a brand-new prediction for [participantId] on [fixture].
  ///
  /// Fails with an [AppError] when [lock] is already locked (kickoff has
  /// arrived/passed) or the goal tallies are invalid. The caller supplies
  /// the server-minted [id] (the client never mints ids — Axioms 2/5).
  static Result<FixturePrediction> submit({
    required PredictionId id,
    required FixtureRef fixture,
    required ParticipantId participantId,
    required FixtureLock lock,
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
  }) {
    if (lock.isLocked) {
      return const Result.err(
        AppError.invariant(
          'prediction.fixture_locked',
          'Predictions can only be submitted before the fixture kicks off',
        ),
      );
    }
    final goalsError = _validateGoals(homeGoals, awayGoals);
    if (goalsError != null) {
      return Result.err(goalsError);
    }
    return Result.ok(
      FixturePrediction._(
        id: id,
        fixture: fixture,
        participantId: participantId,
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        isDouble: isDouble,
      ),
    );
  }

  /// Produces an amended copy of this prediction. Identity ([id], [fixture],
  /// [participantId]) is preserved — an amendment is the same prediction
  /// updated in place, never a second row. Fails when [lock] is already
  /// locked, or the goal tallies are invalid.
  Result<FixturePrediction> amend({
    required FixtureLock lock,
    required int homeGoals,
    required int awayGoals,
    required bool isDouble,
  }) {
    if (lock.isLocked) {
      return const Result.err(
        AppError.invariant(
          'prediction.fixture_locked',
          'Predictions can only be amended before the fixture kicks off',
        ),
      );
    }
    final goalsError = _validateGoals(homeGoals, awayGoals);
    if (goalsError != null) {
      return Result.err(goalsError);
    }
    return Result.ok(
      FixturePrediction._(
        id: id,
        fixture: fixture,
        participantId: participantId,
        homeGoals: homeGoals,
        awayGoals: awayGoals,
        isDouble: isDouble,
      ),
    );
  }

  /// The upper bound on a single side's predicted goals, mirroring the
  /// legacy `FixtureScorePrediction.maxGoals` and the DB check constraint.
  static const int maxGoals = 99;

  static AppError? _validateGoals(int homeGoals, int awayGoals) {
    final homeError = _validateSide('home', homeGoals);
    if (homeError != null) {
      return homeError;
    }
    return _validateSide('away', awayGoals);
  }

  static AppError? _validateSide(String side, int goals) {
    if (goals < 0) {
      return AppError.validation(
        'prediction.score_negative',
        'Predicted $side goals must not be negative',
      );
    }
    if (goals > maxGoals) {
      return AppError.validation(
        'prediction.score_out_of_range',
        'Predicted $side goals must not exceed $maxGoals',
      );
    }
    return null;
  }

  /// The server-minted identity of this prediction.
  final PredictionId id;

  /// The fixture this prediction is for (owned by Football Data; referenced
  /// by id only — Axiom 3).
  final FixtureRef fixture;

  /// The participant who made this prediction. Combined with [fixture] this
  /// is the aggregate's natural key.
  final ParticipantId participantId;

  /// The predicted number of goals for the home side (non-negative).
  final int homeGoals;

  /// The predicted number of goals for the away side (non-negative).
  final int awayGoals;

  /// Whether the participant marked this fixture as their double for the day
  /// — the cross-fixture "at most one per UTC day" cap is enforced by the
  /// application layer (`DailyDoublePolicy`), not by this aggregate.
  final bool isDouble;

  @override
  bool operator ==(Object other) =>
      other is FixturePrediction &&
      other.id == id &&
      other.fixture == fixture &&
      other.participantId == participantId &&
      other.homeGoals == homeGoals &&
      other.awayGoals == awayGoals &&
      other.isDouble == isDouble;

  @override
  int get hashCode =>
      Object.hash(id, fixture, participantId, homeGoals, awayGoals, isDouble);

  @override
  String toString() =>
      'FixturePrediction(id: ${id.value}, fixture: ${fixture.value}, '
      'participant: ${participantId.value}, $homeGoals-$awayGoals'
      '${isDouble ? ', DOUBLE' : ''})';
}
