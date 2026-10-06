import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/duel_record_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: how many duels each player of a season won, shown beside
/// their name on the month's leaderboard (phase 1 of the plan: the features
/// are seen where the players already look).
///
/// The gate is the leaderboard's own: only a member of the season sees it,
/// refused otherwise as [ErrorKind.authorization]
/// `leaderboard.not_a_participant`. Wins carry no points (decided
/// 2026-10-06); they are a record, never a rank.
///
/// Never throws; returns a typed [Result].
final class ListSeasonDuelWins {
  /// Creates the use-case over its collaborators.
  const ListSeasonDuelWins({
    required CompetitionRepository competition,
    required DuelRecordReader records,
  }) : _competition = competition,
       _records = records;

  final CompetitionRepository _competition;
  final DuelRecordReader _records;

  /// The duel wins of [seasonId] for [principal], a member of it.
  Future<Result<Map<ParticipantId, int>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final SeasonId season = (seasonResult as Ok<SeasonId>).value;
    final member = await _competition.findParticipant(season, principal.userId);
    if (member is Err<Participant?>) {
      return Result.err(member.error);
    }
    if ((member as Ok<Participant?>).value == null) {
      return const Result.err(
        AppError.authorization(
          'leaderboard.not_a_participant',
          'Only a member of the season may view its leaderboard',
        ),
      );
    }
    return _records.winsInSeason(season);
  }
}
