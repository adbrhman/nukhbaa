import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/groups/[id]/index.dart' as group_route;
// ignore: always_use_package_imports
import '../../routes/groups/[id]/members/[userId]/index.dart' as member_route;
// ignore: always_use_package_imports
import '../../routes/groups/[id]/members/index.dart' as members_route;
import 'competition_route_harness.dart';

/// Route tests for leaving a league, removing a member and deleting a league
/// (audit M-26), through the real wiring over the harness's in-memory group
/// repository and a roster store that edits the same lists.
void main() {
  ({CompositionRoot root, InMemoryGroupRepository groups}) rootFor() {
    final groups = InMemoryGroupRepository()
      ..seedGroup(storedGroup())
      ..seedMembership(
        storedMembership(
          id: kOwnerMembershipId,
          userId: kOwnerUserId,
          role: GroupRole.owner,
        ),
      )
      ..seedMembership(
        storedMembership(
          id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
          userId: kMemberUserId,
          joinedAt: DateTime.utc(2026, 7, 2),
        ),
      );
    final roster = _Roster(groups)
      ..names[kOwnerUserId] = 'Owner'
      ..names[kMemberUserId] = 'Member';
    final root = CompositionRoot.forTesting(
      listGroupMembers: ListGroupMembers(repository: groups, roster: roster),
      leaveGroup: LeaveGroup(groups: groups, roster: roster),
      removeGroupMember: RemoveGroupMember(groups: groups, roster: roster),
      deleteGroup: DeleteGroup(groups: groups, roster: roster),
    );
    return (root: root, groups: groups);
  }

  Future<Response> deleteMember(
    CompositionRoot root,
    AuthenticatedUser principal,
    String userId,
  ) => member_route.onRequest(
    wireContext(root: root, principal: principal, method: HttpMethod.delete),
    kGroupId,
    userId,
  );

  group('DELETE /groups/{id}/members/{userId}', () {
    test('a member leaves with "me": 200, off the roster', () async {
      final setup = rootFor();

      final response = await deleteMember(setup.root, memberPrincipal(), 'me');

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['left'], isTrue);
      expect(setup.groups.memberships.map((m) => m.userId.value), [
        kOwnerUserId,
      ]);
    });

    test('the owner cannot leave: 409 group.owner_cannot_leave', () async {
      final setup = rootFor();

      final response = await deleteMember(setup.root, ownerPrincipal(), 'me');

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'group.owner_cannot_leave');
      expect(setup.groups.memberships, hasLength(2));
    });

    test('the owner removes a member: 200', () async {
      final setup = rootFor();

      final response = await deleteMember(
        setup.root,
        ownerPrincipal(),
        kMemberUserId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['removed'], isTrue);
      expect(setup.groups.memberships, hasLength(1));
    });

    test('a member cannot remove the owner: 401 group.not_owner', () async {
      final setup = rootFor();

      final response = await deleteMember(
        setup.root,
        memberPrincipal(),
        kOwnerUserId,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(response))['code'], 'group.not_owner');
      expect(setup.groups.memberships, hasLength(2));
    });

    test('only DELETE is served', () async {
      final setup = rootFor();

      final response = await member_route.onRequest(
        wireContext(
          root: setup.root,
          principal: ownerPrincipal(),
          method: HttpMethod.get,
        ),
        kGroupId,
        'me',
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  test('GET /groups/{id}/members names each member (batch 141)', () async {
    final setup = rootFor();

    final response = await members_route.onRequest(
      wireContext(
        root: setup.root,
        principal: memberPrincipal(),
        method: HttpMethod.get,
      ),
      kGroupId,
    );

    expect(response.statusCode, HttpStatus.ok);
    final members = (await decodeBody(response))['members']! as List<Object?>;
    expect(
      [
        for (final m in members.cast<Map<String, Object?>>())
          (m['user_id'], m['role'], m['display_name']),
      ],
      [(kOwnerUserId, 'owner', 'Owner'), (kMemberUserId, 'member', 'Member')],
    );
  });

  group('DELETE /groups/{id}', () {
    test('the owner deletes the league: 200', () async {
      final setup = rootFor();

      final response = await group_route.onRequest(
        wireContext(
          root: setup.root,
          principal: ownerPrincipal(),
          method: HttpMethod.delete,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['deleted'], isTrue);
      expect(setup.groups.groups, isEmpty);
      expect(setup.groups.memberships, isEmpty);
    });

    test('a member cannot delete it: 401 group.not_owner', () async {
      final setup = rootFor();

      final response = await group_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.delete,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(response))['code'], 'group.not_owner');
      expect(setup.groups.groups, hasLength(1));
    });
  });
}

/// A [GroupRosterStore] over the harness repository's own lists.
final class _Roster implements GroupRosterStore {
  _Roster(this._groups);

  final InMemoryGroupRepository _groups;

  /// Display names by user id.
  final Map<String, String> names = <String, String>{};

  @override
  Future<Result<bool>> removeMembership(GroupId groupId, UserId userId) async {
    final before = _groups.memberships.length;
    _groups.memberships.removeWhere(
      (m) =>
          m.groupId.value == groupId.value &&
          m.userId.value == userId.value &&
          !m.isOwner,
    );
    return Result.ok(_groups.memberships.length < before);
  }

  @override
  Future<Result<bool>> deleteGroup(GroupId groupId) async {
    final existed = _groups.groups.remove(groupId.value) != null;
    _groups.memberships.removeWhere((m) => m.groupId.value == groupId.value);
    return Result.ok(existed);
  }

  @override
  Future<Result<Set<String>>> memberParticipantIds(
    GroupId groupId,
    SeasonId seasonId,
  ) async => const Result.ok(<String>{});

  @override
  Future<Result<Map<String, String>>> memberDisplayNames(
    GroupId groupId,
  ) async => Result.ok(names);
}
