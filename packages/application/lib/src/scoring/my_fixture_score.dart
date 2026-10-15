import 'package:domain/domain.dart';

/// One of the caller's own predictions with its score and the match's final
/// score, as far as each exists -- the read model behind
/// `GET /me/fixture-scores` (migration 0171, script 75).
///
/// A row exists once the fixture has a recorded result or the prediction a
/// score; [grade] and [points] stay null while the result waits for scoring.
/// Keyed by ([participantId], [fixture]): a fixture of two seasons the user
/// joined is two predictions, so two rows.
///
/// Pure and immutable; value-comparable by every field.
final class MyFixtureScore {
  /// Creates the read model.
  const MyFixtureScore({
    required this.participantId,
    required this.fixture,
    this.grade,
    this.points,
    this.result,
  });

  /// The caller's participant row the prediction belongs to (one per season).
  final ParticipantId participantId;

  /// The predicted fixture.
  final FixtureRef fixture;

  /// The server's verdict; null until the prediction is scored.
  final FixtureScoreGrade? grade;

  /// The points awarded (already doubled for the day's double); null until
  /// the prediction is scored.
  final int? points;

  /// The recorded final score; null until a result is recorded.
  final FixtureResult? result;

  @override
  bool operator ==(Object other) =>
      other is MyFixtureScore &&
      other.participantId == participantId &&
      other.fixture == fixture &&
      other.grade == grade &&
      other.points == points &&
      other.result?.homeGoals == result?.homeGoals &&
      other.result?.awayGoals == result?.awayGoals;

  @override
  int get hashCode => Object.hash(
    participantId,
    fixture,
    grade,
    points,
    result?.homeGoals,
    result?.awayGoals,
  );
}
