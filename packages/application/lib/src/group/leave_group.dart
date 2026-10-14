import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/group/ports/group_roster_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: a member leaves a friends' league (audit M-26). Before it, a
/// player who joined by mistake -- or through a link posted in a public
/// chat -- stayed on its board, its feed and its pushes for good.
///
/// The caller leaves as themselves (the token's user, never the body). The
/// owner cannot leave: the league would have no owner, and ownership does
/// not move in this version; the owner deletes the league instead
/// (`group.owner_cannot_leave`). A non-member is refused `group.not_a_member`
/// whether or not the league exists (decision #3).
///
/// Never throws; returns a typed [Result].
final class LeaveGroup {
  /// Creates the use-case over its collaborators.
  const LeaveGroup({
    required GroupRepository groups,
    required GroupRosterStore roster,
  }) : _groups = groups,
       _roster = roster;

  final GroupRepository _groups;
  final GroupRosterStore _roster;

  /// Takes [principal] out of [groupId].
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

    final found = await _groups.findMembership(gId, principal.userId);
    if (found is Err<GroupMembership?>) {
      return Result.err(found.error);
    }
    final membership = (found as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may perform this action',
        ),
      );
    }
    if (membership.isOwner) {
      return const Result.err(
        AppError.invariant(
          'group.owner_cannot_leave',
          'أنت مالك هذا الدوري، فلا يمكنك مغادرته. احذفه إن لم تعد تريده.',
        ),
      );
    }

    final removed = await _roster.removeMembership(gId, principal.userId);
    return switch (removed) {
      Ok<bool>() => const Result.ok(null),
      Err<bool>(:final error) => Result.err(error),
    };
  }
}
