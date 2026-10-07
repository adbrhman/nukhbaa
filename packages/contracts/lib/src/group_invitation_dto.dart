/// Versioned wire shapes for invitations to a friends' league (migration
/// 0097): the invited player's own list, newest first, each with who
/// invited, to which league, and where it stands.
///
/// Pure data shapes shared by client and server; this file depends on
/// nothing.
library;

/// One invitation, as the invited player sees it.
final class GroupInvitationDto {
  /// Creates the DTO.
  const GroupInvitationDto({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.inviterName,
    required this.status,
    required this.createdAt,
  });

  /// Deserializes from a JSON map.
  factory GroupInvitationDto.fromJson(Map<String, Object?> json) =>
      GroupInvitationDto(
        id: (json['id'] as String?) ?? '',
        groupId: (json['group_id'] as String?) ?? '',
        groupName: (json['group_name'] as String?) ?? '',
        inviterName: (json['inviter_name'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        createdAt: (json['created_at'] as String?) ?? '',
      );

  /// The invitation (UUID string).
  final String id;

  /// The league (UUID string).
  final String groupId;

  /// The league's name.
  final String groupName;

  /// Who invited.
  final String inviterName;

  /// `pending`, `accepted` or `declined`.
  final String status;

  /// When it was sent, ISO-8601 UTC.
  final String createdAt;

  /// Whether the player has not answered yet.
  bool get isPending => status == 'pending';

  /// Serializes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'group_id': groupId,
    'group_name': groupName,
    'inviter_name': inviterName,
    'status': status,
    'created_at': createdAt,
  };
}

/// The response of `GET /groups/invitations`.
final class GroupInvitationsDto {
  /// Creates the DTO.
  const GroupInvitationsDto({
    required this.invitations,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map; an absent list is empty.
  factory GroupInvitationsDto.fromJson(Map<String, Object?> json) =>
      GroupInvitationsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        invitations: <GroupInvitationDto>[
          for (final Object? item
              in (json['invitations'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map<String, Object?>) GroupInvitationDto.fromJson(item),
        ],
      );

  /// The current schema version.
  static const int currentSchemaVersion = 1;

  /// Newest first.
  final List<GroupInvitationDto> invitations;

  /// The schema version of this payload.
  final int schemaVersion;

  /// The invitation to [groupId], or null.
  GroupInvitationDto? forGroup(String? groupId) {
    for (final GroupInvitationDto invitation in invitations) {
      if (invitation.groupId == groupId) return invitation;
    }
    return null;
  }

  /// Serializes to a JSON map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'invitations': [for (final i in invitations) i.toJson()],
  };
}
