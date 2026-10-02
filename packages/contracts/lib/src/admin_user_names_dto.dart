import 'package:contracts/src/admin_dto.dart';

/// The request body of `POST /admin/users/{id}/display-name`: the new
/// [displayName] and the mandatory [reason] for the audit trail. The target
/// is in the path; the acting admin comes from the verified token.
final class AdminRenameUserRequestDto {
  /// Creates a rename request body.
  const AdminRenameUserRequestDto({
    required this.displayName,
    required this.reason,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map. A missing or non-string field becomes
  /// `null`, so the use-case reports it as a validation failure.
  factory AdminRenameUserRequestDto.fromJson(Map<String, Object?> json) {
    final Object? name = json['display_name'];
    final Object? reason = json['reason'];
    final Object? version = json['schema_version'];
    return AdminRenameUserRequestDto(
      schemaVersion: version is int ? version : 1,
      displayName: name is String ? name : null,
      reason: reason is String ? reason : null,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The new display name.
  final String? displayName;

  /// Why the admin renames the account.
  final String? reason;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    if (displayName != null) 'display_name': displayName,
    if (reason != null) 'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminRenameUserRequestDto &&
      other.displayName == displayName &&
      other.reason == reason &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(displayName, reason, schemaVersion);
}

/// The wire shape of `GET /admin/duplicate-names`: every display name more
/// than one account carries, each as the list of those accounts (oldest
/// first). An empty [groups] list means every chosen name is unique.
final class DuplicateNamesDto {
  /// Creates the duplicate-names DTO.
  const DuplicateNamesDto({
    required this.groups,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory DuplicateNamesDto.fromJson(Map<String, Object?> json) {
    final raw = json['groups']! as List<Object?>;
    return DuplicateNamesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      groups: [
        for (final group in raw)
          [
            for (final user
                in (group! as Map<String, Object?>)['users']! as List<Object?>)
              UserSummaryDto.fromJson(user! as Map<String, Object?>),
          ],
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// One list of accounts per shared name.
  final List<List<UserSummaryDto>> groups;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'groups': [
      for (final group in groups)
        {
          'users': [for (final user in group) user.toJson()],
        },
    ],
  };

  @override
  bool operator ==(Object other) {
    if (other is! DuplicateNamesDto ||
        other.schemaVersion != schemaVersion ||
        other.groups.length != groups.length) {
      return false;
    }
    for (var i = 0; i < groups.length; i++) {
      final mine = groups[i];
      final theirs = other.groups[i];
      if (mine.length != theirs.length) return false;
      for (var j = 0; j < mine.length; j++) {
        if (mine[j] != theirs[j]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    Object.hashAll([for (final group in groups) Object.hashAll(group)]),
  );
}
