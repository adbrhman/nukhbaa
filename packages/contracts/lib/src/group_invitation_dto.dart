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

/// A player who can be invited to a friends' league by name.
final class GroupInviteeDto {
  /// Creates the entry.
  const GroupInviteeDto({required this.userId, required this.displayName});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory GroupInviteeDto.fromJson(Map<String, Object?> json) =>
      GroupInviteeDto(
        userId: json['user_id'] is String ? json['user_id'] as String : '',
        displayName: json['display_name'] is String
            ? json['display_name'] as String
            : '',
      );

  /// The account to invite.
  final String userId;

  /// The player's display name.
  final String displayName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_id': userId,
    'display_name': displayName,
  };
}

/// Body of `GET /groups/invitees?q=NAME`: players whose display name
/// contains the query, exact name first; never the caller.
final class GroupInviteesDto {
  /// Creates the answer.
  const GroupInviteesDto({
    required this.players,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory GroupInviteesDto.fromJson(Map<String, Object?> json) =>
      GroupInviteesDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        players: [
          for (final item in (json['players'] as List<Object?>?) ?? const [])
            if (item is Map<String, Object?>) GroupInviteeDto.fromJson(item),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Matching players, exact name first; never the caller.
  final List<GroupInviteeDto> players;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'players': [for (final p in players) p.toJson()],
  };
}
