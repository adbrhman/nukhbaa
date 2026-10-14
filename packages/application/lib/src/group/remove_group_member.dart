import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/group/ports/group_roster_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: the owner removes a member from a friends' league (audit M-26).
/// Rotating the invite code stopped new strangers but kept the ones already
/// in; now the owner can take them out.
///
/// Owner-only, by the per-group role (decision #2): a member is refused
/// `group.not_owner`, a non-member `group.not_a_member` (no existence
/// oracle, decision #3). The owner cannot remove themselves
/// (`group.owner_cannot_leave`); someone who is not in the league is
/// `group.member_not_found`.
///
/// Never throws; returns a typed [Result].
final class RemoveGroupMember {
  /// Creates the use-case over its collaborators.
  const RemoveGroupMember({
    required GroupRepository groups,
    required GroupRosterStore roster,
  }) : _groups = groups,
       _roster = roster;

  final GroupRepository _groups;
  final GroupRosterStore _roster;

  /// Removes [memberUserId] from [groupId] on behalf of [principal].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String memberUserId,
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
    final memberResult = UserId.tryParse(memberUserId);
    if (memberResult is Err<UserId>) {
      return Result.err(memberResult.error);
    }
    final member = (memberResult as Ok<UserId>).value;

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
    if (member.value == principal.userId.value) {
      return const Result.err(
        AppError.invariant(
          'group.owner_cannot_leave',
          'أنت مالك هذا الدوري، فلا يمكنك إخراج نفسك منه. احذفه إن لم تعد تريده.',
        ),
      );
    }

    final removed = await _roster.removeMembership(gId, member);
    return switch (removed) {
      Ok<bool>(:final value) when value => const Result.ok(null),
      Ok<bool>() => const Result.err(
        AppError.invariant(
          'group.member_not_found',
          'هذا اللاعب ليس عضواً في الدوري.',
        ),
      ),
      Err<bool>(:final error) => Result.err(error),
    };
  }
}
