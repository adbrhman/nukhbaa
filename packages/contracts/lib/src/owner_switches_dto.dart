// NK289_11
/// One owner switch in `GET /owner/switches` and the answer of
/// `PUT /owner/switches/{key}` (script 289): whether it is on, and its last
/// change.
final class OwnerSwitchDto {
  /// Creates the line.
  const OwnerSwitchDto({
    required this.key,
    required this.isOn,
    required this.changedAt,
    this.reason,
    this.changedBy,
  });

  /// Deserializes from a JSON map.
  factory OwnerSwitchDto.fromJson(Map<String, Object?> json) {
    return OwnerSwitchDto(
      key: json['key']! as String,
      isOn: json['is_on']! as bool,
      reason: json['reason'] as String?,
      changedBy: json['changed_by'] as String?,
      changedAt: DateTime.parse(json['changed_at']! as String).toUtc(),
    );
  }

  /// Its key, as `crowning`.
  final String key;

  /// Whether it is on.
  final bool isOn;

  /// Why it was last changed; null before any change.
  final String? reason;

  /// Who last changed it, as the reader sees it: [byYou], [byOtherOwner] or
  /// [bySqlEditor]; null before any change.
  final String? changedBy;

  /// When it was last changed (UTC).
  final DateTime changedAt;

  /// [changedBy] when the reader made the last change.
  static const String byYou = 'you';

  /// [changedBy] when the other owner seat made it.
  static const String byOtherOwner = 'other';

  /// [changedBy] when it was made from the SQL editor.
  static const String bySqlEditor = 'sql';

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'key': key,
    'is_on': isOn,
    'reason': reason,
    'changed_by': changedBy,
    'changed_at': changedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is OwnerSwitchDto &&
      other.key == key &&
      other.isOn == isOn &&
      other.reason == reason &&
      other.changedBy == changedBy &&
      other.changedAt == changedAt;

  @override
  int get hashCode => Object.hash(key, isOn, reason, changedBy, changedAt);
}

/// The wire shape of `GET /owner/switches` (script 289): the owners'
/// switches. An owner seat alone reads it.
final class OwnerSwitchesDto {
  /// Creates the DTO.
  const OwnerSwitchesDto({
    required this.switches,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory OwnerSwitchesDto.fromJson(Map<String, Object?> json) {
    return OwnerSwitchesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      switches: [
        for (final line in json['switches']! as List<Object?>)
          OwnerSwitchDto.fromJson(line! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The switches, in the server's order.
  final List<OwnerSwitchDto> switches;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'switches': [for (final line in switches) line.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! OwnerSwitchesDto ||
        other.schemaVersion != schemaVersion ||
        other.switches.length != switches.length) {
      return false;
    }
    for (var i = 0; i < switches.length; i++) {
      if (other.switches[i] != switches[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(switches));
}
