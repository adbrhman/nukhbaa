import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A player who can be challenged by name.
final class DuelPlayer {
  /// Creates the entry.
  const DuelPlayer({required this.userId, required this.displayName});

  /// The account to challenge.
  final UserId userId;

  /// Their display name (unique since migration 0084).
  final String displayName;
}

/// Finds players to challenge privately.
abstract interface class DuelPlayerDirectory {
  /// Active players whose display name contains [query], never [excluding],
  /// exact matches first, at most [limit].
  Future<Result<List<DuelPlayer>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  });
}
