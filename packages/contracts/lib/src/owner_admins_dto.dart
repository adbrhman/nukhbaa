// NK294_04
/// One admin on the owners' page (script 294).
final class OwnerAdminDto {
  /// Creates the line.
  const OwnerAdminDto({
    required this.id,
    required this.displayName,
    required this.active,
    required this.isOwner,
    this.email,
  });

  /// Deserializes from a JSON map.
  factory OwnerAdminDto.fromJson(Map<String, Object?> json) => OwnerAdminDto(
    id: json['id']! as String,
    displayName: json['display_name']! as String,
    email: json['email'] as String?,
    active: json['active']! as bool,
    isOwner: json['is_owner']! as bool,
  );

  /// The account id.
  final String id;

  /// Its display name.
  final String displayName;

  /// Its e-mail, when it has one.
  final String? email;

  /// Whether it is active (not suspended).
  final bool active;

  /// Whether it holds an owner seat.
  final bool isOwner;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'email': email,
    'active': active,
    'is_owner': isOwner,
  };

  @override
  bool operator ==(Object other) =>
      other is OwnerAdminDto &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.active == active &&
      other.isOwner == isOwner;

  @override
  int get hashCode => Object.hash(id, displayName, email, active, isOwner);
}

/// One change the owners made to an admin (script 294).
final class RoleChangeDto {
  /// Creates the line.
  const RoleChangeDto({
    required this.userName,
    required this.action,
    required this.reason,
    required this.at,
    this.byName,
    this.sessionsEnded,
  });

  /// Deserializes from a JSON map.
  factory RoleChangeDto.fromJson(Map<String, Object?> json) => RoleChangeDto(
    userName: json['user_name']! as String,
    action: json['action']! as String,
    reason: json['reason']! as String,
    byName: json['by_name'] as String?,
    at: DateTime.parse(json['at']! as String).toUtc(),
    sessionsEnded: json['sessions_ended'] as int?,
  );

  /// The account changed, by name.
  final String userName;

  /// `promote`, `revoke` or `end_sessions`.
  final String action;

  /// Why.
  final String reason;

  /// The owner seat who made it, by name.
  final String? byName;

  /// When (UTC).
  final DateTime at;

  /// How many sessions were ended.
  final int? sessionsEnded;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_name': userName,
    'action': action,
    'reason': reason,
    'by_name': byName,
    'at': at.toUtc().toIso8601String(),
    'sessions_ended': sessionsEnded,
  };

  @override
  bool operator ==(Object other) =>
      other is RoleChangeDto &&
      other.userName == userName &&
      other.action == action &&
      other.reason == reason &&
      other.byName == byName &&
      other.at == at &&
      other.sessionsEnded == sessionsEnded;

  @override
  int get hashCode =>
      Object.hash(userName, action, reason, byName, at, sessionsEnded);
}

/// The wire shape of `GET /owner/admins` (script 294).
final class OwnerAdminsDto {
  /// Creates the DTO.
  const OwnerAdminsDto({
    required this.admins,
    required this.changes,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory OwnerAdminsDto.fromJson(Map<String, Object?> json) => OwnerAdminsDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    admins: [
      for (final line in json['admins']! as List<Object?>)
        OwnerAdminDto.fromJson(line! as Map<String, Object?>),
    ],
    changes: [
      for (final line in json['changes']! as List<Object?>)
        RoleChangeDto.fromJson(line! as Map<String, Object?>),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Every admin, by name.
  final List<OwnerAdminDto> admins;

  /// The latest changes, the newest first.
  final List<RoleChangeDto> changes;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'admins': [for (final line in admins) line.toJson()],
    'changes': [for (final line in changes) line.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! OwnerAdminsDto ||
        other.schemaVersion != schemaVersion ||
        other.admins.length != admins.length ||
        other.changes.length != changes.length) {
      return false;
    }
    for (var i = 0; i < admins.length; i++) {
      if (other.admins[i] != admins[i]) return false;
    }
    for (var i = 0; i < changes.length; i++) {
      if (other.changes[i] != changes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    Object.hashAll(admins),
    Object.hashAll(changes),
  );
}
