import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/leaderboard_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's own season-by-season record -- where they
/// placed, what they scored, and the counts behind their accuracy.
///
/// **Visibility:** always the caller's own record. The repository scopes the
/// read to `principal.userId`, so there is no membership gate to apply here
/// and nothing this use-case can return that belongs to someone else. It
/// deliberately takes no user parameter: a use-case that accepted one would
/// be one refactor away from serving another person's history.
///
/// A caller who has never played yields `Ok(<empty list>)`, never an error.
///
/// Never throws; returns a typed [Result].
final class ListMySeasonRecords {
  /// Creates the use-case over its repository.
  const ListMySeasonRecords({
    required LeaderboardRepository leaderboardRepository,
  }) : _leaderboard = leaderboardRepository;

  final LeaderboardRepository _leaderboard;

  /// Lists [principal]'s seasons, newest first.
  Future<Result<List<ParticipantSeasonRecord>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _leaderboard.userSeasonRecords(userId: principal.userId);
  }
}
