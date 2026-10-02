import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: an admin changes another player's display name
/// (`POST /admin/users/{id}/display-name`).
///
/// Why: a player cannot change a chosen name (`UpdateDisplayName` refuses
/// with `identity.display_name_immutable`), and names that were already
/// shared before migration 0084 made them unique stay shared until someone
/// renames one of them. This is that someone.
///
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. require a non-blank [reason] of at most [maxReasonLength] characters
///    (it feeds the audit record, with the old and new names appended);
/// 3. validate the name with the same rule as every other name path
///    ([User.validateDisplayName]);
/// 4. resolve the target ([UserDirectory.findUser]);
/// 5. write it through [UserDirectory.updateDisplayName] -- the same write the
///    player's own choice uses, so the per-request user cache stays fresh and
///    the database refuses a name another player holds
///    (`identity.display_name_taken`, migration 0084);
/// 6. record a [AuditAction.userRenamed] entry, after the write succeeded.
///
/// Setting the account's automatic name (the part of its e-mail before `@`)
/// is allowed on purpose: the app then asks the player to choose a name
/// again. An unchanged name succeeds without writing or auditing anything.
///
/// Never throws; returns the stored [User].
final class AdminRenameUser {
  /// Creates the use-case over its collaborators.
  const AdminRenameUser({
    required UserDirectory userDirectory,
    required AuditRecorder auditRecorder,
  }) : _directory = userDirectory,
       _audit = auditRecorder;

  final UserDirectory _directory;
  final AuditRecorder _audit;

  /// The longest reason accepted. The audit trail keeps up to 500
  /// characters, and the old and new names are appended to the reason.
  static const int maxReasonLength = 300;

  /// Renames [targetUserId] to [displayName] on behalf of the admin
  /// [principal], with the mandatory [reason].
  Future<Result<User>> call({
    required AuthenticatedUser principal,
    required String targetUserId,
    required String? displayName,
    required String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final trimmedReason = reason?.trim() ?? '';
    if (trimmedReason.isEmpty) {
      return const Result.err(
        AppError.validation(
          'admin.rename_reason_required',
          'اكتب سبب تعديل الاسم',
        ),
      );
    }
    if (trimmedReason.length > maxReasonLength) {
      return const Result.err(
        AppError.validation(
          'admin.rename_reason_too_long',
          'السبب طويل جدًا (الحد الأقصى $maxReasonLength حرفًا)',
        ),
      );
    }

    final validated = User.validateDisplayName(displayName ?? '');
    if (validated is Err<String>) {
      return Result.err(validated.error);
    }
    final chosen = (validated as Ok<String>).value;

    final idResult = UserId.tryParse(targetUserId);
    if (idResult is Err<UserId>) {
      return Result.err(idResult.error);
    }
    final targetId = (idResult as Ok<UserId>).value;

    final found = await _directory.findUser(targetId);
    if (found is Err<User?>) {
      return Result.err(found.error);
    }
    final user = (found as Ok<User?>).value;
    if (user == null) {
      return const Result.err(
        AppError.invariant('admin.user_not_found', 'الحساب غير موجود'),
      );
    }
    if (user.displayName == chosen) {
      return Result.ok(user);
    }

    final saved = await _directory.updateDisplayName(targetId, chosen);
    if (saved is Err<User>) {
      return Result.err(saved.error);
    }
    final stored = (saved as Ok<User>).value;

    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.userRenamed,
      targetRef: targetId.value,
      reason: '$trimmedReason | ${user.displayName} -> $chosen',
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }

    return Result.ok(stored);
  }
}
