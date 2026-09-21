/// Use-case: read the teams the caller follows.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/favorite_team_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the caller's favorite teams (plan P3-1). A caller who never chose
/// any reads [FavoriteTeams.none].
///
/// Only the caller's own, always: the principal is the whole of the
/// authority check, and there is no surface for reading someone else's.
///
/// Never throws; returns a typed [Result].
final class GetMyFavoriteTeams {
  /// Creates the use-case over its repository.
  const GetMyFavoriteTeams({required FavoriteTeamRepository favorites})
    : _favorites = favorites;

  final FavoriteTeamRepository _favorites;

  /// Reads [principal]'s teams.
  Future<Result<FavoriteTeams>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _favorites.favoritesOf(principal.userId);
  }
}
