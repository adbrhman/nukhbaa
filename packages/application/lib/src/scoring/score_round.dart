import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/prediction_repository.dart';
import 'package:application/src/prediction/prediction_view.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/scoring/ports/score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: score every prediction in a round (Application ADR, Section 2:
/// command intent `ScoreRound`).
///
/// This is the server-side heart of the Scoring phase (Axioms 2/5: points are
/// computed and written server-side only; the client never computes or submits
/// them). It:
/// 1. authorizes the caller as an **admin** (only the platform scores);
/// 2. loads the round — scoring is now allowed regardless of round status
///    (`open`, `locked`, or `scored`; live/partial scoring, Phase: احتساب
///    فوري): fixtures with no recorded result yet are graded `pending` (see
///    below), so an admin can see a live, continuously-updating leaderboard
///    while a round is still in progress rather than only after it locks;
/// 3. interprets the round's **frozen** [RulesetSnapshot] as a [ScoringRuleset]
///    (reading the frozen rules is what makes a historical round reproducible —
///    Axiom 5);
/// 4. reads every participant's one prediction ([PredictionRepository.listByRound])
///    and whatever actual [FixtureResult]s have been recorded so far for the
///    round's fixtures ([FixtureResultRepository]) — no longer required to be
///    complete: any fixture still missing a result is graded
///    [FixtureScoreGrade.pending] (always zero points) by the pure domain
///    service rather than blocking the whole round's scoring;
/// 5. runs the pure domain [Scoring.scoreRound] per prediction (total,
///    deterministic — same inputs, same score);
/// 6. persists all [RoundScore]s atomically and, only once the round is
///    [RoundStatus.locked] AND every one of its fixtures now has a recorded
///    result, transitions it `locked → scored` under an optimistic-concurrency
///    guard. A partial scoring pass (round still `open`, or some fixtures
///    still without a result) persists the live scores without moving the
///    round's status.
///
/// **Idempotent** (Application ADR, Section 2): the score persistence upserts
/// per `(round, participant)` and re-running scoring — whether partially, as
/// more results arrive, or on an already-`scored` round — recomputes the same
/// deterministic result and re-persists it without creating duplicates.
/// Because the guarded status transition only fires on the `locked → scored`
/// edge once results are complete, a replay on an already-`scored` round
/// re-writes the (identical) scores and reports success without a spurious
/// transition conflict.
///
/// Never throws; returns a typed [Result] carrying the scored [RoundScore]s.
final class ScoreRound {
  /// Creates the use-case over its collaborators.
  const ScoreRound({
    required CompetitionRepository competitionRepository,
    required PredictionRepository predictionRepository,
    required FixtureResultRepository resultRepository,
    required ScoreRepository scoreRepository,
  }) : _competition = competitionRepository,
       _predictions = predictionRepository,
       _results = resultRepository,
       _scores = scoreRepository;

  final CompetitionRepository _competition;
  final PredictionRepository _predictions;
  final FixtureResultRepository _results;
  final ScoreRepository _scores;

  /// Scores round [roundId] on behalf of admin [principal].
  Future<Result<List<RoundScore>>> call({
    required AuthenticatedUser principal,
    required String roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) {
      return Result.err(roundIdResult.error);
    }
    final rId = (roundIdResult as Ok<RoundId>).value;

    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) {
      return Result.err(roundResult.error);
    }
    final round = (roundResult as Ok<Round>).value;

    // Interpret the frozen ruleset. A corrupt/foreign snapshot is a typed
    // failure, never a silent zero score.
    final rulesetResult = ScoringRuleset.fromSnapshot(round.ruleset);
    if (rulesetResult is Err<ScoringRuleset>) {
      return Result.err(rulesetResult.error);
    }
    final ruleset = (rulesetResult as Ok<ScoringRuleset>).value;

    // The round's fixture composition — the exact set every prediction covers
    // and the set of results scoring needs.
    final fixturesResult = await _predictions.listRoundFixtures(rId);
    if (fixturesResult is Err<List<RoundFixture>>) {
      return Result.err(fixturesResult.error);
    }
    final roundFixtures = (fixturesResult as Ok<List<RoundFixture>>).value;
    if (roundFixtures.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'scoring.round_has_no_fixtures',
          'A round with no fixtures cannot be scored',
        ),
      );
    }
    final fixtureRefs = <FixtureRef>[
      for (final link in roundFixtures) link.fixture,
    ];

    // Load whatever actual results have been recorded so far. No longer
    // required to cover every linked fixture (live/partial scoring, Phase:
    // احتساب فوري) — any fixture still missing a result is graded `pending`
    // by the pure domain service below, rather than blocking scoring.
    final resultsResult = await _results.findByFixtures(fixtureRefs);
    if (resultsResult is Err<List<FixtureResult>>) {
      return Result.err(resultsResult.error);
    }
    final results = (resultsResult as Ok<List<FixtureResult>>).value;
    final resultsComplete = results.length == fixtureRefs.length;

    // Load every participant's prediction for the round.
    final predictionsResult = await _predictions.listByRound(rId);
    if (predictionsResult is Err<List<PredictionView>>) {
      return Result.err(predictionsResult.error);
    }
    final predictions = (predictionsResult as Ok<List<PredictionView>>).value;

    // Score each prediction with the pure domain service (deterministic).
    final roundScores = <RoundScore>[];
    for (final view in predictions) {
      final scored = Scoring.scoreRound(
        prediction: view.prediction,
        ruleset: ruleset,
        results: results,
      );
      if (scored is Err<RoundScore>) {
        return Result.err(scored.error);
      }
      roundScores.add((scored as Ok<RoundScore>).value);
    }

    // Persist all scores atomically (all-or-nothing; idempotent per participant).
    final saved = await _scores.saveRoundScores(roundScores);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    // Transition locked → scored under an optimistic-concurrency guard — only
    // once every fixture actually has a recorded result (live/partial scoring
    // must never mark a round `scored` while some fixtures are still
    // `pending`). When the round is already scored (idempotent replay) there
    // is no edge to fire: the scores were re-persisted above, so report
    // success without transitioning. An `open` round, or a `locked` round with
    // incomplete results, simply keeps its current status — this is a live
    // partial-scoring pass, not a phase transition.
    if (round.status == RoundStatus.locked && resultsComplete) {
      final transitioned = round.transitionTo(RoundStatus.scored);
      if (transitioned is Err<Round>) {
        return Result.err(transitioned.error);
      }
      final scoredRound = (transitioned as Ok<Round>).value;
      final statusSaved = await _competition.updateRoundStatus(
        scoredRound,
        RoundStatus.locked,
      );
      if (statusSaved is Err<void>) {
        return Result.err(statusSaved.error);
      }
    }

    return Result.ok(List<RoundScore>.unmodifiable(roundScores));
  }
}
