import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/groups/index.dart' as route;
import 'competition_route_harness.dart';

/// Route test for `GET /me/groups` — exercised through the *real* wiring
/// (`context.read<Future<CompositionRoot>>()` → `root.listMyGroups()`) over
/// the in-memory [InMemoryGroupRepository] from [competition_route_harness],
/// mirroring `group_routes_test.dart` / `me_test.dart`.
///
/// This is an OWNERSHIP read (no `group.not_a_member` gate, unlike
/// `GET /groups/{id}`): the assertions below cover that any authenticated
/// user gets back exactly their own roster, ordered joined-at descending, and
/// that a user in no group gets an empty (not error) list.
void main() {
  CompositionRoot rootFor(InMemoryGroupRepository groups) =>
      CompositionRoot.forTesting(
        listMyGroups: ListMyGroups(repository: groups),
      );

  group('GET /me/groups', () {
    test('returns the caller\'s groups, most-recently-joined first', () async {
      final groups = InMemoryGroupRepository()
        ..seedGroup(storedGroup())
        ..seedMembership(
          storedMembership(
            id: kOwnerMembershipId,
            userId: kOwnerUserId,
            role: GroupRole.owner,
            joinedAt: DateTime.utc(2026, 7, 1),
          ),
        )
        ..seedGroup(
          storedGroup(
            id: '66666666-1111-1111-1111-111111111111',
            ownerId: kMemberUserId,
            inviteCode: kRotatedInviteCode,
          ),
        )
        ..seedMembership(
          storedMembership(
            id: '66666666-2222-2222-2222-222222222222',
            groupId: '66666666-1111-1111-1111-111111111111',
            userId: kOwnerUserId,
            role: GroupRole.member,
            joinedAt: DateTime.utc(2026, 7, 5),
          ),
        );

      final response = await route.onRequest(
        wireContext(
          root: rootFor(groups),
          principal: ownerPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final rows = (body['groups']! as List).cast<Map<Object?, Object?>>();
      expect(rows.length, 2);
      // Second group joined 07-05 (most recent) comes first.
      expect(
        (rows[0]['group']! as Map)['id'],
        '66666666-1111-1111-1111-111111111111',
      );
      expect(rows[0]['role'], 'member');
      expect((rows[1]['group']! as Map)['id'], kGroupId);
      expect(rows[1]['role'], 'owner');
      expect((rows[1]['group']! as Map)['member_count'], 1);
    });

    test('a user in no group gets 200 with an empty list', () async {
      final groups = InMemoryGroupRepository();
      final response = await route.onRequest(
        wireContext(
          root: rootFor(groups),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['groups'], isEmpty);
    });

    test('a non-GET method is 405', () async {
      final response = await route.onRequest(
        wireContext(
          root: rootFor(InMemoryGroupRepository()),
          principal: ownerPrincipal(),
          method: HttpMethod.post,
        ),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
