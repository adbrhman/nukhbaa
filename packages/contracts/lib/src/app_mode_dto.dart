// NK292_04
/// The wire shape of `GET` and `PUT /owner/mode` (script 292): the app's
/// mode and its last change, as the owner seat reading it sees it.
final class AppModeDto {
  /// Creates the DTO.
  const AppModeDto({
    required this.mode,
    required this.changedAt,
    this.reason,
    this.changedBy,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory AppModeDto.fromJson(Map<String, Object?> json) {
    return AppModeDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      mode: json['mode']! as String,
      reason: json['reason'] as String?,
      changedBy: json['changed_by'] as String?,
      changedAt: DateTime.parse(json['changed_at']! as String).toUtc(),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// [mode] when everything works.
  static const String normal = 'normal';

  /// [mode] when the players browse and their writes are refused.
  static const String readOnly = 'read_only';

  /// [mode] when only signing in and deleting an account work.
  static const String closed = 'closed';

  /// [normal], [readOnly] or [closed].
  final String mode;

  /// Why it was last changed; null before any change.
  final String? reason;

  /// Who last changed it: `you`, `other` or `sql`
  /// (`OwnerSwitchDto.byYou` and its siblings); null before any change.
  final String? changedBy;

  /// When it was last changed (UTC).
  final DateTime changedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'mode': mode,
    'reason': reason,
    'changed_by': changedBy,
    'changed_at': changedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppModeDto &&
      other.mode == mode &&
      other.reason == reason &&
      other.changedBy == changedBy &&
      other.changedAt == changedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(mode, reason, changedBy, changedAt, schemaVersion);
}
