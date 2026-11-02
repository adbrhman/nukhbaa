import 'package:application/src/admin/ports/new_player_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the players who joined recently (`GET
/// /admin/new-players`, script 202), the screen the new-player push opens,
/// so an admin sees each one's name, whether it looks borrowed, how many
/// accounts share his phone, and can write to him.
///
/// Admin-only. [days] is held within 1..[maxDays]; at most [maxPlayers].
final class AdminListNewPlayers {
  /// Creates the use-case over its reader.
  const AdminListNewPlayers({required NewPlayerReader players})
    : _players = players;

  final NewPlayerReader _players;

  /// The widest window one read covers.
  static const int maxDays = 30;

  /// The most players one read returns.
  static const int maxPlayers = 200;

  /// The players who joined in the last [days] days, for the admin
  /// [principal].
  Future<Result<List<NewPlayer>>> call({
    required AuthenticatedUser principal,
    int days = 7,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final int window = days < 1 ? 1 : (days > maxDays ? maxDays : days);
    return _players.newPlayers(days: window, limit: maxPlayers);
  }
}
