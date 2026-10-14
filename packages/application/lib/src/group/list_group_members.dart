import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/group/ports/group_roster_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: list a group's members (Application ADR §2: a query intent
/// `ListGroupMembers`, separated from commands).
///
/// **Member-only visibility gate (decision #3, mirror of the season-membership
/// gate):** only a member of the group may read its roster. A caller who is not
/// a member is refused [ErrorKind.authorization] `group.not_a_member`,
/// identically whether or not the group exists — so the response is never a
/// group-existence oracle for a non-member (private-by-default, invite-only
/// discovery). There is no admin/owner gate here — every member may see who
/// else is in their circle (Axiom 1, social-first).
///
/// The principal's membership is resolved from the verified token, never the
/// body (Security ADR §2). The returned memberships are in the repository's
/// joinedAt-ascending order (the owner, who joined first, appears first).
///
/// [withNames] adds each member's display name from a [GroupRosterStore]
/// (batch 141: the owner sees who he removes); without one, or when that
/// read fails, the roster comes without names rather than not at all.
///
/// Never throws; returns a typed [Result].
final class ListGroupMembers {
  /// Creates the use-case over its collaborators.
  const ListGroupMembers({
    required GroupRepository repository,
    GroupRosterStore? roster,
  }) : _repository = repository,
       _roster = roster;

  final GroupRepository _repository;
  final GroupRosterStore? _roster;

  /// The roster of [groupId] with its members' display names, by user id.
  Future<Result<GroupRosterView>> withNames({
    required AuthenticatedUser principal,
    required String groupId,
  }) async {
    final listed = await call(principal: principal, groupId: groupId);
    if (listed is Err<List<GroupMembership>>) {
      return Result.err(listed.error);
    }
    final members = (listed as Ok<List<GroupMembership>>).value;
    final roster = _roster;
    if (roster == null || members.isEmpty) {
      return Result.ok(GroupRosterView(members: members));
    }
    final names = await roster.memberDisplayNames(members.first.groupId);
    return Result.ok(
      GroupRosterView(
        members: members,
        names: switch (names) {
          Ok<Map<String, String>>(:final value) => value,
          Err<Map<String, String>>() => const <String, String>{},
        },
      ),
    );
  }

  /// Lists the members of group [groupId], visible to [principal] as a member.
  Future<Result<List<GroupMembership>>> call({
    required AuthenticatedUser principal,
    required String groupId,
  }) async {
    // Layer 1: platform authority — any signed-in user.
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final groupIdResult = GroupId.tryParse(groupId);
    if (groupIdResult is Err<GroupId>) {
      return Result.err(groupIdResult.error);
    }
    final gId = (groupIdResult as Ok<GroupId>).value;

    // Layer 2 (visibility): the caller must be a member. A non-member is refused
    // identically whether or not the group exists (no existence oracle —
    // decision #3, mirror of `leaderboard.not_a_participant`).
    final membershipResult = await _repository.findMembership(
      gId,
      principal.userId,
    );
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may view its members',
        ),
      );
    }

    // Read the roster. The membership gate above already proved existence to
    // this member, so this list is theirs to see.
    return _repository.listMemberships(gId);
  }
}

/// A league's roster with its members' display names (by user id).
final class GroupRosterView {
  /// Pairs [members] with their [names].
  const GroupRosterView({
    required this.members,
    this.names = const <String, String>{},
  });

  /// The memberships, owner first.
  final List<GroupMembership> members;

  /// Display names by user id; a member without one is absent.
  final Map<String, String> names;
}
