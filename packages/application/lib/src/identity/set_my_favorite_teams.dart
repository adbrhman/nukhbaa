/// Use-case: replace the teams the caller follows.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/favorite_team_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Replaces the caller's favorite teams (plan P3-1) and returns what was
/// stored.
///
/// The whole set is sent every time, so the client never has to diff: an
/// empty list clears it. [FavoriteTeams.tryCreate] drops repeats and refuses
/// more than [FavoriteTeams.max] before anything is written. The owner comes
/// from the verified principal, never from the request body.
///
/// Never throws; returns a typed [Result].
final class SetMyFavoriteTeams {
  /// Creates the use-case over its repository.
  const SetMyFavoriteTeams({required FavoriteTeamRepository favorites})
    : _favorites = favorites;

  final FavoriteTeamRepository _favorites;

  /// Stores [teams] as [principal]'s favorite teams.
  Future<Result<FavoriteTeams>> call({
    required AuthenticatedUser principal,
    required List<TeamRef> teams,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final built = FavoriteTeams.tryCreate(teams);
    if (built is Err<FavoriteTeams>) {
      return Result.err(built.error);
    }
    return _favorites.replace(
      principal.userId,
      (built as Ok<FavoriteTeams>).value,
    );
  }
}
