import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: browse platform users by an optional case-insensitive
/// email-contains [search] — the admin "find a user to sanction" flow
/// (admin-only, Security ADR §2.2/§2.3).
///
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. clamp an untrusted [limit] to `[1, maxLimit]`;
/// 3. normalize a blank [search] to `null` (browse-all, still bounded);
/// 4. delegate to [UserAdminRepository.listUsers].
///
/// An empty match is a legitimate empty result, never an error. Never throws.
final class ListUsers {
  const ListUsers({required UserAdminRepository users}) : _users = users;

  final UserAdminRepository _users;

  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  Future<Result<List<User>>> call({
    required AuthenticatedUser principal,
    String? search,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final trimmed = search?.trim();
    return _users.listUsers(
      search: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      limit: _clampLimit(limit),
    );
  }

  static int _clampLimit(int? limit) {
    if (limit == null || limit <= 0) return defaultLimit;
    if (limit > maxLimit) return maxLimit;
    return limit;
  }
}
