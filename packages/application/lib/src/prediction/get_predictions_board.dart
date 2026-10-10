/// The players' predictions board of one day in ONE read (2026-10-11):
/// for each started fixture asked for, everyone's predictions, the scores
/// and the recorded result, and the reactions -- what the board used to read
/// with three requests per fixture.
///
/// Why: a day of 21 started matches made the board send 63 requests at
/// once; on 2026-10-10 at 22:10 UTC that burst held the server's CPU and
/// its eight database connections for over ten seconds (`db.query_timeout`
/// on the predictions, scores and reactions routes, probe latency 5.5 s).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/list_fixture_predictions.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:application/src/social/ports/prediction_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One fixture of the board.
final class PredictionsBoardColumn {
  /// Creates a column.
  const PredictionsBoardColumn({
    required this.fixtureId,
    this.error,
    this.reveal,
    this.scores = const <ParticipantFixtureScore>[],
    this.result,
    this.reactions,
  });

  /// The fixture asked for.
  final String fixtureId;

  /// Why the fixture is not shown (its predictions' own refusal), or null.
  final AppError? error;

  /// Everyone's predictions with their names; null with [error].
  final FixturePredictionReveal? reveal;

  /// Every participant's score so far; empty before the fixture is scored.
  final List<ParticipantFixtureScore> scores;

  /// The recorded final score, or null before there is one.
  final FixtureResult? result;

  /// The reactions each prediction received; null when they could not be
  /// read (the board then shows the predictions without them).
  final List<PredictionReactionTally>? reactions;
}

/// Query use-case: the predictions board of [GetPredictionsBoard.call]'s
/// fixtures, as one season member sees it.
///
/// **The gate is the predictions' own.** Each fixture goes through
/// [ListFixturePredictions] exactly as `GET .../fixtures/{id}/predictions`
/// does: a member of the season, a fixture linked to it, visible, and kicked
/// off by the server clock. A refused fixture becomes a column with its
/// error, so one refusal never hides the others. Only fixtures that passed
/// the gate are read further.
///
/// **Bounded.** At most [maxFixtures] fixtures, read [parallel] at a time:
/// the board never takes more than that many database connections at once.
/// The scores and the results of every revealed fixture are read in one
/// batched query each.
///
/// Never throws; returns a typed [Result].
final class GetPredictionsBoard {
  /// Creates the use-case over its collaborators.
  const GetPredictionsBoard({
    required ListFixturePredictions reveal,
    required FixtureScoreRepository scores,
    required FixtureResultRepository results,
    required PredictionReactionRepository reactions,
  }) : _reveal = reveal,
       _scores = scores,
       _results = results,
       _reactions = reactions;

  final ListFixturePredictions _reveal;
  final FixtureScoreRepository _scores;
  final FixtureResultRepository _results;
  final PredictionReactionRepository _reactions;

  /// The most fixtures one board may ask for (a day holds about 25).
  static const int maxFixtures = 40;

  /// Fixtures read at the same time.
  static const int parallel = 3;

  /// The board of [fixtureIds] in [seasonId], for [principal].
  Future<Result<List<PredictionsBoardColumn>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required List<String> fixtureIds,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final season = (seasonResult as Ok<SeasonId>).value;

    final ids = <String>[];
    for (final id in fixtureIds) {
      if (!ids.contains(id)) {
        ids.add(id);
      }
    }
    if (ids.isEmpty || ids.length > maxFixtures) {
      return const Result.err(
        AppError.validation(
          'board.fixtures_invalid',
          'Ask for 1 to 40 fixtures',
        ),
      );
    }
    for (final id in ids) {
      final parsed = FixtureRef.tryParse(id);
      if (parsed is Err<FixtureRef>) {
        return Result.err(parsed.error);
      }
    }

    // The gate, fixture by fixture, a few at a time.
    final reveals = <String, Result<FixturePredictionReveal>>{};
    for (var start = 0; start < ids.length; start += parallel) {
      final chunk = ids.sublist(
        start,
        start + parallel > ids.length ? ids.length : start + parallel,
      );
      final answers = await Future.wait([
        for (final id in chunk)
          _reveal(principal: principal, seasonId: seasonId, fixtureId: id),
      ]);
      for (var i = 0; i < chunk.length; i++) {
        reveals[chunk[i]] = answers[i];
      }
    }

    final revealed = <FixtureRef>[
      for (final id in ids)
        if (reveals[id] is Ok<FixturePredictionReveal>)
          (FixtureRef.tryParse(id) as Ok<FixtureRef>).value,
    ];

    // Scores and results of every revealed fixture, one query each.
    final scoresByFixture = <String, List<ParticipantFixtureScore>>{};
    final resultByFixture = <String, FixtureResult>{};
    if (revealed.isNotEmpty) {
      final scoresResult = await _scores.listBySeasonFixtures(revealed);
      if (scoresResult is Err<List<ParticipantFixtureScore>>) {
        return Result.err(scoresResult.error);
      }
      for (final score
          in (scoresResult as Ok<List<ParticipantFixtureScore>>).value) {
        (scoresByFixture[score.fixture.value] ??= <ParticipantFixtureScore>[])
            .add(score);
      }
      final resultsResult = await _results.findByFixtures(revealed);
      if (resultsResult is Err<List<FixtureResult>>) {
        return Result.err(resultsResult.error);
      }
      for (final result in (resultsResult as Ok<List<FixtureResult>>).value) {
        resultByFixture[result.fixture.value] = result;
      }
    }

    // The reactions of every revealed fixture, a few at a time. A failed
    // read leaves that column without reactions.
    final reactionsByFixture = <String, List<PredictionReactionTally>>{};
    for (var start = 0; start < revealed.length; start += parallel) {
      final chunk = revealed.sublist(
        start,
        start + parallel > revealed.length ? revealed.length : start + parallel,
      );
      final answers = await Future.wait([
        for (final fixture in chunk)
          _reactions.tallies(
            seasonId: season,
            fixture: fixture,
            viewer: principal.userId,
          ),
      ]);
      for (var i = 0; i < chunk.length; i++) {
        final answer = answers[i];
        if (answer is Ok<List<PredictionReactionTally>>) {
          reactionsByFixture[chunk[i].value] = answer.value;
        }
      }
    }

    return Result.ok([
      for (final id in ids)
        switch (reveals[id]!) {
          Err<FixturePredictionReveal>(:final error) => PredictionsBoardColumn(
            fixtureId: id,
            error: error,
          ),
          Ok<FixturePredictionReveal>(:final value) => PredictionsBoardColumn(
            fixtureId: id,
            reveal: value,
            scores: scoresByFixture[id] ?? const <ParticipantFixtureScore>[],
            result: resultByFixture[id],
            reactions: reactionsByFixture[id],
          ),
        },
    ]);
  }
}
