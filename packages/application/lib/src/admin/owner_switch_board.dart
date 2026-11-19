import 'package:application/src/admin/ports/owner_switches.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owners' switch board (script 289, migration 0218, item 3 of the
/// owner's report): every owner switch, its state and its last change, and
/// a hand to turn one on or off, always for a reason. First the month's
/// crowning (decision Q04), until now turned from the SQL editor.
///
/// Only an owner seat ([OwnerNotices.isOwner]); any other admin is refused
/// (`admin.owner_only`), a player by the role gate. The `/owner` gate
/// answers them as a path with no route before this is reached; this
/// refuses them again, and a failed seat lookup refuses. Who changed a
/// switch is kept on its row, and the request in the owners' own audit log
/// (script 287). Never throws.
// NK289_02
final class OwnerSwitchBoard {
  /// Creates the use-case over its collaborators.
  const OwnerSwitchBoard({
    required OwnerSwitchSettings settings,
    required OwnerNotices owners,
  }) : _settings = settings,
       _owners = owners;

  final OwnerSwitchSettings _settings;
  final OwnerNotices _owners;

  /// The longest reason kept.
  static const int maxReason = 200;

  /// Every switch, in [OwnerSwitch] order.
  Future<Result<List<OwnerSwitchState>>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    return _settings.all();
  }

  /// Turns the switch [key] on or off ([on]) for [reason], and answers it
  /// as it now stands.
  Future<Result<OwnerSwitchState>> set({
    required AuthenticatedUser principal,
    required String key,
    required bool on,
    required String? reason,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final OwnerSwitch? which = OwnerSwitch.byKey(key);
    if (which == null) {
      return const Result.err(
        AppError.validation(
          'owner.switch_unknown',
          'لا يوجد مفتاح بهذا الاسم.',
        ),
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
    final Result<void> written = await _settings.set(
      which: which,
      on: on,
      reason: why,
      by: (gate as Ok<UserId>).value,
    );
    if (written is Err<void>) return Result.err(written.error);
    final Result<List<OwnerSwitchState>> all = await _settings.all();
    if (all is Err<List<OwnerSwitchState>>) return Result.err(all.error);
    for (final OwnerSwitchState state
        in (all as Ok<List<OwnerSwitchState>>).value) {
      if (state.which == which) return Result.ok(state);
    }
    return const Result.err(
      AppError.transient('ops.row_corrupt', 'An owner switch has no row'),
    );
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
        AppError.invariant('admin.owner_only', 'مفاتيح التشغيل للمالك وحده.'),
      );
    }
    return Result.ok(principal.userId);
  }
}
