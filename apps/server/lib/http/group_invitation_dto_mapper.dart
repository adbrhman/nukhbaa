import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// Projects the caller's invitations to friends' leagues (migration 0097)
/// onto their wire shape: instants as ISO-8601 UTC strings.
GroupInvitationsDto groupInvitationsToDto(List<GroupInvitation> invitations) =>
    GroupInvitationsDto(
      invitations: <GroupInvitationDto>[
        for (final GroupInvitation i in invitations)
          GroupInvitationDto(
            id: i.id,
            groupId: i.groupId.value,
            groupName: i.groupName,
            inviterName: i.inviterName,
            status: i.status.wireValue,
            createdAt: i.createdAt.toUtc().toIso8601String(),
          ),
      ],
    );
