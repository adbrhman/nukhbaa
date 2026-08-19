import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class AdminGetRoundScores {
  const AdminGetRoundScores({
    required CompetitionRepository competitionRepository,
    required ScoreRepository scoreRepository,
  }) : _competition = competitionRepository,
       _scores = scoreRepository;

  final CompetitionRepository _competition;
  final ScoreRepository _scores;

  Future<Result<List<RoundScore>>> call({
    required AuthenticatedUser principal,
    required String roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) return Result.err(roundIdResult.error);
    final rId = (roundIdResult as Ok<RoundId>).value;

    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) return Result.err(roundResult.error);
    final round = (roundResult as Ok<Round>).value;

    if (round.status != RoundStatus.scored) {
      return Result.err(
        AppError.invariant(
          'admin.round_not_scored',
          'Round scores become visible only after the round is scored '
              '(round is ${round.status.wireValue})',
        ),
      );
    }

    return _scores.listByRound(rId);
  }
}
