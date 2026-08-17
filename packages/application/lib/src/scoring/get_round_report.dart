import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: a round's report — every participant's correct/incorrect
/// fixture-grade counts and total points, aggregated from the already-scored
/// round (Task 5, Session decision: server-side aggregation, not a
/// client-side merge — no new points math, one moment of truth — Axioms 2/5).
///
/// Shares [GetRoundScores]'s visibility gate exactly (same collaborators,
/// same round-scored + season-participant checks): a report is just a
/// grouped read over the same scored data.
final class GetRoundReport {
  /// Creates the use-case over its collaborators.
  const GetRoundReport({
    required CompetitionRepository competitionRepository,
    required ScoreRepository scoreRepository,
  }) : _competition = competitionRepository,
       _scores = scoreRepository;

  final CompetitionRepository _competition;
  final ScoreRepository _scores;

  /// Builds the report for the scored round [roundId], visible to
  /// [principal] as a participant of its season.
  Future<Result<List<RoundReportEntry>>> call({
    required AuthenticatedUser principal,
    required String roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
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

    if (round.status != RoundStatus.scored) {
      return Result.err(
        AppError.invariant(
          'scoring.round_not_scored',
          'Round scores become visible only after the round is scored '
              '(round is ${round.status.wireValue})',
        ),
      );
    }

    final participantResult = await _competition.findParticipant(
      round.seasonId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant == null) {
      return const Result.err(
        AppError.authorization(
          'scoring.not_a_participant',
          'Only a participant of the season may view its report',
        ),
      );
    }

    final scoresResult = await _scores.listByRound(rId);
    if (scoresResult is Err<List<RoundScore>>) {
      return Result.err(scoresResult.error);
    }
    final scores = (scoresResult as Ok<List<RoundScore>>).value;

    return Result.ok([
      for (final score in scores) RoundReportEntry.fromScore(score),
    ]);
  }
}
