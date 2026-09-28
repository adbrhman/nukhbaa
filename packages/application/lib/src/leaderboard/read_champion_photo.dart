/// Use-case: a champion's celebration picture, for everyone signed in
/// (migration 0077).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the picture of [userId] crowned in [seasonId]; `Ok(null)` when
/// there is none. The picture is shown to every player, like the avatars on
/// the boards.
///
/// Never throws; returns a typed [Result].
final class ReadChampionPhoto {
  /// Creates the use-case over its store.
  const ReadChampionPhoto({required MonthChampionRepository champions})
    : _champions = champions;

  final MonthChampionRepository _champions;

  /// Runs the use-case for [principal].
  Future<Result<StoredAvatar?>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String userId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final userResult = UserId.tryParse(userId);
    if (userResult is Err<UserId>) {
      return Result.err(userResult.error);
    }
    return _champions.photo(
      season: (seasonResult as Ok<SeasonId>).value,
      user: (userResult as Ok<UserId>).value,
    );
  }
}
