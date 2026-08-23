import 'package:domain/src/competition/fixture_ref.dart';
import 'package:shared/shared.dart';

/// How well a single fixture prediction matched the actual result — a closed
/// classification (Axiom 3: football-specific).
///
/// [exactScoreline], [correctOutcome] and [incorrect] are mutually exclusive
/// and ordered by specificity (exact ⊃ correctOutcome ⊃ incorrect) and apply
/// only once the fixture's actual result is known. [missed] stands apart from
/// that chain — it means no prediction was ever made, not that one was wrong.
/// [pending] stands apart too — a prediction exists but the fixture's actual
/// result has not been recorded yet (live/partial scoring, Phase: احتساب
/// فوري): the round can be scored while still in progress, and every
/// not-yet-decided fixture is graded [pending] rather than blocking the whole
/// round's scoring. Scoring maps each grade to a point award from the frozen
/// ruleset ([missed] and [pending] are always zero, unconditionally); nothing
/// else can grade a fixture.
enum FixtureScoreGrade {
  /// The predicted scoreline exactly matched the actual scoreline (which implies
  /// the outcome matched too).
  exactScoreline,

  /// The predicted match outcome (home win / draw / away win) matched, but the
  /// exact scoreline did not.
  correctOutcome,

  /// Neither the outcome nor the scoreline matched.
  incorrect,

  /// The fixture kicked off before the participant ever predicted it (a
  /// per-fixture lock, not a round-wide one), so there is no prediction to
  /// grade. Always worth zero points — never reward non-participation — and
  /// never subject to the double multiplier (there is nothing to double).
  missed,

  /// A prediction exists for this fixture, but the fixture's actual result has
  /// not been recorded yet — the match has not finished (or has not been
  /// ingested) at scoring time. Always worth zero points; re-scoring the round
  /// later, once the result lands, replaces this grade with the real one
  /// (exact/correct/incorrect). Never subject to the double multiplier (there
  /// is nothing final to double yet).
  pending;

  /// The stable wire/storage token for this grade, decoupled from the Dart
  /// identifier so persisted values can never drift silently.
  String get wireValue => switch (this) {
    FixtureScoreGrade.exactScoreline => 'exact_scoreline',
    FixtureScoreGrade.correctOutcome => 'correct_outcome',
    FixtureScoreGrade.incorrect => 'incorrect',
    FixtureScoreGrade.missed => 'missed',
    FixtureScoreGrade.pending => 'pending',
  };

  /// Parses a [FixtureScoreGrade] from an untrusted [raw] token (e.g. a stored
  /// row), returning a validation [AppError] when absent or unrecognized.
  static Result<FixtureScoreGrade> tryParse(String? raw) {
    for (final value in FixtureScoreGrade.values) {
      if (value.wireValue == raw) {
        return Result.ok(value);
      }
    }
    return Result.err(
      AppError.validation(
        'scoring.grade_unknown',
        'Unknown fixture score grade: ${raw ?? '<null>'}',
      ),
    );
  }
}

/// The scored outcome of one fixture within a round: the [grade] earned and the
/// [points] that grade is worth under the round's frozen ruleset.
///
/// A pure read value produced entirely server-side by the scoring function
/// (Axioms 2/5: the client never computes points). It names the [fixture] by id
/// only (Axiom 3) and carries no participant/round reference — those belong to
/// the enclosing [RoundScore]. Immutable; value-comparable.
final class FixtureScoreResult {
  /// Creates a fixture score result. Constructed only by the domain scoring
  /// function and by infrastructure rehydration of an already-scored row; both
  /// sources are trusted, so no re-validation is performed here.
  const FixtureScoreResult({
    required this.fixture,
    required this.grade,
    required this.points,
  });

  /// The fixture this result grades (by id — Axiom 3).
  final FixtureRef fixture;

  /// How the prediction for this fixture matched the actual result.
  final FixtureScoreGrade grade;

  /// The points awarded for this fixture under the round's frozen ruleset
  /// (non-negative; server-computed).
  final int points;

  @override
  bool operator ==(Object other) =>
      other is FixtureScoreResult &&
      other.fixture == fixture &&
      other.grade == grade &&
      other.points == points;

  @override
  int get hashCode => Object.hash(fixture, grade, points);

  @override
  String toString() =>
      'FixtureScoreResult(fixture: ${fixture.value}, '
      '${grade.wireValue}, points: $points)';
}
