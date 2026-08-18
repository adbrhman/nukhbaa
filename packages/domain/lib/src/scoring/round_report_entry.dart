import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/scoring/fixture_score_result.dart';
import 'package:domain/src/scoring/round_score.dart';

/// One participant's aggregated summary for a round report — counts of
/// correct/incorrect fixture grades plus the already-derived total points
/// (Task 5: a pure count/group-by over the existing scored round; no new
/// points math, no new source of truth — Axioms 2/5).
///
/// [correctCount] counts fixtures graded [FixtureScoreGrade.exactScoreline]
/// or [FixtureScoreGrade.correctOutcome]; [incorrectCount] counts
/// [FixtureScoreGrade.incorrect]. A [FixtureScoreGrade.missed] fixture (no
/// prediction was ever made) counts toward neither — it is absence, not a
/// wrong guess.
final class RoundReportEntry {
  const RoundReportEntry({
    required this.participantId,
    required this.correctCount,
    required this.incorrectCount,
    required this.totalPoints,
  });

  /// Aggregates one participant's [RoundScore] into its report entry.
  factory RoundReportEntry.fromScore(RoundScore score) {
    var correct = 0;
    var incorrect = 0;
    for (final result in score.fixtureResults) {
      switch (result.grade) {
        case FixtureScoreGrade.exactScoreline:
        case FixtureScoreGrade.correctOutcome:
          correct++;
        case FixtureScoreGrade.incorrect:
          incorrect++;
        case FixtureScoreGrade.missed:
          break;
      }
    }
    return RoundReportEntry(
      participantId: score.participantId,
      correctCount: correct,
      incorrectCount: incorrect,
      totalPoints: score.totalPoints,
    );
  }

  /// The participant this entry belongs to (by id).
  final ParticipantId participantId;

  /// Fixtures graded exact-scoreline or correct-outcome.
  final int correctCount;

  /// Fixtures graded incorrect.
  final int incorrectCount;

  /// The same derived total the round score carries — never recomputed.
  final int totalPoints;

  @override
  bool operator ==(Object other) =>
      other is RoundReportEntry &&
      other.participantId == participantId &&
      other.correctCount == correctCount &&
      other.incorrectCount == incorrectCount &&
      other.totalPoints == totalPoints;

  @override
  int get hashCode =>
      Object.hash(participantId, correctCount, incorrectCount, totalPoints);

  @override
  String toString() =>
      'RoundReportEntry(participant: ${participantId.value}, '
      'correct: $correctCount, incorrect: $incorrectCount, '
      'points: $totalPoints)';
}
