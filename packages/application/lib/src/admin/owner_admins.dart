import 'package:application/src/admin/ports/admin_roster.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One admin on the owners' page: the account, and whether it holds an
/// owner seat.
typedef AdminSeat = ({AdminMember member, bool owner});

/// The owners' page of admins: who they are and the latest changes.
typedef AdminRosterView = ({List<AdminSeat> admins, List<RoleChange> changes});

/// The owners' hand on the admins (script 294, migration 0223, item 4 of
/// the owner's report): make a player an admin, take the role back (his
/// sessions end with it), or end an account's sessions; always for a
/// reason of 1 to 200 characters, kept in `admin.role_changes`.
///
/// An owner seat's role is never taken back here, so the last owner can
/// never be disabled (decision Q01); a seat lookup that fails refuses.
/// Only an owner seat; any other admin is refused (`admin.owner_only`), a
/// player by the role gate. Never throws.
// NK294_02
final class OwnerAdmins {
  /// Creates the use-case over its collaborators.
  const OwnerAdmins({required AdminRoster roster, required OwnerNotices owners})
    : _roster = roster,
      _owners = owners;

  final AdminRoster _roster;
  final OwnerNotices _owners;

  /// The longest reason kept.
  static const int maxReason = 200;

  /// Every admin, whether each holds a seat, and the latest changes.
  Future<Result<AdminRosterView>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final Result<List<AdminMember>> admins = await _roster.admins();
    if (admins is Err<List<AdminMember>>) return Result.err(admins.error);
    final Result<List<RoleChange>> changes = await _roster.changes();
    if (changes is Err<List<RoleChange>>) return Result.err(changes.error);
    final List<AdminSeat> seats = <AdminSeat>[];
    for (final AdminMember member in (admins as Ok<List<AdminMember>>).value) {
      seats.add((member: member, owner: await _holdsSeat(member.id)));
    }
    return Result.ok((
      admins: seats,
      changes: (changes as Ok<List<RoleChange>>).value,
    ));
  }

  /// Runs [action] (`promote`, `revoke` or `end_sessions`) on the account
  /// [userId] for [reason]; answers how many sessions ended (0 for a
  /// promotion).
  Future<Result<int>> act({
    required AuthenticatedUser principal,
    required String userId,
    required String action,
    required String? reason,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final UserId by = (gate as Ok<UserId>).value;
    final Result<UserId> parsed = UserId.tryParse(userId);
    if (parsed is Err<UserId>) return Result.err(parsed.error);
    final UserId target = (parsed as Ok<UserId>).value;
    final String why = (reason ?? '').trim();
    if (why.isEmpty || why.length > maxReason) {
      return const Result.err(
        AppError.validation(
          'owner.reason_required',
          'اكتب السبب (200 حرف على الأكثر).',
        ),
      );
    }

    int ended = 0;
    switch (action) {
      case 'promote':
        final Result<bool> promoted = await _roster.setRole(
          user: target,
          admin: true,
        );
        if (promoted is Err<bool>) return Result.err(promoted.error);
        if (!(promoted as Ok<bool>).value) {
          return const Result.err(
            AppError.invariant(
              'owner.not_a_player',
              'هذا الحساب مشرف من قبل، أو غير موجود.',
            ),
          );
        }
      case 'revoke':
        if (await _holdsSeat(target)) {
          return const Result.err(
            AppError.invariant(
              'owner.cannot_revoke_owner',
              'لا يُسحب إشراف صاحب مقعد مالك من هنا.',
            ),
          );
        }
        final Result<bool> demoted = await _roster.setRole(
          user: target,
          admin: false,
        );
        if (demoted is Err<bool>) return Result.err(demoted.error);
        if (!(demoted as Ok<bool>).value) {
          return const Result.err(
            AppError.invariant('owner.not_an_admin', 'هذا الحساب ليس مشرفاً.'),
          );
        }
        final Result<int> revokedOut = await _roster.endSessions(target);
        if (revokedOut is Err<int>) return Result.err(revokedOut.error);
        ended = (revokedOut as Ok<int>).value;
      case 'end_sessions':
        final Result<int> endedOut = await _roster.endSessions(target);
        if (endedOut is Err<int>) return Result.err(endedOut.error);
        ended = (endedOut as Ok<int>).value;
      default:
        return const Result.err(
          AppError.validation(
            'owner.action_invalid',
            'action must be promote, revoke or end_sessions',
          ),
        );
    }

    final Result<void> kept = await _roster.record(
      user: target,
      action: action,
      reason: why,
      by: by,
      sessionsEnded: action == 'promote' ? null : ended,
    );
    if (kept is Err<void>) return Result.err(kept.error);
    return Result.ok(ended);
  }

  /// Whether [user] holds an owner seat; a failed lookup counts as yes,
  /// so an owner is never revoked by a fault.
  Future<bool> _holdsSeat(UserId user) async =>
      switch (await _owners.isOwner(user)) {
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
    final bool seated = switch (await _owners.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
    if (!seated) {
      return const Result.err(
        AppError.invariant('admin.owner_only', 'إدارة المشرفين للمالك وحده.'),
      );
    }
    return Result.ok(principal.userId);
  }
}
