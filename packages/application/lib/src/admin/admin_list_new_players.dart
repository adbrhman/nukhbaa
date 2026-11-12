import 'package:application/src/admin/ports/account_name_directory.dart';
import 'package:application/src/admin/ports/new_player_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the players who joined recently (`GET
/// /admin/new-players`, script 202), the screen the new-player push opens,
/// so an admin sees each one's name, whether it looks borrowed, how many
/// accounts share his phone, and can write to him.
///
/// With [names] (script 263), each player carries the names of the other
/// accounts that share his first and last name ([NewPlayer.similarTo]):
/// maybe one person behind several accounts. A failed read of the names
/// leaves the hint out, never the list.
///
/// Admin-only. [days] is held within 1..[maxDays]; at most [maxPlayers].
final class AdminListNewPlayers {
  /// Creates the use-case over its reader.
  const AdminListNewPlayers({
    required NewPlayerReader players,
    AccountNameDirectory? names,
  }) : _players = players,
       _names = names;

  final NewPlayerReader _players;
  final AccountNameDirectory? _names;

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
    final Result<List<NewPlayer>> read = await _players.newPlayers(
      days: window,
      limit: maxPlayers,
    );
    final AccountNameDirectory? names = _names;
    if (names == null || read is! Ok<List<NewPlayer>> || read.value.isEmpty) {
      return read;
    }
    final Result<List<AccountName>> all = await names.all();
    if (all is! Ok<List<AccountName>>) {
      return read;
    }
    return Result.ok(<NewPlayer>[
      for (final NewPlayer player in read.value)
        NewPlayer(
          user: player.user,
          joinedAt: player.joinedAt,
          phoneAccounts: player.phoneAccounts,
          predictions: player.predictions,
          nameHint: player.nameHint,
          similarTo: <String>[
            for (final AccountName other in accountsLike(
              all.value,
              name: player.user.displayName,
              except: player.user.id,
            ))
              other.displayName,
          ],
        ),
    ]);
  }
}
