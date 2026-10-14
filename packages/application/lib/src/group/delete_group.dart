import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/group/ports/group_roster_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: the owner deletes a friends' league (audit M-26). Its
/// memberships, invitations, reactions and notifications go with it; the
/// members' points are filed under the month contest, never under a league,
/// so nobody's score changes.
///
/// Owner-only, by the per-group role (decision #2): a member is refused
/// `group.not_owner`, a non-member `group.not_a_member` (no existence
/// oracle, decision #3).
///
/// Never throws; returns a typed [Result].
final class DeleteGroup {
  /// Creates the use-case over its collaborators.
  const DeleteGroup({
    required GroupRepository groups,
    required GroupRosterStore roster,
  }) : _groups = groups,
       _roster = roster;

  final GroupRepository _groups;
  final GroupRosterStore _roster;

  /// Deletes [groupId] on behalf of [principal].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String groupId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final groupIdResult = GroupId.tryParse(groupId);
    if (groupIdResult is Err<GroupId>) {
      return Result.err(groupIdResult.error);
    }
    final gId = (groupIdResult as Ok<GroupId>).value;

    final own = await _groups.findMembership(gId, principal.userId);
    if (own is Err<GroupMembership?>) {
      return Result.err(own.error);
    }
    final caller = (own as Ok<GroupMembership?>).value;
    if (caller == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may perform this action',
        ),
      );
    }
    if (!caller.isOwner) {
      return const Result.err(
        AppError.authorization(
          'group.not_owner',
          'Only the group owner may perform this action',
        ),
      );
    }

    final deleted = await _roster.deleteGroup(gId);
    return switch (deleted) {
      Ok<bool>() => const Result.ok(null),
      Err<bool>(:final error) => Result.err(error),
    };
  }
}
