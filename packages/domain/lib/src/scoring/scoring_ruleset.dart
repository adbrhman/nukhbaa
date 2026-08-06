import 'package:domain/src/competition/ruleset_snapshot.dart';
import 'package:shared/shared.dart';

/// The **typed** interpretation of a round's frozen [RulesetSnapshot] for the
/// football-scoreline format.
///
/// Competition freezes the ruleset as an *opaque, structured* payload it never
/// interprets (see `RulesetSnapshot` doc: "only the Scoring context interprets
/// its keys"). This value object is that interpretation: it parses the exact
/// payload shape produced by `ConfiguredRulesetProvider`
/// (`{format: 'football_scoreline', points: {exact_scoreline, correct_outcome,
/// incorrect}}`) into three validated point awards, and rejects anything that
/// does not match — a corrupt or foreign snapshot is a typed failure, never a
/// silent zero (Security ADR §2: untrusted/structured input is validated).
///
/// Reading the snapshot at scoring time (not baking rules into code) is what
/// makes historical rounds reproducible: a round scored under ruleset v1 keeps
/// scoring by v1 forever, because v1's numbers are the ones frozen on it
/// (`RulesetSnapshot` doc; Axiom 5, the competitive record is the protected
/// asset). Pure and immutable.
final class ScoringRuleset {
  const ScoringRuleset._({
    required this.rulesetVersion,
    required this.exactScorelinePoints,
    required this.correctOutcomePoints,
    required this.incorrectPoints,
    required this.doubleMultiplier,
  });

  /// The wire token identifying the football-scoreline format inside a snapshot
  /// payload. Matches `ConfiguredRulesetProvider` and `FormatType.wireValue`.
  static const String footballScorelineFormat = 'football_scoreline';

  /// Interprets a frozen [snapshot] as football-scoreline scoring rules.
  ///
  /// Validates that the payload declares the football-scoreline format and
  /// carries a `points` map with integer, non-negative `exact_scoreline`,
  /// `correct_outcome`, and `incorrect` awards, and that a more-specific result
  /// is worth at least as much as a less-specific one
  /// (`exact_scoreline >= correct_outcome >= incorrect`) — a monotonicity the
  /// scoring model relies on and a cheap guard against a transposed/corrupt
  /// snapshot. Returns a validation [AppError] otherwise (kept total).
  static Result<ScoringRuleset> fromSnapshot(RulesetSnapshot snapshot) {
    final payload = snapshot.payload;

    final format = payload['format'];
    if (format != footballScorelineFormat) {
      return Result.err(
        AppError.validation(
          'scoring.ruleset_format_unsupported',
          'Scoring supports only the $footballScorelineFormat format; '
              'got ${format ?? '<null>'}',
        ),
      );
    }

    final rawPoints = payload['points'];
    if (rawPoints is! Map) {
      return const Result.err(
        AppError.validation(
          'scoring.ruleset_points_missing',
          'Ruleset snapshot is missing a points map',
        ),
      );
    }

    final exact = _readAward(rawPoints, 'exact_scoreline');
    if (exact is Err<int>) {
      return Result.err(exact.error);
    }
    final outcome = _readAward(rawPoints, 'correct_outcome');
    if (outcome is Err<int>) {
      return Result.err(outcome.error);
    }
    final incorrect = _readAward(rawPoints, 'incorrect');
    if (incorrect is Err<int>) {
      return Result.err(incorrect.error);
    }

    final exactPts = (exact as Ok<int>).value;
    final outcomePts = (outcome as Ok<int>).value;
    final incorrectPts = (incorrect as Ok<int>).value;

    if (exactPts < outcomePts || outcomePts < incorrectPts) {
      return const Result.err(
        AppError.validation(
          'scoring.ruleset_non_monotonic',
          'Point awards must satisfy '
              'exact_scoreline >= correct_outcome >= incorrect',
        ),
      );
    }

    // `double_multiplier` is read from the top-level payload (a multiplier is
    // not a per-grade point award, unlike the three keys above). Absent on
    // older frozen snapshots (pre-double rulesets) — defaults to 1 (no
    // multiplier effect) so a historical round keeps reproducing its original
    // score exactly (Axiom 5): those rounds never had a double to begin with.
    final rawMultiplier = payload['double_multiplier'];
    var multiplier = 1;
    if (rawMultiplier != null) {
      if (rawMultiplier is! int || rawMultiplier < 1) {
        return Result.err(
          AppError.validation(
            'scoring.ruleset_double_multiplier_invalid',
            'Ruleset "double_multiplier" must be an integer >= 1; got '
                '$rawMultiplier',
          ),
        );
      }
      multiplier = rawMultiplier;
    }

    return Result.ok(
      ScoringRuleset._(
        rulesetVersion: snapshot.rulesetVersion,
        exactScorelinePoints: exactPts,
        correctOutcomePoints: outcomePts,
        incorrectPoints: incorrectPts,
        doubleMultiplier: multiplier,
      ),
    );
  }

  static Result<int> _readAward(Map<Object?, Object?> points, String key) {
    final raw = points[key];
    if (raw is! int) {
      return Result.err(
        AppError.validation(
          'scoring.ruleset_award_invalid',
          'Point award "$key" must be an integer; got ${raw ?? '<null>'}',
        ),
      );
    }
    if (raw < 0) {
      return Result.err(
        AppError.validation(
          'scoring.ruleset_award_negative',
          'Point award "$key" must not be negative',
        ),
      );
    }
    return Result.ok(raw);
  }

  /// The version of the source ruleset this interpretation was frozen from
  /// (carried through from the snapshot for traceability/reproducibility).
  final int rulesetVersion;

  /// Points awarded when the predicted scoreline exactly matches the actual one.
  final int exactScorelinePoints;

  /// Points awarded when the predicted match outcome (home win / draw / away
  /// win) matches but the exact scoreline does not.
  final int correctOutcomePoints;

  /// Points awarded when neither the outcome nor the scoreline is correct.
  final int incorrectPoints;

  /// The factor applied to whatever points a fixture earns (at any grade
  /// except [FixtureScoreGrade.missed]) when the participant marked it as
  /// their round double. Always >= 1; defaults to 1 (no effect) when the
  /// frozen snapshot predates the double feature.
  final int doubleMultiplier;

  @override
  bool operator ==(Object other) =>
      other is ScoringRuleset &&
      other.rulesetVersion == rulesetVersion &&
      other.exactScorelinePoints == exactScorelinePoints &&
      other.correctOutcomePoints == correctOutcomePoints &&
      other.incorrectPoints == incorrectPoints &&
      other.doubleMultiplier == doubleMultiplier;

  @override
  int get hashCode => Object.hash(
    rulesetVersion,
    exactScorelinePoints,
    correctOutcomePoints,
    incorrectPoints,
    doubleMultiplier,
  );

  @override
  String toString() =>
      'ScoringRuleset(v$rulesetVersion, exact: $exactScorelinePoints, '
      'outcome: $correctOutcomePoints, incorrect: $incorrectPoints, '
      'doubleMultiplier: $doubleMultiplier)';
}
