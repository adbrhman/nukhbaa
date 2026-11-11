import 'package:application/src/admin/ports/hidden_account_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owner admin's hidden accounts (script 258, migration 0207, decided by
/// the owner on 2026-11-11): first the account Google Play's reviewers sign
/// in with.
///
/// Only the owner admin -- the active admin account with the owner's e-mail
/// ([OwnerNotices.ownerId]) -- lists, hides or shows an account. Any other
/// admin is refused (`admin.owner_only`) and reads nothing; a plain player
/// is refused by the role gate first. It fails closed: no owner found, or a
/// failed lookup, refuses. The owner never hides himself.
///
/// Never throws.
final class OwnerHiddenAccounts {
  /// Creates the use-case over its collaborators.
  const OwnerHiddenAccounts({
    required HiddenAccountStore store,
    required OwnerNotices owner,
  }) : _store = store,
       _owner = owner;

  final HiddenAccountStore _store;
  final OwnerNotices _owner;

  /// Every hidden account, the most recently hidden first.
  Future<Result<List<HiddenAccount>>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    return _store.list();
  }

  /// Hides the account [targetUserId] from every board.
  Future<Result<void>> hide({
    required AuthenticatedUser principal,
    required String targetUserId,
  }) => _set(principal: principal, targetUserId: targetUserId, hidden: true);

  /// Shows the account [targetUserId] again, with the same points.
  Future<Result<void>> show({
    required AuthenticatedUser principal,
    required String targetUserId,
  }) => _set(principal: principal, targetUserId: targetUserId, hidden: false);

  Future<Result<void>> _set({
    required AuthenticatedUser principal,
    required String targetUserId,
    required bool hidden,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final UserId owner = (gate as Ok<UserId>).value;

    final Result<UserId> parsed = UserId.tryParse(targetUserId);
    if (parsed is Err<UserId>) return Result.err(parsed.error);
    final UserId target = (parsed as Ok<UserId>).value;
    if (hidden && target == owner) {
      return const Result.err(
        AppError.invariant(
          'admin.cannot_hide_owner',
          'لا يمكن إخفاء حساب المالك.',
        ),
      );
    }

    final Result<bool> written = hidden
        ? await _store.hide(target)
        : await _store.show(target);
    if (written is Err<bool>) return Result.err(written.error);
    if (!(written as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant('admin.user_not_found', 'No such user'),
      );
    }
    return const Result.ok(null);
  }

  /// The owner admin's id when [principal] is he; refused otherwise.
  Future<Result<UserId>> _ownerOnly(AuthenticatedUser principal) async {
    final Result<AuthenticatedUser> role = Authorization.requireRole(
      principal,
      PlatformRole.admin,
    );
    if (role is Err<AuthenticatedUser>) return Result.err(role.error);
    final Result<UserId?> found = await _owner.ownerId();
    final UserId? owner = switch (found) {
      Ok<UserId?>(:final value) => value,
      Err<UserId?>() => null,
    };
    if (owner == null || owner != principal.userId) {
      return const Result.err(
        AppError.invariant(
          'admin.owner_only',
          'إخفاء الحسابات للمشرف المالك وحده.',
        ),
      );
    }
    return Result.ok(owner);
  }
}
