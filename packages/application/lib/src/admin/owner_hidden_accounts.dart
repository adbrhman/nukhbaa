import 'package:application/src/admin/ports/hidden_account_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owner admin's hidden accounts (script 258, migration 0207, decided by
/// the owner on 2026-11-11): first the account Google Play's reviewers sign
/// in with.
///
/// Only an owner -- an active admin holding an owner seat, primary or
/// backup ([OwnerNotices.isOwner], script 285) -- lists, hides or shows an
/// account. Any other admin is refused (`admin.owner_only`) and reads
/// nothing; a plain player is refused by the role gate first. It fails
/// closed: a failed lookup refuses. No owner seat is ever hidden.
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
    final Result<UserId> parsed = UserId.tryParse(targetUserId);
    if (parsed is Err<UserId>) return Result.err(parsed.error);
    final UserId target = (parsed as Ok<UserId>).value;
    if (hidden && await _holdsSeat(target)) {
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

  /// Whether [user] holds an owner seat; a failed lookup counts as yes,
  /// so an owner is never hidden by a fault.
  Future<bool> _holdsSeat(UserId user) async =>
      switch (await _owner.isOwner(user)) {
        Ok<bool>(:final value) => value,
        Err<bool>() => true,
      };

  /// The id of [principal] when he holds an owner seat; refused otherwise.
  Future<Result<UserId>> _ownerOnly(AuthenticatedUser principal) async {
    final Result<AuthenticatedUser> role = Authorization.requireRole(
      principal,
      PlatformRole.admin,
    );
    if (role is Err<AuthenticatedUser>) return Result.err(role.error);
    // NK285_05
    final bool seated = switch (await _owner.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
    if (!seated) {
      return const Result.err(
        AppError.invariant(
          'admin.owner_only',
          'إخفاء الحسابات للمشرف المالك وحده.',
        ),
      );
    }
    return Result.ok(principal.userId);
  }
}
