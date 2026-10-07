import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _group = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _inviter = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';

void main() {
  test('an invitation is told once per league and inviter', () {
    final subject = NotificationSubject.groupInvited(
      groupId: const GroupId(_group),
      actorUserId: const UserId(_inviter),
    );
    final again = NotificationSubject.groupInvited(
      groupId: const GroupId(_group),
      actorUserId: const UserId(_inviter),
    );
    final someoneElse = NotificationSubject.groupInvited(
      groupId: const GroupId(_group),
      actorUserId: const UserId(_other),
    );

    expect(subject.kind, NotificationKind.groupInvited);
    expect(subject.groupId, const GroupId(_group));
    expect(subject.actorUserId, const UserId(_inviter));
    expect(subject.dedupeRef, 'group_invited:$_group:$_inviter');
    expect(subject, again);
    expect(subject.dedupeRef == someoneElse.dedupeRef, isFalse);
  });

  test('the kind carries a stable wire token', () {
    expect(NotificationKind.groupInvited.wireValue, 'group_invited');
    expect(
      (NotificationKind.tryParse('group_invited') as Ok<NotificationKind>)
          .value,
      NotificationKind.groupInvited,
    );
  });
}
