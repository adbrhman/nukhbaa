import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _owner = 'aaaaaaaa-0000-4000-8000-000000000001';
const _member = 'bbbbbbbb-0000-4000-8000-000000000002';
const _stranger = 'cccccccc-0000-4000-8000-000000000003';
const _groupId = '11111111-1111-4111-8111-111111111111';

InMemoryGroupRepository _repo() => InMemoryGroupRepository()
  ..seedGroup(storedGroup(id: _groupId, ownerId: _owner))
  ..seedMembership(
    storedMembership(
      id: '22222222-2222-4222-8222-222222222221',
      groupId: _groupId,
      userId: _owner,
      role: GroupRole.owner,
    ),
  )
  ..seedMembership(
    storedMembership(
      id: '22222222-2222-4222-8222-222222222222',
      groupId: _groupId,
      userId: _member,
    ),
  );

void main() {
  group('LeaveGroup (audit M-26)', () {
    test('a member leaves', () async {
      final repo = _repo();
      final result = await LeaveGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _member),
        groupId: _groupId,
      );

      expect(result, isA<Ok<void>>());
      expect(repo.membershipCount(_groupId), 1);
    });

    test('the owner cannot leave; he deletes instead', () async {
      final repo = _repo();
      final result = await LeaveGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
      );

      final error = (result as Err<void>).error;
      expect(error.code, 'group.owner_cannot_leave');
      expect(error.kind, ErrorKind.invariant);
      expect(repo.membershipCount(_groupId), 2);
    });

    test('someone outside is refused as a non-member', () async {
      final repo = _repo();
      final result = await LeaveGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _stranger),
        groupId: _groupId,
      );

      expect((result as Err<void>).error.code, 'group.not_a_member');
    });
  });

  group('RemoveGroupMember (audit M-26)', () {
    test('the owner removes a member', () async {
      final repo = _repo();
      final result = await RemoveGroupMember(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
        memberUserId: _member,
      );

      expect(result, isA<Ok<void>>());
      expect(repo.membershipCount(_groupId), 1);
    });

    test('a member cannot remove anyone', () async {
      final repo = _repo();
      final result = await RemoveGroupMember(groups: repo, roster: repo)(
        principal: principalUser(userId: _member),
        groupId: _groupId,
        memberUserId: _owner,
      );

      expect((result as Err<void>).error.code, 'group.not_owner');
      expect(repo.membershipCount(_groupId), 2);
    });

    test('the owner cannot remove himself', () async {
      final repo = _repo();
      final result = await RemoveGroupMember(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
        memberUserId: _owner,
      );

      expect((result as Err<void>).error.code, 'group.owner_cannot_leave');
    });

    test('someone who is not in the league is not found', () async {
      final repo = _repo();
      final result = await RemoveGroupMember(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
        memberUserId: _stranger,
      );

      expect((result as Err<void>).error.code, 'group.member_not_found');
    });

    test('a malformed user id is refused before any read', () async {
      final repo = _repo();
      final result = await RemoveGroupMember(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
        memberUserId: 'not-a-uuid',
      );

      expect((result as Err<void>).error.kind, ErrorKind.validation);
    });
  });

  group('DeleteGroup (audit M-26)', () {
    test('the owner deletes the league and its memberships', () async {
      final repo = _repo();
      final result = await DeleteGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _owner),
        groupId: _groupId,
      );

      expect(result, isA<Ok<void>>());
      expect(repo.hasGroup(_groupId), isFalse);
      expect(repo.membershipCount(_groupId), 0);
    });

    test('a member cannot delete it', () async {
      final repo = _repo();
      final result = await DeleteGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _member),
        groupId: _groupId,
      );

      expect((result as Err<void>).error.code, 'group.not_owner');
      expect(repo.hasGroup(_groupId), isTrue);
    });

    test('someone outside is refused as a non-member', () async {
      final repo = _repo();
      final result = await DeleteGroup(groups: repo, roster: repo)(
        principal: principalUser(userId: _stranger),
        groupId: _groupId,
      );

      expect((result as Err<void>).error.code, 'group.not_a_member');
    });
  });

  group('JoinGroupByInvite member limit (audit M-26)', () {
    InMemoryGroupRepository full() {
      final repo = InMemoryGroupRepository()
        ..seedGroup(storedGroup(id: _groupId, ownerId: _owner));
      for (var i = 0; i < JoinGroupByInvite.memberLimit; i++) {
        final n = i.toString().padLeft(12, '0');
        repo.seedMembership(
          storedMembership(
            id: '33333333-3333-4333-8333-$n',
            groupId: _groupId,
            userId: '44444444-4444-4444-8444-$n',
            role: i == 0 ? GroupRole.owner : GroupRole.member,
          ),
        );
      }
      return repo;
    }

    test('a newcomer to a full league is refused in Arabic', () async {
      final repo = full();
      final result =
          await JoinGroupByInvite(
            repository: repo,
            idGenerator: FakeIdGenerator([
              '55555555-5555-4555-8555-555555555555',
            ]),
            clock: FakeClock(),
          )(
            principal: principalUser(userId: _stranger),
            inviteCode: sampleCode,
          );

      final error = (result as Err<GroupMembership>).error;
      expect(error.code, 'group.full');
      expect(error.message, contains('50'));
      expect(repo.membershipCount(_groupId), JoinGroupByInvite.memberLimit);
    });

    test('a member of a full league still gets his membership', () async {
      final repo = full();
      final result =
          await JoinGroupByInvite(
            repository: repo,
            idGenerator: FakeIdGenerator([
              '55555555-5555-4555-8555-555555555555',
            ]),
            clock: FakeClock(),
          )(
            principal: principalUser(
              userId: '44444444-4444-4444-8444-000000000003',
            ),
            inviteCode: sampleCode,
          );

      expect(result, isA<Ok<GroupMembership>>());
    });
  });

  group('ListGroupMembers.withNames (batch 141)', () {
    test('the roster comes with its members names', () async {
      final repo = _repo()
        ..seedName(_owner, 'Owner')
        ..seedName(_member, 'Member');

      final result = await ListGroupMembers(repository: repo, roster: repo)
          .withNames(
            principal: principalUser(userId: _member),
            groupId: _groupId,
          );

      final view = (result as Ok<GroupRosterView>).value;
      expect(view.members.map((m) => m.userId.value), [_owner, _member]);
      expect(view.names, {_owner: 'Owner', _member: 'Member'});
    });

    test('without a roster store the names are empty, not an error', () async {
      final repo = _repo();

      final result = await ListGroupMembers(repository: repo).withNames(
        principal: principalUser(userId: _member),
        groupId: _groupId,
      );

      final view = (result as Ok<GroupRosterView>).value;
      expect(view.members, hasLength(2));
      expect(view.names, isEmpty);
    });

    test('a non-member is refused before any name is read', () async {
      final repo = _repo();

      final result = await ListGroupMembers(repository: repo, roster: repo)
          .withNames(
            principal: principalUser(userId: _stranger),
            groupId: _groupId,
          );

      expect((result as Err<GroupRosterView>).error.code, 'group.not_a_member');
    });
  });
}
