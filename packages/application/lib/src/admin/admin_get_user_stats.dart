import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the platform-wide user counts for the admin dashboard
/// (Database ADR §3, `identity.users`) — total registered users plus the
/// active/suspended split. Admin-only (Security ADR §2.2/§2.3).
///
/// Unlike `ListUsers` — a bounded browse page for finding one user to
/// sanction, capped at its `maxLimit` — this reads a single server-side
/// aggregate over the WHOLE table, so "how many users does the platform
/// have" no longer depends on a page size.
final class AdminGetUserStats {
  /// Creates the use-case over its collaborator.
  const AdminGetUserStats({required UserAdminRepository users})
    : _users = users;

  final UserAdminRepository _users;

  /// Reads the counts. Admin only; a non-admin is refused
  /// `auth.insufficient_role`.
  Future<Result<UserCounts>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _users.countUsers();
  }
}
