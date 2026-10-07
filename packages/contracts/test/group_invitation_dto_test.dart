import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('an invitation list survives the wire and finds by league', () {
    const GroupInvitationsDto dto = GroupInvitationsDto(
      invitations: <GroupInvitationDto>[
        GroupInvitationDto(
          id: 'i-1',
          groupId: 'g-1',
          groupName: 'Office',
          inviterName: 'Sara',
          status: 'pending',
          createdAt: '2026-10-07T12:00:00.000Z',
        ),
      ],
    );

    final GroupInvitationsDto back = GroupInvitationsDto.fromJson(dto.toJson());

    expect(back.invitations.single.groupName, 'Office');
    expect(back.invitations.single.inviterName, 'Sara');
    expect(back.forGroup('g-1')?.isPending, isTrue);
    expect(back.forGroup('g-2'), isNull);
  });

  test('an empty payload is an empty list', () {
    expect(
      GroupInvitationsDto.fromJson(const <String, Object?>{}).invitations,
      isEmpty,
    );
  });
}
