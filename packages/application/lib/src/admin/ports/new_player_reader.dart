import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Why a player's name may not be his real one (script 202): a hint for
/// the admin, never a verdict.
enum NewPlayerNameHint {
  /// The name the database gave from the e-mail; the player chose none.
  automatic,

  /// The name holds digits.
  digits,

  /// One word only.
  oneWord,

  /// Its first word is a title or nickname (ملك، بطل، دكتور ...).
  title,

  /// Latin letters only.
  latin,
}

/// One player who joined recently (`GET /admin/new-players`, script 202).
final class NewPlayer {
  /// Creates the line.
  const NewPlayer({
    required this.user,
    required this.joinedAt,
    required this.phoneAccounts,
    required this.predictions,
    required this.nameHint,
    this.similarTo = const <String>[],
  });

  /// The account.
  final User user;

  /// When the account was created (UTC).
  final DateTime joinedAt;

  /// The most accounts seen on any phone this account was seen on
  /// (migrations 0177 and 0197); 0 when no phone was seen yet.
  final int phoneAccounts;

  /// Every prediction the account sent.
  final int predictions;

  /// Why the name may not be a real one; null when nothing points that way.
  final NewPlayerNameHint? nameHint;

  /// The names of the other accounts whose name shares this one's first and
  /// last part ([User.personKey], script 263): maybe one person behind
  /// several accounts. A hint for the owner, never a verdict.
  final List<String> similarTo;
}

/// Port for the admin's list of the players who joined recently.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class NewPlayerReader {
  /// The plain players (not admins) who joined in the last [days] days,
  /// newest first, at most [limit].
  Future<Result<List<NewPlayer>>> newPlayers({
    required int days,
    required int limit,
  });
}
