import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/prediction/fixture_prediction.dart';
import 'package:domain/src/prediction/fixture_score_prediction.dart';
import 'package:domain/src/prediction/prediction.dart';
import 'package:domain/src/scoring/fixture_result.dart';
import 'package:domain/src/scoring/fixture_score_result.dart';
import 'package:domain/src/scoring/participant_fixture_score.dart';
import 'package:domain/src/scoring/round_score.dart';
import 'package:domain/src/scoring/scoring_ruleset.dart';
import 'package:shared/shared.dart';

/// The pure Scoring domain service: turn one [Prediction] plus the actual
/// [FixtureResult]s into a [RoundScore], under the round's frozen
/// [ScoringRuleset] (Axioms 2/5: computed server-side only; the client never
/// computes or submits points).
///
/// This is framework-free, total (returns [Result], never throws), and
/// deterministic — the same inputs always yield the same score, which is what
/// makes scoring reproducible and re-runnable (idempotency at the use-case level
/// builds on this determinism). It does not persist anything; persistence and
/// the append-only `PointEntry` record are the Ledger phase (Axiom 5).
///
/// Grading per fixture the participant actually predicted (most-specific
/// first, so an exact match is never also counted as a mere correct outcome),
/// each multiplied by [ScoringRuleset.doubleMultiplier] when the participant
/// marked that fixture as their double:
/// 1. exact scoreline (home & away both match) → [ScoringRuleset.exactScorelinePoints];
/// 2. otherwise correct outcome (same home-win/draw/away-win) →
///    [ScoringRuleset.correctOutcomePoints];
/// 3. otherwise incorrect → [ScoringRuleset.incorrectPoints].
///
/// A round fixture the participant never predicted — because it kicked off
/// before they ever forecast it, under the per-fixture kickoff lock enforced
/// by `SubmitPrediction` — is graded [FixtureScoreGrade.missed], always worth
/// zero regardless of the double multiplier: there is no forecast to double.
abstract final class Scoring {
  /// Scores [prediction] against [results] under [ruleset].
  ///
  /// [results] holds whatever actual results have been recorded for the round
  /// so far — it no longer needs to cover every fixture (live/partial
  /// scoring, Phase: احتساب فوري): a round may now be scored while some
  /// fixtures haven't kicked off or finished yet. [prediction] likewise no
  /// longer needs to cover every fixture in the round: since fixtures lock
  /// individually at kickoff, a participant who joined late may have fewer
  /// scores than the round has fixtures, and each of those uncovered fixtures
  /// is graded `missed` rather than rejected. A fixture the participant DID
  /// predict but that has no recorded result yet is graded `pending`
  /// (always zero points) rather than rejected — re-scoring the round later,
  /// once the result lands, replaces it with the real grade. [results] must
  /// still contain no duplicates for the same fixture.
  ///
  /// The per-fixture breakdown preserves the prediction's own fixture order
  /// for every fixture it covers (Axiom 4: the one forecast, graded in
  /// place), then appends any missed fixtures ordered by fixture id for a
  /// stable, deterministic breakdown.
  static Result<RoundScore> scoreRound({
    required Prediction prediction,
    required ScoringRuleset ruleset,
    required List<FixtureResult> results,
  }) {
    final resultsByFixture = <String, FixtureResult>{};
    for (final result in results) {
      final key = result.fixture.value;
      if (resultsByFixture.containsKey(key)) {
        return const Result.err(
          AppError.invariant(
            'scoring.duplicate_result',
            'The result set contains more than one result for a fixture',
          ),
        );
      }
      resultsByFixture[key] = result;
    }

    final graded = <FixtureScoreResult>[];
    final coveredFixtureIds = <String>{};
    for (final scorePrediction in prediction.scores) {
      final result = resultsByFixture[scorePrediction.fixture.value];
      if (result == null) {
        // The fixture was predicted, but its actual result hasn't been
        // recorded yet — live/partial scoring grades it `pending` (always
        // zero) rather than rejecting the whole round's scoring. Re-scoring
        // later, once the result lands, replaces this grade with the real
        // one.
        graded.add(
          FixtureScoreResult(
            fixture: scorePrediction.fixture,
            grade: FixtureScoreGrade.pending,
            points: 0,
          ),
        );
        coveredFixtureIds.add(scorePrediction.fixture.value);
        continue;
      }
      graded.add(_gradeFixture(scorePrediction, result, ruleset));
      coveredFixtureIds.add(scorePrediction.fixture.value);
    }

    // Every round fixture with a result but no matching prediction was
    // locked (kicked off) before the participant ever forecast it — graded
    // `missed`, never rewarded. Sorted by fixture id: `results` order is not
    // guaranteed by its repository port, so this keeps the breakdown
    // deterministic across runs.
    final missed =
        results
            .where(
              (result) => !coveredFixtureIds.contains(result.fixture.value),
            )
            .toList()
          ..sort((a, b) => a.fixture.value.compareTo(b.fixture.value));
    for (final result in missed) {
      graded.add(
        FixtureScoreResult(
          fixture: result.fixture,
          grade: FixtureScoreGrade.missed,
          points: 0,
        ),
      );
    }

    return RoundScore.fromGraded(
      roundId: prediction.roundId,
      participantId: prediction.participantId,
      rulesetVersion: ruleset.rulesetVersion,
      fixtureResults: graded,
    );
  }

  /// Scores a single [FixturePrediction] against its fixture's actual
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

  static FixtureScoreResult _gradeFixture(
    FixtureScorePrediction prediction,
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
}
