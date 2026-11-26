import 'package:application/src/admin/ports/owner_audit_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK341_02
/// The owners' read of their own actions (plan 339 to 348): what each owner
/// seat did on the owner page and inside the admins' tools, the newest
/// first. It only reads; no owner action is refused because of it.
///
/// Only an owner seat: a player is refused by the role gate, any other admin
/// with `admin.owner_only`, and a failed seat lookup refuses too (it fails
/// closed). The [limit] is clamped to `[1, maxLimit]`. Never throws.
final class ListOwnerAudit {
  /// Creates the use-case over its collaborators.
  const ListOwnerAudit({
    required OwnerAuditReader reader,
    required OwnerNotices owners,
  }) : _reader = reader,
       _owners = owners;

  final OwnerAuditReader _reader;
  final OwnerNotices _owners;

  /// How many actions one read returns when no (valid) limit is asked.
  static const int defaultLimit = 200;

  /// The hard cap on one read (a bounded scan).
  static const int maxLimit = 200;

  /// The latest actions of the owner seats, the newest first.
  Future<Result<List<OwnerAuditLine>>> call({
    required AuthenticatedUser principal,
    int? limit,
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
        AppError.invariant('admin.owner_only', 'سجل المالك للمالك وحده.'),
      );
    }
    return _reader.latest(limit: _clampLimit(limit));
  }

  static int _clampLimit(int? limit) {
    if (limit == null || limit <= 0) return defaultLimit;
    if (limit > maxLimit) return maxLimit;
    return limit;
  }
}
