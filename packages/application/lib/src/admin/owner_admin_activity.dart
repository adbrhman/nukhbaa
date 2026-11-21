import 'package:application/src/admin/ports/admin_activity_log.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK300_03
/// The owners' read of what the admins changed (script 300, owner decision
/// 2026-11-21): every change, the newest first, with the admin's name and
/// the player or match it touched. It only reads: nothing an admin does is
/// refused because of it.
///
/// Only an owner seat; any other admin is refused (`admin.owner_only`), a
/// player by the role gate. Never throws.
final class OwnerAdminActivity {
  /// Creates the use-case over its collaborators.
  const OwnerAdminActivity({
    required AdminActivityLog log,
    required OwnerNotices owners,
  }) : _log = log,
       _owners = owners;

  final AdminActivityLog _log;
  final OwnerNotices _owners;

  /// How many changes one read returns.
  static const int limit = 200;

  /// The latest changes, the newest first.
  Future<Result<List<AdminActivity>>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<AuthenticatedUser> role = Authorization.requireRole(
      principal,
      PlatformRole.admin,
    );
    if (role is Err<AuthenticatedUser>) return Result.err(role.error);
    final bool seated = switch (await _owners.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
    if (!seated) {
      return const Result.err(
        AppError.invariant('admin.owner_only', 'سجل المشرفين للمالك وحده.'),
      );
    }
    return _log.latest(limit: limit);
  }
}
