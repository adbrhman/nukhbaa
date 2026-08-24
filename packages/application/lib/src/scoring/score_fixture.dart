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

    final predictionsResult = await _fixturePredictions.listByFixture(fixture);
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

    return Result.ok(List<ParticipantFixtureScore>.unmodifiable(fixtureScores));
  }
}
