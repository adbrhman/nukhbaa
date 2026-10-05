import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/duel_player_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: find a player to challenge privately by name.
///
/// Fewer than [minQueryLength] characters answers nothing rather than the
/// whole player list; the caller is never in the answer.
final class SearchDuelPlayers {
  /// Creates the use-case.
  const SearchDuelPlayers({required DuelPlayerDirectory players})
    : _players = players;

  final DuelPlayerDirectory _players;

  /// Shortest query searched.
  static const int minQueryLength = 2;

  /// Most players answered.
  static const int limit = 20;

  /// Searches for [query] on behalf of [principal].
  Future<Result<List<DuelPlayer>>> call({
    required AuthenticatedUser principal,
    required String query,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final String trimmed = query.trim();
    if (trimmed.length < minQueryLength) {
      return const Result.ok(<DuelPlayer>[]);
    }
    return _players.search(
      query: trimmed,
      excluding: principal.userId,
      limit: limit,
    );
  }
}
