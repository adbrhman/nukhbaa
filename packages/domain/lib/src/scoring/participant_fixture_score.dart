import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/scoring/fixture_score_result.dart';
import 'package:shared/shared.dart';

/// A single participant's scored result for a single fixture — the output of
/// the Scoring phase under Axiom 4 Amendment ("ScoreFixture replaces
/// ScoreRound").
///
/// Replaces the round-scoped `RoundScore` (one row per (participant, round),
/// wrapping every fixture in that round). Under the amendment, scoring is
/// per-fixture: exactly one [ParticipantFixtureScore] per `(participant,
/// fixture)`, computed the instant that fixture's actual result lands —
/// never waiting on the rest of a round. It names [fixture] and
/// [participantId] by id only, carries the [result] (grade + points, already
/// reflecting the double multiplier when the prediction's `isDouble` was
/// set) and the [rulesetVersion] that governed it (Axiom 5,
/// reproducibility). It carries **no** round or group reference (Axiom 4).
///
/// Points here are a server-computed read value, not yet the competitive
/// -record instrument (that is the Ledger phase). Pure and immutable.
final class ParticipantFixtureScore {
  const ParticipantFixtureScore._({
    required this.fixture,
    required this.participantId,
    required this.rulesetVersion,
    required this.result,
  });

  /// Rehydrates a fixture score from already-trusted stored fields.
  const ParticipantFixtureScore.fromStored({
    required this.fixture,
    required this.participantId,
    required this.rulesetVersion,
    required this.result,
  });

  /// Builds a [ParticipantFixtureScore] from an already-graded [result].
  /// Not exposed for arbitrary construction — points are server-owned; this
  /// is used only internally by the fixture-scoring function.
  static Result<ParticipantFixtureScore> fromGraded({
    required FixtureRef fixture,
    required ParticipantId participantId,
    required int rulesetVersion,
    required FixtureScoreResult result,
  }) {
    if (result.fixture != fixture) {
      return const Result.err(
        AppError.invariant(
          'scoring.fixture_mismatch',
          'The graded result must be for the same fixture being scored',
        ),
      );
    }
    return Result.ok(
      ParticipantFixtureScore._(
        fixture: fixture,
        participantId: participantId,
        rulesetVersion: rulesetVersion,
        result: result,
      ),
    );
  }

  /// The fixture this score is for (by id — Axiom 3).
  final FixtureRef fixture;

  /// The participant this score belongs to. Combined with [fixture] this is
  /// the natural key — exactly one score per (participant, fixture).
  final ParticipantId participantId;

  /// The version of the frozen ruleset used to compute this score.
  final int rulesetVersion;

  /// The graded outcome (grade + points) for this fixture.
  final FixtureScoreResult result;

  /// The points awarded — a convenience accessor over [result].
  int get points => result.points;

  @override
  bool operator ==(Object other) =>
      other is ParticipantFixtureScore &&
      other.fixture == fixture &&
      other.participantId == participantId &&
      other.rulesetVersion == rulesetVersion &&
      other.result == result;

  @override
  int get hashCode =>
      Object.hash(fixture, participantId, rulesetVersion, result);

  @override
  String toString() =>
      'ParticipantFixtureScore(fixture: ${fixture.value}, '
      'participant: ${participantId.value}, v$rulesetVersion, '
      'points: ${result.points})';
}
