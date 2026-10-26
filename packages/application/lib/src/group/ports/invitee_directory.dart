import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A player who can be invited to a friends' league by name.
final class GroupInvitee {
  /// Creates the entry.
  const GroupInvitee({required this.userId, required this.displayName});

  /// The account to invite.
  final UserId userId;

  /// Their display name (unique since migration 0084).
  final String displayName;
}

/// Finds players to invite to a friends' league.
abstract interface class InviteeDirectory {
  /// Active players whose display name contains [query], never [excluding],
  /// exact matches first, at most [limit].
  Future<Result<List<GroupInvitee>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  });
}
