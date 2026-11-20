import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK294_01
/// One admin account (script 294).
final class AdminMember {
  /// Creates the member.
  const AdminMember({
    required this.id,
    required this.displayName,
    required this.active,
    this.email,
  });

  /// The account.
  final UserId id;

  /// Its display name.
  final String displayName;

  /// Its e-mail, when it has one.
  final String? email;

  /// Whether it is active (not suspended).
  final bool active;
}

/// One change the owners made to an admin (script 294, migration 0223).
final class RoleChange {
  /// Creates the line.
  const RoleChange({
    required this.userName,
    required this.action,
    required this.reason,
    required this.at,
    this.byName,
    this.sessionsEnded,
  });

  /// The account changed, by its display name.
  final String userName;

  /// `promote`, `revoke` or `end_sessions`.
  final String action;

  /// Why.
  final String reason;

  /// The owner seat who made it, by name; null when gone.
  final String? byName;

  /// When (UTC).
  final DateTime at;

  /// How many sessions were ended, when it ended any.
  final int? sessionsEnded;
}

/// Port for the owners' hand on the admins (script 294, migration 0223).
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class AdminRoster {
  /// Every admin account, by name.
  Future<Result<List<AdminMember>>> admins();

  /// Makes the player [user] an admin ([admin] true), or the admin [user]
  /// a player again. False when [user] is not in the other role (or
  /// deleted): nothing changed.
  Future<Result<bool>> setRole({required UserId user, required bool admin});

  /// Signs [user] out of every phone; answers how many sessions ended.
  Future<Result<int>> endSessions(UserId user);

  /// Keeps [action] on [user] for [reason], by [by].
  Future<Result<void>> record({
    required UserId user,
    required String action,
    required String reason,
    required UserId by,
    int? sessionsEnded,
  });

  /// The latest changes, the newest first.
  Future<Result<List<RoleChange>>> changes({int limit = 30});
}
