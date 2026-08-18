import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: read a round's ranked standings — a **round leaderboard**
/// (Application ADR §2: query separated from command; mirrors
/// [GetSeasonLeaderboard]/[GetHallOfFame], scoped to a single scored round
/// instead of a season or all-time).
///
/// A round leaderboard is a **read-side projection** over the round's
/// already-computed [RoundScore]s (Axiom 5: the SAME points `ScoreRound`
/// already produced — this never computes or stores a point total of its
/// own). It reuses exactly the same visibility gate as [GetRoundScores] (a
/// round is rankable only once [RoundStatus.scored]; only a participant of
/// the round's season may see the competing pool) — this read reveals nothing
/// a caller could not already see via `GET /rounds/{id}/scores`; it only adds
/// the [RoundLeaderboard.rank] ordering the pure domain computes. The two
/// error codes below are therefore intentionally identical to
/// [GetRoundScores]'s, so the client's [ErrorPresenter]-style handling needs
/// no new case.
///
/// Never throws; returns a typed [Result].
final class GetRoundLeaderboard {
  /// Creates the use-case over its collaborators.
  const GetRoundLeaderboard({
    required CompetitionRepository competitionRepository,
    required ScoreRepository scoreRepository,
  }) : _competition = competitionRepository,
       _scores = scoreRepository;

  final CompetitionRepository _competition;
  final ScoreRepository _scores;

  /// Returns the ranked [RoundLeaderboard] for the scored round [roundId],
  /// visible to [principal] as a participant of its season.
  Future<Result<RoundLeaderboard>> call({
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

    // Visibility gate: a round is rankable only once it is scored — same
    // reasoning as GetRoundScores (exposing an in-progress round would reveal
    // partial/absent results).
    if (round.status != RoundStatus.scored) {
      return Result.err(
        AppError.invariant(
          'scoring.round_not_scored',
          'Round scores become visible only after the round is scored '
              '(round is ${round.status.wireValue})',
        ),
      );
    }

    // Membership: only a participant of the season sees the competing pool.
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
          'Only a participant of the season may view its scores',
        ),
      );
    }

    final scoresResult = await _scores.listByRound(rId);
    if (scoresResult is Err<List<RoundScore>>) {
      return Result.err(scoresResult.error);
    }
    final scores = (scoresResult as Ok<List<RoundScore>>).value;

    return RoundLeaderboard.rank(roundId: rId, scores: scores);
  }
}
