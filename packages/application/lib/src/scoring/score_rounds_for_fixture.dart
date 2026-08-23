import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/scoring/score_round.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: re-score every round a fixture belongs to (Phase: احتساب فوري —
/// live/partial scoring).
///
/// A fixture carries no round/competition reference of its own (Axiom 3), so
/// recording or correcting its actual result cannot know by itself which
/// round(s) to refresh. This use-case is the fan-out: it resolves every round
/// the fixture is linked to ([CompetitionRepository.listRoundsByFixture]) and
/// runs [ScoreRound] against each one, so an admin recording a fixture's
/// result immediately sees an up-to-date, live leaderboard for every round it
/// feeds — no manual "score this round" step, and no waiting for the round to
/// lock (fixtures still without a result grade `pending`, see
/// [FixtureScoreGrade.pending]).
///
/// Never throws; returns a typed [Result]. Stops and reports the first
/// per-round failure it hits — a partial fan-out failure is a caller-visible
/// error, never silently swallowed.
final class ScoreRoundsForFixture {
  /// Creates the use-case over its collaborators.
  const ScoreRoundsForFixture({
    required CompetitionRepository competitionRepository,
    required ScoreRound scoreRound,
  }) : _competition = competitionRepository,
       _scoreRound = scoreRound;

  final CompetitionRepository _competition;
  final ScoreRound _scoreRound;

  /// Re-scores every round [fixtureId] is linked to, on behalf of admin
  /// [principal]. Returns the combined [RoundScore]s from every round scored,
  /// in round-id order. A fixture linked to no round scores nothing and
  /// returns `Ok(<empty list>)` — not an error.
  Future<Result<List<RoundScore>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    final roundIdsResult = await _competition.listRoundsByFixture(fixture);
    if (roundIdsResult is Err<List<RoundId>>) {
      return Result.err(roundIdsResult.error);
    }
    final roundIds = (roundIdsResult as Ok<List<RoundId>>).value;

    final allScores = <RoundScore>[];
    for (final roundId in roundIds) {
      final scored = await _scoreRound.call(
        principal: principal,
        roundId: roundId.value,
      );
      if (scored is Err<List<RoundScore>>) {
        return Result.err(scored.error);
      }
      allScores.addAll((scored as Ok<List<RoundScore>>).value);
    }

    return Result.ok(List<RoundScore>.unmodifiable(allScores));
  }
}
