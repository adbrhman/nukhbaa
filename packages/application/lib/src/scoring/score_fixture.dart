import 'package:application/src/competition/fixture_visibility.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/competition/ports/ruleset_provider.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/notify_fixture_winners.dart';
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
/// 6. adds the sole exact bonus ([Scoring.applySoloExactBonus], decided by
///    the owner 2026-10-27): once the result is in, the only exact call of
///    the fixture among every prediction of it earns
///    [ScoringRuleset.soloExactBonusPoints] more (3 + 3 = 6, a double
///    6 + 3 = 9), on a fixture that kicked off at or after
///    [ScoringRuleset.soloExactSince] -- read from the stored kickoff, so an
///    unknown kickoff (no schedule repository) pays no bonus;
/// 7. persists all [ParticipantFixtureScore]s atomically
///    ([FixtureScoreRepository.saveFixtureScores]).
///
/// **Idempotent**: re-running scoring for the same fixture — before or after
/// its result lands — recomputes the same deterministic result and
/// re-persists it without creating duplicates (one score per
/// `(fixture, participant)`).
///
/// **Hidden and test fixtures** (migration 0098) are not scored: the call
/// succeeds with no scores, persists nothing and notifies nobody. A hidden
/// fixture is scored once it is shown again (the rescore sweep finds it); a
/// test fixture never is. Applied when the schedule repository is wired.
///
/// **Sent after kickoff** (same condition): once the result is in, a
/// prediction stamped at or after the stored kickoff is graded `incorrect`
/// for zero points. The lock refuses such a prediction, so one exists only
/// when the kickoff was brought forward after it was sent.
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
    NotifyFixtureWinners? winnerNotifier,
    FixtureScheduleRepository? fixtureScheduleRepository,
  }) : _fixturePredictions = fixturePredictionRepository,
       _results = resultRepository,
       _scores = scoreRepository,
       _rulesetProvider = rulesetProvider,
       _winnerNotifier = winnerNotifier,
       _schedules = fixtureScheduleRepository;

  final FixturePredictionRepository _fixturePredictions;
  final FixtureResultRepository _results;
  final FixtureScoreRepository _scores;
  final RulesetProvider _rulesetProvider;

  /// Optional Tier-3 announcer. Null in the test roots and in any composition
  /// that has no push transport; scoring behaves identically either way.
  final NotifyFixtureWinners? _winnerNotifier;

  /// Optional: without it every fixture is scored, as before 0098.
  final FixtureScheduleRepository? _schedules;

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

    final schedules = _schedules;
    final Result<FixtureSchedule?> scheduleResult = schedules == null
        ? const Result.ok(null)
        : await schedules.findByFixture(fixture);
    if (scheduleResult is Err<FixtureSchedule?>) {
      return Result.err(scheduleResult.error);
    }
    final schedule = (scheduleResult as Ok<FixtureSchedule?>).value;
    if (!FixtureVisibility.scorable(schedule)) {
      return const Result.ok(<ParticipantFixtureScore>[]);
    }
    // A prediction stamped at or after the stored kickoff was sent once the
    // match had started -- possible only when the kickoff was brought
    // forward after it was sent (provider sync or an admin correction, C-03).
    // It earns nothing, whatever it says.
    final DateTime? kickoffAt = schedule?.kickoffAt.toUtc();

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
    // No hard gate on an empty list (Option-3 live/partial philosophy,
    // matching ScoreRound): a fixture nobody has predicted yet simply has
    // nothing to score, not an error — mirrors ScoreRound's tolerance of a
    // round with zero submitted predictions.

    final fixtureScores = <ParticipantFixtureScore>[];
    for (final view in predictions) {
      final bool sentAfterKickoff =
          result != null &&
          kickoffAt != null &&
          !view.submittedAt.toUtc().isBefore(kickoffAt);
      final scored = sentAfterKickoff
          ? ParticipantFixtureScore.fromGraded(
              fixture: view.prediction.fixture,
              participantId: view.prediction.participantId,
              rulesetVersion: ruleset.rulesetVersion,
              result: FixtureScoreResult(
                fixture: view.prediction.fixture,
                grade: FixtureScoreGrade.incorrect,
                points: 0,
              ),
            )
          : Scoring.scoreFixture(
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

    // The sole exact call, among every prediction of the fixture: graded
    // here, where all of them are, and stored in its points.
    final int? soloIndex = result == null
        ? null
        : Scoring.soloExactIndex(
            grades: <FixtureScoreGrade>[
              for (final score in fixtureScores) score.result.grade,
            ],
            ruleset: ruleset,
            kickoffAt: kickoffAt,
          );
    final List<ParticipantFixtureScore> finalScores = result == null
        ? fixtureScores
        : Scoring.applySoloExactBonus(
            scores: fixtureScores,
            ruleset: ruleset,
            kickoffAt: kickoffAt,
          );

    final saved = await _scores.saveFixtureScores(finalScores);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    // Tier-3 (ADR 0007 SS2.4): tell the exact callers. Awaited so the push
    // leaves before the request ends, but its Result is deliberately dropped
    // -- an unreachable phone must never fail a scored fixture.
    final notifier = _winnerNotifier;
    if (notifier != null) {
      await notifier(
        fixture: fixture,
        scores: finalScores,
        doubled: <ParticipantId>{
          for (final view in predictions)
            if (view.prediction.isDouble) view.prediction.participantId,
        },
        solo: soloIndex == null ? null : finalScores[soloIndex].participantId,
      );
    }

    return Result.ok(List<ParticipantFixtureScore>.unmodifiable(finalScores));
  }
}
