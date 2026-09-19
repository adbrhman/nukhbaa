/// Request body of `POST /me/time-zone`.
///
/// The owner is deliberately absent: the server binds it from the verified
/// bearer token, never a body field (Security ADR §2), so a caller cannot
/// set another account's notification clock.
final class TimeZoneReportRequestDto {
  /// Creates the report.
  const TimeZoneReportRequestDto({required this.utcOffsetMinutes});

  /// Deserializes from a JSON map.
  factory TimeZoneReportRequestDto.fromJson(Map<String, Object?> json) {
    return TimeZoneReportRequestDto(
      utcOffsetMinutes: json['utc_offset_minutes']! as int,
    );
  }

  /// Minutes the calling device's clock is ahead of UTC (Riyadh is 180, a
  /// zone west of UTC is negative).
  ///
  /// An offset, not a zone name: it carries no daylight-saving rule, which is
  /// why the app sends it on every launch rather than once.
  final int utcOffsetMinutes;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'utc_offset_minutes': utcOffsetMinutes};

  @override
  bool operator ==(Object other) =>
      other is TimeZoneReportRequestDto &&
      other.utcOffsetMinutes == utcOffsetMinutes;

  @override
  int get hashCode => utcOffsetMinutes.hashCode;
}

/// Response body of `POST /me/time-zone`.
///
/// Carries no echo of the offset: the device just sent it and has no reason
/// to read the platform's copy.
final class TimeZoneAckDto {
  /// Creates the acknowledgement.
  const TimeZoneAckDto({
    required this.recorded,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory TimeZoneAckDto.fromJson(Map<String, Object?> json) {
    return TimeZoneAckDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      recorded: json['recorded']! as bool,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Always `true` on a 200 — the write is unconditional, so there is no
  /// meaningful `false`. The field exists so the body is a JSON object the
  /// client parses like every other response, not an empty special case.
  final bool recorded;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recorded': recorded,
  };

  @override
  bool operator ==(Object other) =>
      other is TimeZoneAckDto &&
      other.recorded == recorded &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(recorded, schemaVersion);
}
