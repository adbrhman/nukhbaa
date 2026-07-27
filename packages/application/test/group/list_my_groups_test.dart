import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _caller = 'aaaaaaaa-0000-0000-0000-000000000001';
const _otherOwner = 'bbbbbbbb-0000-0000-0000-000000000002';
const _outsider = 'cccccccc-0000-0000-0000-000000000003';
const _groupA = '11111111-1111-1111-1111-111111111111';
const _groupB = '22222222-2222-2222-2222-222222222222';

InMemoryGroupRepository _repo() => InMemoryGroupRepository()
  // Group A: caller is the owner, joined first (07-01).
  ..seedGroup(storedGroup(id: _groupA, ownerId: _caller))
  ..seedMembership(
    storedMembership(
      id: '33333333-3333-3333-3333-333333333333',
      groupId: _groupA,
      userId: _caller,
      role: GroupRole.owner,
      joinedAt: DateTime.utc(2026, 7, 1),
    ),
  )
  // Group B: owned by someone else, caller joined later (07-05) as a member.
  ..seedGroup(
    storedGroup(id: _groupB, ownerId: _otherOwner, inviteCode: otherCode),
  )
  ..seedMembership(
    storedMembership(
      id: '44444444-4444-4444-4444-444444444444',
      groupId: _groupB,
      userId: _otherOwner,
      role: GroupRole.owner,
      joinedAt: DateTime.utc(2026, 7, 2),
    ),
  )
  ..seedMembership(
    storedMembership(
      id: '55555555-5555-5555-5555-555555555555',
      groupId: _groupB,
      userId: _caller,
      role: GroupRole.member,
      joinedAt: DateTime.utc(2026, 7, 5),
    ),
  );

void main() {
  group('ListMyGroups — ownership read, no per-group gate', () {
    test(
      'returns every group the caller belongs to, most-recently-joined first',
      () async {
        final useCase = ListMyGroups(repository: _repo());
        final result = await useCase.call(
          principal: principalUser(userId: _caller),
        );
        final summaries = (result as Ok<List<MyGroupSummary>>).value;

        expect(summaries.length, 2);
        // Group B joined 07-05 (most recent) comes first, then Group A (07-01).
        expect(summaries[0].group.id.value, _groupB);
        expect(summaries[0].role, GroupRole.member);
        expect(summaries[0].memberCount, 2);
        expect(summaries[1].group.id.value, _groupA);
        expect(summaries[1].role, GroupRole.owner);
        expect(summaries[1].memberCount, 1);
      },
    );

    test('a user in no group gets an empty list, not an error', () async {
      final useCase = ListMyGroups(repository: _repo());
      final result = await useCase.call(
        principal: principalUser(userId: _outsider),
      );
      expect((result as Ok<List<MyGroupSummary>>).value, isEmpty);
    });

    test('propagates a transient lookup failure', () async {
      final repo = _repo()..failNextWith(const AppError.transient('db', 'x'));
      final useCase = ListMyGroups(repository: repo);
      final result = await useCase.call(
        principal: principalUser(userId: _caller),
      );
      expect(
        (result as Err<List<MyGroupSummary>>).error.kind,
        ErrorKind.transient,
      );
    });
  });
}
