import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:application/src/platform/ports/app_mode_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owners' hand on the app's mode (script 292, migration 0222, item 1
/// of the owner's report): normal, read only or closed, always for a
/// reason. The server reads it before every request (`maintenanceGate`).
///
/// Only an owner seat; any other admin is refused (`admin.owner_only`), a
/// player by the role gate, and a failed seat lookup refuses. Never throws.
// NK292_02
final class OwnerAppMode {
  /// Creates the use-case over its collaborators.
  const OwnerAppMode({
    required AppModeStore store,
    required OwnerNotices owners,
  }) : _store = store,
       _owners = owners;

  final AppModeStore _store;
  final OwnerNotices _owners;

  /// The longest reason kept.
  static const int maxReason = 200;

  /// The mode now.
  Future<Result<AppModeState>> state({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    return _store.read();
  }

  /// Sets the mode [wire] for [reason]; answers it as it now stands.
  Future<Result<AppModeState>> set({
    required AuthenticatedUser principal,
    required String wire,
    required String? reason,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final AppMode? mode = AppMode.byWire(wire);
    if (mode == null) {
      return const Result.err(
        AppError.validation('owner.mode_unknown', 'لا يوجد وضع بهذا الاسم.'),
      );
    }
    final String why = (reason ?? '').trim();
    if (why.isEmpty || why.length > maxReason) {
      return const Result.err(
        AppError.validation(
          'owner.reason_required',
          'اكتب السبب (200 حرف على الأكثر).',
        ),
      );
    }
    final Result<void> written = await _store.set(
      mode: mode,
      reason: why,
      by: (gate as Ok<UserId>).value,
    );
    if (written is Err<void>) return Result.err(written.error);
    return _store.read();
  }

  /// The id of [principal] when he holds an owner seat; refused otherwise.
  Future<Result<UserId>> _ownerOnly(AuthenticatedUser principal) async {
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
        AppError.invariant('admin.owner_only', 'وضع التطبيق للمالك وحده.'),
      );
    }
    return Result.ok(principal.userId);
  }
}
