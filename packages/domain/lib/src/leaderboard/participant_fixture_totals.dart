import 'package:domain/src/competition/participant_id.dart';
import 'package:shared/shared.dart';

/// One participant's already-summed fixture results for a set of fixtures:
/// the same four numbers `FixtureLeaderboard.rank` folds out of individual
/// `ParticipantFixtureScore` rows, delivered pre-summed by the store so the
/// rows never have to travel. Summing is not scoring: every point here was
/// produced by `ScoreFixture` (Axioms 2/5).
final class ParticipantFixtureTotals {
  const ParticipantFixtureTotals._({
    required this.participantId,
    required this.totalPoints,
    required this.fixturesScored,
    required this.exactCount,
    required this.decidedCount,
  });

  /// Builds the totals, refusing numbers no set of fixture scores can sum to.
  static Result<ParticipantFixtureTotals> of({
    required ParticipantId participantId,
    required int totalPoints,
    required int fixturesScored,
    required int exactCount,
    required int decidedCount,
  }) {
    if (totalPoints < 0 ||
        fixturesScored < 0 ||
        exactCount < 0 ||
        decidedCount < 0) {
      return const Result.err(
        AppError.invariant(
          'fixture_totals.negative',
          'Fixture totals cannot be negative',
        ),
      );
    }
    if (exactCount > decidedCount || decidedCount > fixturesScored) {
      return const Result.err(
        AppError.invariant(
          'fixture_totals.inconsistent',
          'exact <= decided <= scored must hold for fixture totals',
        ),
      );
    }
    return Result.ok(
      ParticipantFixtureTotals._(
        participantId: participantId,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
      ),
    );
  }

  /// Whose totals these are.
  final ParticipantId participantId;

  /// Points summed over the fixtures.
  final int totalPoints;

  /// How many of the fixtures carry a score for this participant.
  final int fixturesScored;

  /// Decided fixtures called exactly right.
  final int exactCount;

  /// Decided fixtures (pending excluded).
  final int decidedCount;

  @override
  bool operator ==(Object other) =>
      other is ParticipantFixtureTotals &&
      other.participantId == participantId &&
      other.totalPoints == totalPoints &&
      other.fixturesScored == fixturesScored &&
      other.exactCount == exactCount &&
      other.decidedCount == decidedCount;

  @override
  int get hashCode => Object.hash(
    participantId,
    totalPoints,
    fixturesScored,
    exactCount,
    decidedCount,
  );
}
