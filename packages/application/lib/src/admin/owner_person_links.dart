import 'package:application/src/admin/ports/person_link_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One person's accounts, linked by the owner admin (script 263, migration
/// 0209, decided by the owner on 2026-11-12).
///
/// A person may play with two accounts (the rules allow a second one),
/// never more. When one person is found behind several accounts (a close
/// name, one phone), the owner names the main account and, if he wants, a
/// second one: both keep counting, and every other account of that person
/// is hidden from every board, as the owner's own hiding does (0207). It
/// still signs in and predicts. Setting the person again, or unlinking it,
/// shows again what the link hid; nothing is deleted.
///
/// Only the owner admin ([OwnerNotices.ownerId]) reads or changes it; any
/// other admin is refused (`admin.owner_only`), a plain player by the role
/// gate first. It fails closed. The owner's own account is never hidden by
/// a link.
///
/// Never throws.
final class OwnerPersonLinks {
  /// Creates the use-case over its collaborators.
  const OwnerPersonLinks({
    required PersonLinkStore store,
    required OwnerNotices owner,
  }) : _store = store,
       _owner = owner;

  final PersonLinkStore _store;
  final OwnerNotices _owner;

  /// Every linked person.
  Future<Result<List<LinkedPerson>>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    return _store.list();
  }

  /// Sets the person of [mainId]: [mainId] and [secondId] count, [otherIds]
  /// are hidden from every board.
  Future<Result<void>> set({
    required AuthenticatedUser principal,
    required String mainId,
    required String? secondId,
    required List<String> otherIds,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final UserId owner = (gate as Ok<UserId>).value;

    final Result<UserId> main = UserId.tryParse(mainId);
    if (main is Err<UserId>) return Result.err(main.error);
    UserId? second;
    if (secondId != null && secondId.trim().isNotEmpty) {
      final Result<UserId> parsed = UserId.tryParse(secondId);
      if (parsed is Err<UserId>) return Result.err(parsed.error);
      second = (parsed as Ok<UserId>).value;
    }
    final List<UserId> others = <UserId>[];
    for (final String id in otherIds) {
      final Result<UserId> parsed = UserId.tryParse(id);
      if (parsed is Err<UserId>) return Result.err(parsed.error);
      others.add((parsed as Ok<UserId>).value);
    }
    if (others.contains(owner)) {
      return const Result.err(
        AppError.invariant(
          'admin.cannot_hide_owner',
          'لا يمكن إخفاء حساب المالك.',
        ),
      );
    }

    final Result<PersonLinkRefusal?> written = await _store.set(
      main: (main as Ok<UserId>).value,
      second: second,
      others: others,
      by: owner,
    );
    if (written is Err<PersonLinkRefusal?>) return Result.err(written.error);
    return switch ((written as Ok<PersonLinkRefusal?>).value) {
      null => const Result.ok(null),
      PersonLinkRefusal.tooFew => const Result.err(
        AppError.validation(
          'admin.person_too_few',
          'اختر حسابين على الأقل للشخص الواحد.',
        ),
      ),
      PersonLinkRefusal.duplicate => const Result.err(
        AppError.validation(
          'admin.person_duplicate',
          'اخترت الحساب نفسه أكثر من مرة.',
        ),
      ),
      PersonLinkRefusal.unknown => const Result.err(
        AppError.invariant('admin.user_not_found', 'أحد الحسابات غير موجود.'),
      ),
      PersonLinkRefusal.taken => const Result.err(
        AppError.invariant(
          'admin.person_account_taken',
          'أحد الحسابات مربوط بشخص آخر. افكك ربط ذلك الشخص أولاً.',
        ),
      ),
    };
  }

  /// Unlinks the person of [mainId], showing again what the link hid;
  /// answers how many accounts were linked (0 when none).
  Future<Result<int>> unlink({
    required AuthenticatedUser principal,
    required String mainId,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final Result<UserId> main = UserId.tryParse(mainId);
    if (main is Err<UserId>) return Result.err(main.error);
    return _store.unlink((main as Ok<UserId>).value);
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
          'ربط حسابات الشخص الواحد للمشرف المالك وحده.',
        ),
      );
    }
    return Result.ok(owner);
  }
}
